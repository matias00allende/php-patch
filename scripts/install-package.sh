#!/bin/bash
# install-package.sh - instala PHP parchado en /opt/phpMM de forma ADITIVA.
# No modifica /usr/bin/php, /etc/php.ini, mod_php ni ningun vhost. No inicia FPM ni activa sitios.
# Uso: sudo ./install-package.sh <dir-paquetes> MM [MM...]
#   <dir-paquetes> contiene SHA256SUMS, *deps*.tar.gz y php-X.Y.Z-el7-opt.tar.gz (ver build/make-package.sh)
# Se puede copiar solo un subconjunto de paquetes: se verifica unicamente lo que se va a usar.
source "$(dirname "$0")/lib.sh"
need_root
ensure_backup install
TPL=${TPL:-$(cd "$(dirname "$0")/../assets/templates" && pwd)}
PKG=$(readlink -f -- "${1:?dir paquetes}") || die "no existe el directorio de paquetes"; shift   # absoluta: despues se hace cd
[ $# -ge 1 ] || die "indicar al menos una version (por ejemplo 83)"
log "== install-package en $(hostname): versiones $*"

# 1) area privada: se copia SOLO lo necesario a un directorio de root (0700, en el mismo sistema de archivos que /opt) y se verifica y extrae
#    desde esa copia, de modo que quien tenga escritura en el directorio de origen no puede cambiar un paquete despues de verificarlo
cd "$PKG" || die "no existe $PKG"
[ -f SHA256SUMS ] || die "falta SHA256SUMS en $PKG"
need=""
for mm in "$@"; do
  valid_mm "$mm"
  t=$(ls php-$(mm_dotted $mm).*-opt.tar.gz 2>/dev/null | sort -V | tail -1) || true
  [ -n "$t" ] || die "falta el paquete php-$(mm_dotted $mm).*-opt.tar.gz en $PKG"
  need="$need $t"
done
if [ ! -d /opt/deps ]; then
  d=$(ls *deps*.tar.gz 2>/dev/null | head -1); [ -n "$d" ] || die "falta el paquete de dependencias (*deps*.tar.gz)"
  need="$need $d"
fi
STG=$(mktemp -d /opt/.php-patch-stg.XXXXXX) || die "no pude crear el area privada en /opt"
chmod 700 "$STG"; trap 'rm -rf -- "$STG"' EXIT
cp -- SHA256SUMS $need "$STG/" || die "no pude copiar los paquetes al area privada"
PKG=$STG; cd "$PKG"

# 2) integridad sobre la copia privada: solo las lineas de SHA256SUMS cuyo archivo esta presente (CentOS 7 no tiene --ignore-missing)
present=$(while read -r h f; do [ -f "$f" ] && echo "$h  $f"; done < SHA256SUMS)
[ -n "$present" ] || die "ningun archivo de SHA256SUMS esta presente"
echo "$present" | sha256sum -c - >/dev/null || die "SHA256 no coincide en $PKG"
for f in $need; do echo "$present" | grep -q "  $f\$" || die "$f no figura en SHA256SUMS: no se instala un paquete sin hash"; done
log "SHA256 verificado (sobre la copia privada)"

# 2b) puertas de seguridad ANTES de escribir nada en el sistema: alcance probado y autenticidad de las fuentes
for mm in "$@"; do gate_scope "$mm"; done
# shellcheck disable=SC2086
gate_auth $(for f in $need; do echo "$PKG/$f"; done)

# put <destino>: escribe el contenido de stdin; si el destino ya existe y difiere, lo CONSERVA y deja la propuesta en <destino>.new
put() {
  local d=$1 tmp; tmp=$(mktemp); cat > "$tmp"; chmod 644 "$tmp"
  if [ -e "$d" ] && ! cmp -s "$tmp" "$d"; then cp "$tmp" "$d.new"; rm -f "$tmp"; log "AVISO: $d existe y difiere; se conserva (propuesta en $d.new)"
  else cat "$tmp" > "$d"; rm -f "$tmp"; command -v restorecon >/dev/null && restorecon "$d" 2>/dev/null; fi   # cat (no mv): un archivo movido desde /tmp conserva user_tmp_t y systemd no puede abrirlo con SELinux
}
# safe_tar <tar.gz> <regex-de-prefijos-permitidos>: rechaza rutas fuera de lo permitido, "..", y enlaces absolutos o con ".." (extraer como root)
safe_tar() {
  local t=$1 allow=$2 bad
  bad=$(tar -tzf "$t" | sed 's#^\./##' | grep -Ev "^($allow)(/|\$)" | head -3)
  [ -z "$bad" ] || die "$(basename "$t") contiene rutas fuera de lo permitido: $bad"
  tar -tzf "$t" | grep -Eq '(^|/)\.\.(/|$)' && die "$(basename "$t") contiene componentes '..'"
  # tipos: solo archivos regulares, directorios y enlaces (nada de dispositivos, FIFO ni sockets)
  bad=$(tar -tvzf "$t" | awk 'substr($1,1,1) !~ /[-dlh]/ {print $NF}' | head -3)
  [ -z "$bad" ] || die "$(basename "$t") contiene tipos de archivo no permitidos: $bad"
  # sin setuid/setgid (se extrae como root)
  bad=$(tar -tvzf "$t" | awk 'substr($1,1,1) != "l" && substr($1,4,1) ~ /[sS]/ || substr($1,1,1) != "l" && substr($1,7,1) ~ /[sS]/ {print $NF}' | head -3)
  [ -z "$bad" ] || die "$(basename "$t") contiene archivos setuid/setgid: $bad"
  # enlaces: se permiten relativos sin ".." y absolutos solo hacia /opt/deps, /opt/phpNN o los certificados del sistema (OpenSSL los enlaza)
  bad=$(tar -tvzf "$t" | awk '
    / -> / || / link to / { l=$0; sub(/.* -> /,"",l); sub(/.* link to /,"",l);
      if (l ~ /(^|\/)\.\.(\/|$)/) print l;
      else if (l ~ /^\// && l !~ /^\/(opt\/deps|opt\/php[0-9][0-9]|etc\/pki|etc\/ssl)(\/|$)/) print l }' | head -3)
  [ -z "$bad" ] || die "$(basename "$t") contiene enlaces peligrosos: $bad"
  # ningun miembro se extrae "a traves" de un enlace simbolico del mismo paquete (podria escribir fuera del arbol)
  bad=$(tar -tvzf "$t" | awk '{ p=$6; sub(/^\.\//,"",p) } substr($1,1,1)=="l" { L[p]=1 } { P[NR]=p } END { for (i in P) for (l in L) if (index(P[i], l "/")==1) print P[i] }' | head -3)
  [ -z "$bad" ] || die "$(basename "$t") contiene miembros que atraviesan un enlace simbolico: $bad"
}
# extract_pkg <tar.gz> <nombre bajo /opt>: extrae en el area privada, revisa el arbol ya extraido y lo mueve a /opt con un rename (todo o nada)
extract_pkg() {
  local t=$1 n=$2 x="$STG/x.$2" bad xr
  safe_tar "$t" "opt/$n"
  mkdir -p "$x" && tar -xzf "$t" -C "$x" --no-same-owner || die "fallo la extraccion de $t (espacio o permisos); no se toco /opt/$n"
  [ -d "$x/opt/$n" ] || die "$(basename "$t") no contiene opt/$n"
  xr=$(readlink -f -- "$x")
  chmod -R go-w "$x" || die "no pude normalizar permisos del paquete"   # nada escribible por grupo u otros, venga como venga el paquete
  [ -z "$(find "$x" -perm /6000 -print -quit)" ] || die "$(basename "$t") contiene archivos setuid/setgid tras extraer"
  bad=$(find "$x" -type l | while read -r l; do
    tg=$(readlink "$l")
    case "$tg" in
      /opt/deps|/opt/deps/*|/opt/php[0-9][0-9]|/opt/php[0-9][0-9]/*|/etc/pki/*|/etc/ssl/*) ;;
      /*) echo "$l -> $tg";;
      *) r=$(readlink -m -- "$(dirname "$l")/$tg"); case "$r" in "$xr/opt/$n"|"$xr/opt/$n"/*) ;; *) echo "$l -> $tg";; esac;;
    esac
  done | head -3)
  [ -z "$bad" ] || die "enlaces que salen del arbol instalado: $bad"
  [ ! -e "/opt/$n" ] || die "/opt/$n ya existe"
  mv -T -- "$x/opt/$n" "/opt/$n" || die "no pude mover $n a /opt"
}



# los directorios de los IncludeOptional deben EXISTIR: con un comodin sobre un directorio inexistente Apache 2.4 falla el configtest
mkdir -p "$SITES_DEF" "$STATE" "$APA_ACTIVE" "$APA_OFF" "$APA_BASE/shadow"
if [ ! -d /opt/deps ]; then
  d=$(ls "$PKG"/*deps*.tar.gz 2>/dev/null | head -1)
  extract_pkg "$d" deps
  log "dependencias instaladas en /opt/deps"
fi

for f in php-fpm.conf php-fpm.service php-fpm.logrotate php-cli-wrapper.sh opcache.ini; do [ -s "$TPL/$f.tpl" ] || die "falta la plantilla $f.tpl en $TPL"; done
for mm in "$@"; do
  t=$(ls "$PKG"/php-$(mm_dotted $mm).*-opt.tar.gz | sort -V | tail -1)
  v=$(basename "$t" | sed -E 's/^php-([0-9.]+)-.*/\1/')
  if [ -x /opt/php$mm/bin/php ]; then
    log "/opt/php$mm ya existe: se conserva (usar uninstall.sh para reinstalar)"
  else
    extract_pkg "$t" "php$mm"
    log "PHP $v extraido en /opt/php$mm"
    [ -f /opt/php$mm/SOURCES-NOT-AUTHENTICATED.txt ] && log "AVISO: el codigo fuente de este PHP no se autentico (ver /opt/php$mm/SOURCES-NOT-AUTHENTICATED.txt, references/02)"
  fi
  mkdir -p /opt/php$mm/etc/php-fpm.d /opt/php$mm/etc/php.d /var/log/php$mm-fpm /var/lib/php$mm/session
  chown $WEB_USER:$WEB_USER /var/lib/php$mm/session; chmod 770 /var/lib/php$mm/session
  # php.ini base solo si no existe; el del servidor se instala despues, ANTES de activar el primer sitio
  if [ ! -f /opt/php$mm/etc/php.ini ]; then
    if [ -f /opt/php$mm/lib/php.ini-production ]; then cp /opt/php$mm/lib/php.ini-production /opt/php$mm/etc/php.ini
    else printf '; php.ini base de php-patch: reemplazar por uno derivado del php.ini actual del servidor\n' > /opt/php$mm/etc/php.ini; fi
  fi
  sed "s/@MM@/$mm/g" "$TPL/php-fpm.conf.tpl" | put /opt/php$mm/etc/php-fpm.conf
  sed "s/@MM@/$mm/g;s/@VER@/$v/g" "$TPL/php-fpm.service.tpl" | put /etc/systemd/system/php$mm-fpm.service
  sed "s/@MM@/$mm/g" "$TPL/php-fpm.logrotate.tpl" | put /etc/logrotate.d/php$mm-fpm
  sed "s/@MM@/$mm/g;s/@VER@/$v/g" "$TPL/php-cli-wrapper.sh.tpl" | put /usr/local/bin/php$mm; chmod 755 /usr/local/bin/php$mm
  # PHP 8.5 trae opcache integrado: no se carga como zend_extension
  if [ "$mm" -ge 85 ]; then ol=''; else ol='zend_extension=opcache'; fi
  sed "s/@MM@/$mm/g;s|@OPCACHE_LOAD@|$ol|" "$TPL/opcache.ini.tpl" | put /opt/php$mm/etc/php.d/10-opcache.ini
  systemctl daemon-reload
  # el servicio NO se habilita ni se inicia: lo hace activate-site.sh con el primer sitio
  PHP_INI_SCAN_DIR=/opt/php$mm/etc/php.d /opt/php$mm/bin/php -c /opt/php$mm/etc/php.ini -v | head -1 | tee -a "$LOG"
  if ldd /opt/php$mm/sbin/php-fpm | grep -q 'not found'; then
    ldd /opt/php$mm/sbin/php-fpm | grep 'not found'
    die "librerias del sistema faltantes para php$mm: instalarlas con yum (references/04-errores-conocidos.md) y repetir"
  fi
  if [ "$(getenforce 2>/dev/null)" = Enforcing ] && [ "${PREPARE_SELINUX:-0}" != 1 ]; then
    log "AVISO: SELinux Enforcing: NO se etiquetaron contextos ni puertos (cambio de SELinux que requiere autorizacion). Con autorizacion, reejecutar con PREPARE_SELINUX=1 o aplicar references/05-selinux.md; activate-site.sh se niega hasta entonces"
  elif [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
    if command -v semanage >/dev/null; then
      semanage fcontext -a -t httpd_exec_t "/opt/php$mm/sbin/php-fpm" 2>/dev/null || true
      semanage fcontext -a -t bin_t "/opt/php$mm/bin(/.*)?" 2>/dev/null || true
      semanage fcontext -a -t lib_t "/opt/deps(/.*)?" 2>/dev/null || true
      semanage fcontext -a -t httpd_log_t "/var/log/php$mm-fpm(/.*)?" 2>/dev/null || true
      semanage fcontext -a -t httpd_sys_rw_content_t "/var/lib/php$mm(/.*)?" 2>/dev/null || true
      restorecon -R /opt/php$mm /opt/deps /var/log/php$mm-fpm /var/lib/php$mm
      semanage port -l | grep -q "^http_port_t.*$PORT_MIN" || semanage port -a -t http_port_t -p tcp $PORT_MIN-$PORT_MAX 2>/dev/null || true
    else
      log "AVISO: SELinux Enforcing y sin semanage: no se etiquetaron contextos ni puertos. Ver references/05-selinux.md ANTES de activar un sitio."
    fi
  fi
done

[ -f /opt/deps/SOURCES-NOT-AUTHENTICATED.txt ] && log "AVISO: /opt/deps incluye bibliotecas cuya fuente no se autentico (ver /opt/deps/SOURCES-NOT-AUTHENTICATED.txt, references/02)"
# Include de Apache: inerte mientras active/ este vacio
if [ ! -f "$APA_INCLUDE" ]; then
  sed "s|@APA_INCLUDE@|$APA_INCLUDE|;s|@APA_ACTIVE@|$APA_ACTIVE|;s|@APA_BASE@|$APA_BASE|" "$TPL/include.conf.tpl" > "$APA_INCLUDE"
  if ! $HTTPD_BIN -t >/dev/null 2>&1; then
    rm -f "$APA_INCLUDE"; die "configtest de Apache fallo con el include; revertido"
  fi
  log "include de Apache instalado (sin efecto hasta activar un sitio)"
fi
log "instalacion lista. PHP vigente intacto: $(php -v 2>/dev/null | head -1)"

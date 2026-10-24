#!/bin/bash
# shadow-site.sh - prueba un sitio con el PHP nuevo SIN tocar el trafico real ("sitio sombra").
# Crea el pool del sitio y un VirtualHost que escucha SOLO en 127.0.0.1:<SHADOW_PORT> con el mismo docroot.
# El vhost real sigue en el PHP anterior; ningun usuario pasa por la sombra.
# Uso:  sudo ./shadow-site.sh up   <slug> <MM> <ServerName>     levanta la sombra
#       sudo ./shadow-site.sh down <slug>                       la retira (pool, vhost y estado)
#       Probar: curl -s --resolve <ServerName>:<SHADOW_PORT>:127.0.0.1 http://<ServerName>:<SHADOW_PORT>/
#
# LIMITES (leer): comparte base de datos y archivos con el sitio real; las sesiones pueden compartirse o cambiar de ubicacion segun la aplicacion. Usar SOLO peticiones de lectura
# (GET) o credenciales de prueba; no ejecutar operaciones que escriban, envien correo o disparen integraciones.
# La sombra reproduce docroot, handler y DirectoryIndex; NO reproduce Alias, Rewrite de vhost, SSL ni otras
# directivas del vhost real. Sirve para detectar 500, funciones eliminadas y extensiones faltantes, no para
# certificar el sitio: eso lo hace el piloto real.
# SELinux Enforcing: el puerto de la sombra debe ser http_port_t (por defecto no lo es el 18080; ver references/05).
source "$(dirname "$0")/lib.sh"
need_root
SHADOW_PORT=${SHADOW_PORT:-18080}
SH_DIR=$APA_BASE/shadow
act=${1:?up|down}; slug=${2:?slug}; valid_slug "$slug"
# SHADOW_PORT y el ServerName se escriben en configuracion de Apache: se validan estrictamente
[[ "$SHADOW_PORT" =~ ^[0-9]{4,5}$ ]] && [ "$SHADOW_PORT" -ge 1024 ] && [ "$SHADOW_PORT" -le 65535 ] || die "SHADOW_PORT debe ser un numero entre 1024 y 65535"
def=$SITES_DEF/$slug
case $act in
  up)
    mm=${3:?MM}; name=${4:?ServerName}; valid_mm "$mm"
    [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] || die "ServerName invalido '$name' (solo letras, digitos, punto y guion)"
    [ -f "$def/pool.conf" ] && [ -f "$def/site.conf" ] || die "faltan definiciones en $def (generate-site.sh)"
    [ -x /opt/php$mm/sbin/php-fpm ] || die "PHP $mm no instalado"
    gate_scope "$mm"
    if [ -f /opt/php$mm/SOURCES-NOT-AUTHENTICATED.txt ] || [ -f /opt/deps/SOURCES-NOT-AUTHENTICATED.txt ]; then
      [ "${ACCEPT_UNAUTHENTICATED:-}" = yes ] || die "PHP $mm o /opt/deps tienen fuentes sin autenticar (SOURCES-NOT-AUTHENTICATED.txt): la sombra ejecuta ese PHP contra el codigo del sitio y no se levanta sin la excepcion aprobada (references/11)"
    fi
    [ -f "$STATE/$slug" ] && die "$slug ya esta activo en FPM; la sombra no aplica"
    [ -f "$STATE/$slug.shadow" ] && die "ya hay una sombra de $slug; ejecutar 'down' primero"
    ensure_backup shadow
    if [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
      # Un Listen en un puerto que httpd_t no puede abrir hace que Apache se caiga al recargar (probado en Rocky 9): se rechaza antes.
      command -v semanage >/dev/null || die "SELinux Enforcing y sin semanage: no puedo comprobar si el puerto $SHADOW_PORT es http_port_t. Instalar policycoreutils-python-utils o fijar SHADOW_PORT a un puerto ya etiquetado"
      port_labeled "$SHADOW_PORT" || die "SELinux Enforcing: el puerto $SHADOW_PORT no es http_port_t y Apache se caeria al recargar. Usa un puerto ya etiquetado (ver: semanage port -l | grep http_port_t), por ejemplo SHADOW_PORT=8008, o etiquetalo con autorizacion (references/05)"
      selinux_proxy_ok || die "$SELINUX_PROXY_MSG"
    fi
    doc=$(sed -n 's/^<Directory "\(.*\)">/\1/p' "$def/site.conf" | head -1); [ -d "$doc" ] || die "docroot no encontrado en site.conf"
    port=$(sed -n 's/^listen *= *127.0.0.1:\([0-9]*\).*/\1/p' "$def/pool.conf" | head -1)
    # el include debe cargar shadow/*.conf (instalaciones anteriores no lo traen); el directorio debe existir antes
    mkdir -p "$SH_DIR"
    if ! grep -q "$SH_DIR" "$APA_INCLUDE"; then
      cp "$APA_INCLUDE" "$APA_INCLUDE.bak.$$"; echo "IncludeOptional $SH_DIR/*.conf" >> "$APA_INCLUDE"
      $HTTPD_BIN -t >/dev/null 2>&1 || { mv "$APA_INCLUDE.bak.$$" "$APA_INCLUDE"; die "configtest fallo al agregar el include de sombras"; }
      rm -f "$APA_INCLUDE.bak.$$"
    fi
    mkdir -p "$SH_DIR" "$(fpm_dir "$mm")" /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache
    chown $WEB_USER:$WEB_USER /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache; chmod 770 /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache
    command -v restorecon >/dev/null && restorecon -R /var/lib/php$mm 2>/dev/null
    render "$def/pool.conf" "$mm" > "$(fpm_dir "$mm")/$slug.conf.tmp" && mv -f "$(fpm_dir "$mm")/$slug.conf.tmp" "$(fpm_dir "$mm")/$slug.conf" || { rm -f "$(fpm_dir "$mm")/$slug.conf.tmp"; die "no pude escribir el pool de la sombra"; }
    cleanup() { rm -f "$(fpm_dir "$mm")/$slug.conf" "$SH_DIR/$slug.conf"; ls "$SH_DIR"/*.conf 2>/dev/null | grep -qv '00-listen.conf' || rm -f "$SH_DIR/00-listen.conf"; fpm_sync "$mm" || true; apache_check_reload || log "ERROR: Apache no recargo al limpiar la sombra; revisar a mano"; }
    trap 'log "interrumpido: limpiando la sombra de $slug"; cleanup; exit 1' INT TERM HUP
    fpm_test "$mm" >/dev/null 2>&1 || { fpm_test "$mm" 2>&1 | tail -3 >&2; cleanup; die "php-fpm -t fallo"; }
    fpm_sync "$mm" || { cleanup; die "no pudo iniciar php$mm-fpm"; }
    for i in 1 2 3 4 5; do ss -tln | grep -q "127.0.0.1:$port " && break; sleep 1; done
    ss -tln | grep -q "127.0.0.1:$port " || { cleanup; die "el pool no escucha en $port"; }
    [ -f "$SH_DIR/00-listen.conf" ] || echo "Listen 127.0.0.1:$SHADOW_PORT" > "$SH_DIR/00-listen.conf"
    cat > "$SH_DIR/$slug.conf" <<CONF
# sombra de $slug (php-patch): solo loopback, mismo docroot. Retirar con shadow-site.sh down $slug
<VirtualHost 127.0.0.1:$SHADOW_PORT>
    ServerName $name
    DocumentRoot "$doc"
    <Directory "$doc">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
        SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
        <FilesMatch "\.(php|phar)\$">
            SetHandler "proxy:fcgi://127.0.0.1:$port"
        </FilesMatch>
    </Directory>
</VirtualHost>
CONF
    apache_check_reload || { cleanup; die "Apache no recargo con la sombra; revertido"; }
    trap '' INT TERM HUP
    printf 'MM=%s\nPORT=%s\nSHADOW_PORT=%s\nFECHA=%s\n' "$mm" "$port" "$SHADOW_PORT" "$(date '+%F %T')" > "$STATE/$slug.shadow" || { cleanup; die "no pude guardar el estado de la sombra"; }
    trap - INT TERM HUP
    log "SOMBRA $slug -> php$mm lista. Probar: curl -s --resolve $name:$SHADOW_PORT:127.0.0.1 http://$name:$SHADOW_PORT/   (solo lecturas revisadas: un GET tambien puede escribir sesiones o cache, y el vhost de sombra no replica restricciones de acceso del original; es solo loopback)";;
  down)
    f=$STATE/$slug.shadow; [ -f "$f" ] || { log "$slug no tiene sombra"; exit 0; }
    ensure_backup shadow-down
    mm=$(sed -n 's/^MM=//p' "$f")
    # primero el vhost (y se confirma la recarga de Apache); el pool se retira despues, para no dejar un vhost apuntando a un pool inexistente
    rm -f "$SH_DIR/$slug.conf"
    ls "$SH_DIR"/*.conf 2>/dev/null | grep -qv '00-listen.conf' || rm -f "$SH_DIR/00-listen.conf"
    apache_check_reload || die "Apache no recargo; revisar $SH_DIR (el pool de la sombra sigue en su lugar)"
    rm -f "$(fpm_dir "$mm")/$slug.conf"
    fpm_sync "$mm" || log "aviso: fpm_sync php$mm devolvio error"
    rm -f "$f"; log "sombra de $slug retirada";;
  *) die "accion desconocida $act";;
esac

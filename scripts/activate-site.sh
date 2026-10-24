#!/bin/bash
# activate-site.sh <slug> <MM> - pone el sitio en PHP-FPM de la version MM (activacion o cambio de version).
# Requiere /etc/php-patch/sites/<slug>/{pool.conf,site.conf} (ver generate-site.sh).
# Comprobacion opcional contra el propio Apache (sin DNS):  CHECK_HOST=www.example.org [CHECK_PATH=/] [CHECK_SCHEME=https]
#   Si el codigo HTTP pasa a 5xx y antes no lo era, revierte solo en segundos.
# Si algo falla, deja el sitio como estaba (en el PHP anterior si era la primera activacion).
source "$(dirname "$0")/lib.sh"
need_root
slug=${1:?slug}; mm=${2:?MM}; valid_slug "$slug"; valid_mm "$mm"
def=$SITES_DEF/$slug
[ -f "$def/pool.conf" ] && [ -f "$def/site.conf" ] || die "faltan definiciones en $def"
[ -x /opt/php$mm/sbin/php-fpm ] || die "PHP $mm no instalado"
# un php.ini vacio (marcador de install-package.sh cuando el paquete no trae php.ini-production) deja a PHP con valores de desarrollo
head -1 /opt/php$mm/etc/php.ini 2>/dev/null | grep -q 'php.ini base de php-patch' && [ "${ALLOW_DEFAULT_INI:-}" != yes ] && die "el php.ini de /opt/php$mm es el marcador vacio: instala un php.ini revisado (derivado del php.ini actual del servidor) antes de activar. Solo para pruebas: ALLOW_DEFAULT_INI=yes"
gate_scope "$mm"
[ -f /opt/php$mm/SOURCES-NOT-AUTHENTICATED.txt ] || [ -f /opt/deps/SOURCES-NOT-AUTHENTICATED.txt ] && { [ "${ACCEPT_UNAUTHENTICATED:-}" = yes ] || die "PHP $mm o /opt/deps tienen fuentes sin autenticar (SOURCES-NOT-AUTHENTICATED.txt): no se activa en produccion sin la excepcion aprobada (references/11)"; }
if [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
  command -v semanage >/dev/null || die "SELinux Enforcing sin semanage: preparar SELinux primero (references/05-selinux.md)"
  { port_labeled $PORT_MIN && port_labeled $PORT_MAX; } || die "SELinux Enforcing: puertos $PORT_MIN-$PORT_MAX sin etiquetar como http_port_t (references/05-selinux.md)"
  selinux_proxy_ok || die "$SELINUX_PROXY_MSG"
fi
[ -f "$STATE/$slug.shadow" ] && die "$slug tiene un sitio sombra activo; retirarlo antes: shadow-site.sh down $slug"
old=$(site_mm "$slug")
[ "$old" = "$mm" ] && { log "$slug ya esta en php$mm"; exit 0; }
before=""
if [ -n "${CHECK_HOST:-}" ]; then
  before=$(probe "$CHECK_HOST" "${CHECK_PATH:-/}" "${CHECK_SCHEME:-https}"); log "linea base $CHECK_HOST: HTTP $before"
fi

revert() {
  log "REVIRTIENDO $slug"
  rm -f "$(fpm_dir "$mm")/$slug.conf"; fpm_sync "$mm" || true
  if [ -n "$old" ]; then
    render "$def/pool.conf" "$old" > "$(fpm_dir "$old")/$slug.conf"; fpm_sync "$old" || true
  else
    mv -f "$APA_ACTIVE/$slug.conf" "$APA_OFF/$slug.conf" 2>/dev/null || true
  fi
  apache_check_reload || log "ERROR: Apache no recargo durante la reversion; revisar a mano: httpd -t y journalctl -u httpd"
  exit 1
}

ensure_backup activate
# una interrupcion (Ctrl+C, cierre de la sesion SSH, kill) a mitad del cambio deja el sitio como estaba
trap 'log "interrumpido: revirtiendo $slug"; revert' INT TERM HUP
# 1) si ya estaba en otra version, liberar su pool (mismo puerto)
if [ -n "$old" ]; then rm -f "$(fpm_dir "$old")/$slug.conf"; fpm_sync "$old" || true; fi
# 2) pool en la version nueva (sesiones, temporales y cache WSDL propios del sitio)
{ mkdir -p "$(fpm_dir "$mm")" /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache \
  && chown $WEB_USER:$WEB_USER /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache \
  && chmod 770 /var/lib/php$mm/session/$slug /var/lib/php$mm/tmp/$slug /var/lib/php$mm/wsdlcache; } || { log "no pude preparar los directorios de php$mm"; revert; }
command -v restorecon >/dev/null && restorecon -R /var/lib/php$mm 2>/dev/null
render "$def/pool.conf" "$mm" > "$(fpm_dir "$mm")/$slug.conf.tmp" && mv -f "$(fpm_dir "$mm")/$slug.conf.tmp" "$(fpm_dir "$mm")/$slug.conf" || { log "no pude escribir el pool de $slug"; rm -f "$(fpm_dir "$mm")/$slug.conf.tmp"; revert; }
fpm_test "$mm" >/dev/null 2>&1 || { log "php-fpm -t fallo"; fpm_test "$mm" 2>&1 | tail -3 >&2; revert; }
fpm_sync "$mm" || { log "no pudo iniciar/recargar php$mm-fpm"; revert; }
port=$(sed -n 's/^listen *= *127.0.0.1:\([0-9]*\).*/\1/p' "$(fpm_dir "$mm")/$slug.conf" | head -1)
for i in 1 2 3 4 5; do ss -tln | grep -q "127.0.0.1:$port " && break; sleep 1; done
ss -tln | grep -q "127.0.0.1:$port " || { log "el pool no escucha en $port"; revert; }
# 3) Apache: solo la primera vez hay que activar el .conf (en un cambio de version el puerto es el mismo)
if [ -z "$old" ]; then
  cp "$def/site.conf" "$APA_ACTIVE/$slug.conf" || { log "no pude copiar site.conf a active/"; revert; die "activacion abortada"; }
  rm -f "$APA_OFF/$slug.conf"
  apache_check_reload || { log "configtest/graceful de Apache fallo"; revert; }
fi
# 4) comprobacion HTTP
if [ -n "$before" ]; then
  sleep 2; after=$(probe "$CHECK_HOST" "${CHECK_PATH:-/}" "${CHECK_SCHEME:-https}")
  log "despues $CHECK_HOST: HTTP $after (antes $before)"
  case $after in 5*|000) case $before in 5*|000) ;; *) log "el sitio pasa a error ($after)"; revert;; esac;; esac
fi
trap '' INT TERM HUP   # desde aqui el estado y el cambio deben quedar coherentes: no se interrumpe
{ printf 'MM=%s\nPORT=%s\nFECHA=%s\nANTERIOR=%s\n' "$mm" "$port" "$(date '+%F %T')" "${old:-php-anterior}" > "$STATE/$slug.tmp" && mv -f "$STATE/$slug.tmp" "$STATE/$slug"; } \
  || { log "no pude guardar el estado de $slug"; revert; }
trap - INT TERM HUP
systemctl enable "php$mm-fpm" >/dev/null 2>&1 || true
log "OK $slug -> php$mm (puerto $port). Rollback: rollback-site.sh $slug"

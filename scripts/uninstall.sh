#!/bin/bash
# uninstall.sh MM [MM...] | --all - retira PHP parchado. Exige que no queden sitios activos en esa version.
# No borra: renombra /opt/phpMM a /opt/phpMM.removed.<fecha>. /opt/deps y /etc/php-patch quedan (retiro manual).
source "$(dirname "$0")/lib.sh"
need_root
[ $# -ge 1 ] || die "indicar versiones o --all"
if [ "$1" = --all ]; then
  confirm_bulk "retiro de TODAS las versiones de PHP parchado"
  set --
  for d in /opt/php[0-9][0-9]; do [ -d "$d" ] && set -- "$@" "${d#/opt/php}"; done
fi
ensure_backup uninstall
for mm in "$@"; do
  valid_mm "$mm"
  [ -d /opt/php$mm ] || continue
  if ls "$(fpm_dir "$mm")"/*.conf >/dev/null 2>&1; then die "php$mm tiene pools activos; ejecutar rollback-site.sh primero"; fi
  systemctl stop php$mm-fpm 2>/dev/null
  mv /opt/php$mm "/opt/php$mm.removed.$(date +%Y%m%d%H%M%S)" || { systemctl start php$mm-fpm 2>/dev/null; die "no pude renombrar /opt/php$mm; no se retiro nada mas"; }
  systemctl disable php$mm-fpm 2>/dev/null
  rm -f /etc/systemd/system/php$mm-fpm.service /etc/logrotate.d/php$mm-fpm /usr/local/bin/php$mm
  log "php$mm retirado (directorio renombrado, no borrado)"
done
systemctl daemon-reload
if ! ls -d /opt/php[0-9][0-9] >/dev/null 2>&1 && ! ls $APA_ACTIVE/*.conf >/dev/null 2>&1; then
  if mv "$APA_INCLUDE" "$APA_INCLUDE.removed" 2>/dev/null; then
    apache_check_reload || { mv "$APA_INCLUDE.removed" "$APA_INCLUDE"; apache_check_reload >/dev/null 2>&1; die "Apache no recargo sin el include; se restauro $APA_INCLUDE. Revisar httpd -t"; }
  fi
fi

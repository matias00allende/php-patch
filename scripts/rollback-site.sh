#!/bin/bash
# rollback-site.sh <slug>|--all - devuelve el sitio al SAPI ORIGINAL (mod_php u otro) sin tocar los demas.
# No es "deshacer un cambio de version": para volver a la version FPM anterior usar change-version.sh <slug> <MM anterior>.
# Se niega si mod_php ya no esta cargado (el sitio quedaria sin handler y Apache serviria el codigo PHP como texto): FORCE_ROLLBACK=1 lo omite.
# Efecto colateral: el sitio vuelve al directorio de sesiones anterior, asi que las sesiones del pool FPM dejan de ser accesibles (los usuarios pueden tener que ingresar de nuevo).
source "$(dirname "$0")/lib.sh"
need_root
if [ "${1:?slug o --all}" = --all ]; then
  confirm_bulk "rollback de TODOS los sitios activos en FPM"
  rc=0
  for f in "$STATE"/*; do
    [ -f "$f" ] || continue
    case "$f" in *.rollback.*|*.shadow) continue;; esac
    "$0" "$(basename "$f")" || { log "ERROR: fallo el rollback de $(basename "$f")"; rc=1; }
  done
  ls "$STATE"/*.shadow >/dev/null 2>&1 && log "AVISO: hay sitios sombra; retirarlos con shadow-site.sh down <slug>"
  exit $rc
fi
slug=$1; valid_slug "$slug"
if [ "${FORCE_ROLLBACK:-0}" != 1 ] && ! { $HTTPD_BIN -M 2>/dev/null | grep -Eq "php[0-9]*_module"; }; then
  die "mod_php no esta cargado: revertir dejaria $slug sin handler PHP y Apache serviria el codigo fuente como texto. Restaure primero el handler anterior o use FORCE_ROLLBACK=1 sabiendo el riesgo"
fi
mm=$(site_mm "$slug"); [ -n "$mm" ] || { log "$slug no esta activo en FPM"; exit 0; }
ensure_backup rollback
if [ -f "$APA_ACTIVE/$slug.conf" ]; then mv -f "$APA_ACTIVE/$slug.conf" "$APA_OFF/$slug.conf"; fi
apache_check_reload || { mv -f "$APA_OFF/$slug.conf" "$APA_ACTIVE/$slug.conf" 2>/dev/null; apache_check_reload >/dev/null 2>&1; die "Apache no recargo con el rollback; se restauro active/$slug.conf (el sitio sigue en FPM). Revisar httpd -t y journalctl -u httpd"; }
rm -f "$(fpm_dir "$mm")/$slug.conf"; fpm_sync "$mm" || log "aviso: fpm_sync php$mm devolvio error"
mv -f "$STATE/$slug" "$STATE/$slug.rollback.$(date +%Y%m%d%H%M%S)"
log "ROLLBACK $slug: vuelve al PHP anterior (las sesiones del pool FPM ya no son accesibles)"

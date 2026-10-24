#!/bin/bash
# status.sh - SOLO LECTURA: que sitio corre en que version, servicios y pools. Guardar la salida como evidencia.
source "$(dirname "$0")/lib.sh"
echo "== $(hostname) $(date '+%F %T') | PHP vigente: $(php -v 2>/dev/null | head -1)"
echo "== sitios en FPM"
for f in "$STATE"/*; do
  [ -f "$f" ] || continue
  case "$f" in *.rollback.*) continue;; esac
  printf '%-32s %s\n' "$(basename "$f")" "$(tr '\n' ' ' < "$f")"
done
echo "== servicios"
for d in /opt/php[0-9][0-9]; do
  [ -x $d/sbin/php-fpm ] || continue; mm=${d#/opt/php}
  printf 'php%s-fpm: %s, pools=%s\n' "$mm" "$(systemctl is-active php$mm-fpm)" "$(ls "$(fpm_dir $mm)"/*.conf 2>/dev/null | wc -l)"
done
echo "== definiciones sin activar: $(for d in $SITES_DEF/*/; do s=$(basename $d); [ -f $STATE/$s ] || printf '%s ' $s; done)"
echo "== apache active: $(ls $APA_ACTIVE 2>/dev/null | wc -l)  off: $(ls $APA_OFF 2>/dev/null | wc -l)"

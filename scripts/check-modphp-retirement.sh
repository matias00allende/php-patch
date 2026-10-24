#!/bin/bash
# check-modphp-retirement.sh - SOLO LECTURA. Dice si es seguro retirar mod_php (paso final, con autorizacion).
# Retirarlo antes de tiempo apaga todo sitio que aun dependa de el. Revisa tres cosas:
#   1) todo vhost con DocumentRoot esta cubierto por un sitio activo en FPM
#   2) ninguna configuracion ni .htaccess usa php_value/php_flag (con el modulo retirado dan 500)
#   3) crontabs que usan el PHP del sistema (no cambian al retirar mod_php, pero siguen sin parche)
source "$(dirname "$0")/lib.sh"
rc=0
echo "== 1) docroots sin handler FPM"
for dr in $(grep -rhiE '^\s*DocumentRoot' $HTTPD_ETC 2>/dev/null | awk '{print $2}' | tr -d '"' | sed 's#/$##' | sort -u); do
  grep -qs "<Directory \"$dr\">" $APA_ACTIVE/*.conf || { echo "  SIN FPM: $dr"; rc=1; }
done
echo "== 2) directivas php_* en configuracion y .htaccess"
n=$(grep -rniE '^\s*php_(value|flag|admin_value|admin_flag)' $HTTPD_ETC --exclude-dir=$LP_NAME 2>/dev/null | grep -v 'conf.d/php.conf' | wc -l)
echo "  en configuracion: $n"; [ "$n" = 0 ] || rc=1
for dr in $(grep -rhiE '^\s*DocumentRoot' $HTTPD_ETC 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u); do
  if [ -d "$dr" ]; then
    find "$dr" -maxdepth 4 -name .htaccess -print0 2>/dev/null | xargs -0 grep -nHiE '^\s*php_(value|flag|admin_value|admin_flag)' 2>/dev/null && rc=1
  fi
done
echo "== 3) crons con PHP del sistema (informativo)"
grep -rEno '(^|[[:space:]])([^[:space:]]*/)?php[0-9.]*([[:space:]]|$)' /etc/cron* /var/spool/cron 2>/dev/null | head   # solo archivo:linea y ejecutable, sin argumentos
if [ $rc = 0 ]; then echo "RESULTADO: comprobaciones superadas (cobertura parcial: .htaccess hasta 4 niveles y vhosts descubiertos; revisa a mano Alias y configuraciones fuera de esos arboles) - se puede retirar mod_php con autorizacion"; else echo "RESULTADO: NO retirar todavia"; fi
echo "NOTA: el handler nuevo cubre .php y .phar; si el sitio usa otras extensiones (.phtml, .php5...) revisa AddHandler/AddType con inventory.sh antes de retirar mod_php"
exit $rc

#!/bin/bash
# lab-reset.sh - deja el laboratorio sin estado de php-patch (no borra: aparta a /tmp/lab-old.<ts>).
# Solo para el laboratorio desechable.
[ "${LAB_CONFIRM:-}" = yes ] || { echo "Este script modifica el sistema (systemctl falso, vhost de prueba, pkill). Solo en un laboratorio desechable: ejecutar con LAB_CONFIRM=yes"; exit 2; }
pkill httpd; pkill php-fpm; sleep 1
T=$(mktemp -d /tmp/lab-old.XXXXXX) || exit 1
for p in /etc/php-patch /etc/httpd/php-patch /etc/httpd/conf.d/00-php-patch.conf /etc/httpd/conf.d/zz-labvhost.conf /var/www/html/labtest /run/php[0-9][0-9]-fpm; do
  [ -e "$p" ] && mv "$p" "$T/$(echo $p | tr / _)"
done
for f in /opt/php[0-9][0-9]/etc/php-fpm.d/*.conf; do [ -e "$f" ] && mv "$f" "$T/$(echo $f | tr / _)"; done
grep -q "sustituto minimo de systemctl" /usr/local/bin/systemctl 2>/dev/null && mv /usr/local/bin/systemctl "$T/systemctl-sustituto"
echo "apartado en $T"

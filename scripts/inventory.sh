#!/bin/bash
# inventory.sh - SOLO LECTURA. Levantamiento de un servidor web con PHP antes de decidir nada.
# No escribe en el servidor. Ejecutar con sudo para ver crontabs y logs; sin sudo igual entrega lo demas.
# Uso: [sudo] ./inventory.sh > inventario.txt
# Todo lo que se concluya debe salir de esta salida o de otra lectura: no se infiere.
export LC_ALL=C
sec() { echo; echo "=== $*"; }
sec "host"; hostname; date '+%F %T'; uname -r
sec "sistema operativo"; cat /etc/redhat-release 2>/dev/null; grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release 2>/dev/null
sec "recursos"; free -m | head -2; df -h / /opt /var 2>/dev/null
sec "PHP del sistema"; command -v php && php -v 2>/dev/null | head -1; rpm -qa 2>/dev/null | grep -iE '^php' | sort | head -40; dpkg -l 2>/dev/null | grep -E '^ii +php' | awk '{print $2,$3}' | head -40
sec "PHP ya instalado aparte"; ls -d /opt/php* /opt/remi* /opt/rh/*php* 2>/dev/null
sec "Apache"; (httpd -v || apache2 -v) 2>/dev/null | head -2
# SUSE: start_apache2 arma los modulos y los -D desde /etc/sysconfig/apache2; "httpd -M/-S" a secas no ven php ni proxy_fcgi, "apachectl" si
if [ -x /usr/sbin/start_apache2 ] && command -v apachectl >/dev/null 2>&1; then
  apa() { apachectl "$@"; }
elif command -v httpd >/dev/null 2>&1; then apa() { httpd "$@"; }
else apa() { apache2ctl "$@"; }; fi
apa -M 2>/dev/null | grep -Ei 'php|proxy|fcgi|mpm|rewrite|ssl'
sec "virtual hosts (httpd -S)"; apa -S 2>&1 | head -150
sec "DocumentRoot declarados"; grep -rhiE '^\s*DocumentRoot' /etc/httpd /etc/apache2 2>/dev/null | sed 's/^ *//' | sort | uniq -c | sort -rn
sec "directivas php_* en configuracion y .htaccess (daran 500 si se retira mod_php)"
# los valores se ocultan salvo una lista de parametros no sensibles (un valor puede traer contrasenas o URLs con credenciales)
mask() { awk '{ if (match($0, /php_(value|flag|admin_value|admin_flag)[[:space:]]+[^[:space:]]+([[:space:]]+[^[:space:]]+)?/)) {
    pre=substr($0,1,RSTART-1); n=split(substr($0,RSTART,RLENGTH), a, /[[:space:]]+/); v=(n>=3)?a[3]:"";
    ok=(a[2] ~ /^(memory_limit|upload_max_filesize|post_max_size|max_execution_time|max_input_time|max_input_vars|display_errors|error_reporting|date\.timezone|short_open_tag|log_errors|session\.gc_maxlifetime)$/);
    print pre a[1] " " a[2] " " (ok ? v : "***") } else print $0 }'; }
grep -rniE '^\s*php_(value|flag|admin_value|admin_flag)' /etc/httpd /etc/apache2 2>/dev/null | head -40 | mask
for d in $(grep -rhiE '^\s*DocumentRoot' /etc/httpd /etc/apache2 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u); do
  [ -d "$d" ] && find "$d" -maxdepth 4 -name .htaccess -print0 2>/dev/null | xargs -0 grep -niE '^\s*php_(value|flag|admin_value|admin_flag)' 2>/dev/null | head -20 | mask
done
sec "extensiones y handlers de PHP declarados en Apache (el handler nuevo cubre .php y .phar: revisa que no queden otras, como .phtml o .php5)"
grep -rniE '^\s*(AddHandler|AddType|SetHandler|<FilesMatch).*php' /etc/httpd /etc/apache2 2>/dev/null | head -20
sec "SELinux"; getenforce 2>/dev/null; command -v semanage || echo "semanage: no instalado"
sec "puertos en escucha"; ss -tlnp 2>/dev/null | head -60
sec "servicios relacionados"; systemctl list-units --type=service --no-legend 2>/dev/null | grep -Ei 'httpd|apache|php|fpm|nginx|mysql|maria|postgres|crond'
sec "uso de PHP en cron (requiere root para crontabs de otros)"
# solo archivo:linea y el ejecutable (sin argumentos: pueden traer contrasenas o tokens)
grep -rEno '(^|[[:space:]])([^[:space:]]*/)?php[0-9.]*([[:space:]]|$)' /etc/cron* 2>/dev/null | head -20; ls /var/spool/cron 2>/dev/null && grep -Eno '(^|[[:space:]])([^[:space:]]*/)?php[0-9.]*([[:space:]]|$)' /var/spool/cron/* 2>/dev/null | head -20
sec "frameworks y CMS detectados (por archivos tipicos)"
for d in $(grep -rhiE '^\s*DocumentRoot' /etc/httpd /etc/apache2 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u); do
  [ -d "$d" ] || continue
  [ -f "$d/wp-includes/version.php" ] && echo "WordPress $(sed -n "s/.*wp_version = '\([^']*\)'.*/\1/p" "$d/wp-includes/version.php") en $d"
  [ -f "$d/system/core/CodeIgniter.php" ] && echo "CodeIgniter $(sed -n "s/.*define('CI_VERSION', '\([^']*\)').*/\1/p" "$d/system/core/CodeIgniter.php") en $d"
  [ -f "$d/artisan" ] && echo "Laravel en $d"
  [ -f "$d/sites/default/settings.php" ] && echo "Drupal en $d"
  [ -f "$d/configuration.php" ] && echo "Joomla en $d"
done
echo; echo "FIN del inventario"

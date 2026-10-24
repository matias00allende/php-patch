#!/bin/bash
# lab-test.sh - prueba de extremo a extremo de los scripts en un laboratorio CentOS 7 DESECHABLE
# (VM, contenedor con systemd o WSL) con Apache 2.4 + mod_php. NUNCA en produccion: instala, activa y revierte.
# Uso: sudo LAB_CONFIRM=yes ./lab-test.sh <dir-paquetes> <MM> [MM2 ...]     (cada MM es una version ya empaquetada)
# En WSL sin systemd se crea un sustituto de systemctl en /usr/local/bin (se queda instalado: es un laboratorio desechable).
[ "${LAB_CONFIRM:-}" = yes ] || { echo "Este script modifica el sistema (systemctl falso, vhost de prueba, pkill). Solo en un laboratorio desechable: ejecutar con LAB_CONFIRM=yes"; exit 2; }
set -u
PKG=${1:?dir paquetes}; shift
[ $# -ge 1 ] || { echo "indicar al menos una version"; exit 2; }
VERS=("$@")
# Por defecto la suite corre SIN las excepciones: con paquetes autenticados y una combinacion dentro de assets/alcance-verificado.conf
# las puertas de lib.sh no deben estorbar. Para probar un paquete propio con fuentes sin autenticar o una version fuera del alcance:
#   LAB_EXCEPTIONS=yes ./lab-test.sh ...   (la persona que lo ejecuta acepta esas excepciones en un laboratorio desechable)
unset ACCEPT_UNAUTHENTICATED ACK_UNTESTED
[ "${LAB_EXCEPTIONS:-}" = yes ] && export ACCEPT_UNAUTHENTICATED=yes ACK_UNTESTED=yes
S=$(cd "$(dirname "$0")" && pwd)
pass=0; fail=0
TD=$(mktemp -d); trap 'rm -r "$TD" 2>/dev/null' EXIT
t() { if eval "$2" >$TD/t.out 2>&1; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; sed 's/^/      /' $TD/t.out | head -8; fail=$((fail+1)); fi; }

if [ ! -d /run/systemd/system ]; then
[ -e /usr/local/bin/systemctl ] && ! grep -q "sustituto minimo de systemctl" /usr/local/bin/systemctl && { echo "ya existe /usr/local/bin/systemctl y no es el sustituto de esta suite: no se sobrescribe"; exit 1; }
cat > /usr/local/bin/systemctl <<'SH'
#!/bin/bash
# sustituto minimo de systemctl para laboratorios sin systemd
cmd=$1; u=${2:-}; [ "$u" = "--quiet" ] && u=${3:-}
mm=${u#php}; mm=${mm%-fpm}; pidf=/run/php$mm-fpm/php-fpm.pid
case $cmd in
  daemon-reload|enable|disable) exit 0;;
  is-active) if [ -f $pidf ] && kill -0 $(cat $pidf) 2>/dev/null; then echo active; exit 0; fi; echo inactive; exit 3;;
  start) mkdir -p /run/php$mm-fpm
         PHP_INI_SCAN_DIR=/opt/php$mm/etc/php.d nohup /opt/php$mm/sbin/php-fpm --nodaemonize --fpm-config /opt/php$mm/etc/php-fpm.conf -c /opt/php$mm/etc/php.ini >/tmp/fpm$mm.out 2>&1 &
         for i in 1 2 3 4 5 6 7 8; do [ -f $pidf ] && break; sleep 1; done; [ -f $pidf ];;
  stop) [ -f $pidf ] && kill -QUIT $(cat $pidf); sleep 1; rm -f $pidf; exit 0;;
  reload) kill -USR2 $(cat $pidf); sleep 2;;
esac
SH
chmod +x /usr/local/bin/systemctl
fi

# --- aplicacion de prueba bajo el PHP vigente (mod_php)
W=/var/www/html/labtest; mkdir -p $W
cat > $W/info.php <<'PHP'
<?php echo "VER=" . PHP_VERSION . " SAPI=" . php_sapi_name() . "\n";
echo "PATH_INFO=" . (isset($_SERVER['PATH_INFO']) ? $_SERVER['PATH_INFO'] : '-') . "\n";
echo "AUTH=" . (isset($_SERVER['HTTP_AUTHORIZATION']) ? $_SERVER['HTTP_AUTHORIZATION'] : (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION']) ? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] : '-')) . "\n";
echo "SCRIPT=" . $_SERVER['SCRIPT_FILENAME'] . "\n";
$m = array('openssl','curl','mbstring','mysqli','pdo_mysql','gd','intl','ldap','soap','zip','sodium','xsl','gmp','bcmath','sockets','calendar','exif');
$f = array(); foreach ($m as $e) if (!extension_loaded($e)) $f[] = $e; echo "MODS_FALTAN=" . ($f ? implode(',', $f) : 'ninguno') . "\n";
PHP
cat > $W/sess.php <<'PHP'
<?php session_start(); $_SESSION['n'] = (isset($_SESSION['n']) ? $_SESSION['n'] : 0) + 1; echo "N=" . $_SESSION['n'] . " VER=" . PHP_VERSION . "\n";
PHP
cat > $W/up.php <<'PHP'
<?php echo "UP=" . (isset($_FILES['f']) ? $_FILES['f']['size'] . ":" . md5_file($_FILES['f']['tmp_name']) : 'nada') . "\n";
PHP
cat > $W/slow.php <<'PHP'
<?php sleep((int)(isset($_GET['s']) ? $_GET['s'] : 1)); echo "LENTO_OK\n";
PHP
echo '<?php echo "INDEX VER=".PHP_VERSION."\n";' > $W/index.php
id apache >/dev/null 2>&1 && chown -R apache:apache $W
# vhost con nombre para que baseline.sh lo descubra con "httpd -S"
cat > /etc/httpd/conf.d/zz-labvhost.conf <<'CONF'
<VirtualHost *:80>
    ServerName lab.test
    DocumentRoot /var/www/html
</VirtualHost>
CONF
mkdir -p /run/httpd; pgrep -x httpd >/dev/null && httpd -k graceful || httpd
sleep 2
U=http://127.0.0.1/labtest
base=$(curl -s $U/info.php | sed -n 's/^VER=\([0-9.]*\).*/\1/p')

echo "== LINEA BASE (PHP vigente $base)"
t "base: el PHP vigente responde" "[ -n '$base' ]"
echo "== DETECCION Y LINEA BASE"
t "detect-env sugiere estrategia" "$S/detect-env.sh | grep -q 'sugerencia'"
t "pkg-upgrade-plan imprime el plan y avisa que no ejecuta" "$S/pkg-upgrade-plan.sh 5.4 | grep -q 'NO ejecutados'"
t "baseline save descubre el vhost" "$S/baseline.sh save $TD/base.tsv /labtest/info.php | grep -q 'lab.test'"
t "baseline compare sin diferencias" "$S/baseline.sh compare $TD/base.tsv >/dev/null"
echo "== PUERTAS DE SEGURIDAD (sin las excepciones de la persona, deben negarse)"
t "gate_scope niega PHP fuera del alcance probado" "! env -u ACK_UNTESTED LP_SCOPE_FILE=/nonexistent bash -c 'source $S/lib.sh; gate_scope 86'"
t "gate_scope acepta con ACK_UNTESTED=yes y lo registra" "ACK_UNTESTED=yes bash -c 'source $S/lib.sh; gate_scope 86' 2>&1 | grep -q 'ACK_UNTESTED=yes'"
t "gate_auth niega paquete con fuentes sin autenticar" "mkdir -p $TD/ga/opt/php99 && echo x > $TD/ga/opt/php99/SOURCES-NOT-AUTHENTICATED.txt && tar -czf $TD/ga.tar.gz -C $TD/ga opt && ! env -u ACCEPT_UNAUTHENTICATED bash -c 'source $S/lib.sh; gate_auth $TD/ga.tar.gz'"
t "gate_auth acepta con ACCEPT_UNAUTHENTICATED=yes" "ACCEPT_UNAUTHENTICATED=yes bash -c 'source $S/lib.sh; gate_auth $TD/ga.tar.gz'"
echo "== BACKUP Y RESTAURACION"
t "backup create + verify" "id=\$(BACKUP_DIR=$TD/bk $S/backup.sh create lab | tail -1) && BACKUP_DIR=$TD/bk $S/backup.sh verify \$id"
t "backup restore sin confirmar se niega" "! BACKUP_DIR=$TD/bk $S/backup.sh restore \$(ls $TD/bk | head -1) --apply </dev/null"
echo "== PREFLIGHT"; $S/preflight.sh | tail -25
echo "== INSTALAR ${VERS[*]}"
t "install-package" "$S/install-package.sh $PKG ${VERS[*]}"
t "el PHP vigente sigue igual" "curl -s $U/info.php | grep -q 'VER=$base'"
for mm in "${VERS[@]}"; do t "CLI php$mm" "v=\$(/usr/local/bin/php$mm -v) && echo \"\$v\" | head -1"; done

echo "== SITIO labtest"
t "generate-site" "$S/generate-site.sh labtest $W --port 9450 --terminate 10 --memory 256M"
first=${VERS[0]}
echo "== SITIO SOMBRA (prueba sin tocar el trafico real)"
SP=${SHADOW_PORT:-18080}; export SHADOW_PORT=$SP   # con SELinux Enforcing usar un puerto http_port_t, por ejemplo SHADOW_PORT=8008
t "shadow up" "$S/shadow-site.sh up labtest $first lab.test"
v0=$(/usr/local/bin/php$first -r 'echo PHP_VERSION;')
t "la sombra responde con el PHP nuevo" "curl -s --resolve lab.test:$SP:127.0.0.1 http://lab.test:$SP/info.php | grep -q 'VER=$v0 SAPI=fpm-fcgi'"
t "el trafico real sigue en el PHP anterior" "curl -s $U/info.php | grep -q 'VER=$base'"
t "activar con sombra presente se niega" "! $S/activate-site.sh labtest $first"
t "shadow down limpia todo" "$S/shadow-site.sh down labtest && [ ! -f /etc/php-patch/state/labtest.shadow ] && [ ! -f /opt/php$first/etc/php-fpm.d/labtest.conf ] && ! ss -tln | grep -q ':$SP '"
t "el trafico real intacto tras la sombra" "$S/baseline.sh compare $TD/base.tsv >/dev/null"
for mm in "${VERS[@]}" "$first"; do
  if [ -f /etc/php-patch/state/labtest ]; then c=change-version.sh; else c=activate-site.sh; fi
  [ "$mm" = "$first" ] && [ "$c" = change-version.sh ] && [ "${VERS[*]}" = "$first" ] && continue
  echo "== $c -> php$mm"
  t "$c labtest $mm" "CHECK_HOST=lab.test CHECK_SCHEME=http CHECK_PATH=/labtest/info.php $S/$c labtest $mm"
  v=$(/usr/local/bin/php$mm -r 'echo PHP_VERSION;')
  t "responde $v por FPM" "curl -s $U/info.php | grep -q 'VER=$v SAPI=fpm-fcgi'"
  t "modulos completos" "curl -s $U/info.php | grep -q 'MODS_FALTAN=ninguno'"
  t "PATH_INFO" "curl -s $U/info.php/extra/ruta | grep -q 'PATH_INFO=/extra/ruta'"
  t "Authorization llega" "curl -s -H 'Authorization: Bearer abc123' $U/info.php | grep -q 'AUTH=Bearer abc123'"
  t "SCRIPT_FILENAME correcto" "curl -s $U/info.php | grep -q 'SCRIPT=$W/info.php'"
  t "directory index (index.php)" "curl -s $U/ | grep -q 'INDEX VER=$v'"
  t "sesion persiste" "rm -f $TD/cj; curl -s -c $TD/cj -b $TD/cj $U/sess.php >/dev/null; curl -s -c $TD/cj -b $TD/cj $U/sess.php | grep -q 'N=2'"
  head -c 3000000 /dev/urandom > $TD/up.bin; exp=$(md5sum < $TD/up.bin | cut -c1-32)
  t "subida 3 MB integra" "curl -s -F f=@$TD/up.bin $U/up.php | grep -q '3000000:$exp'"
  t "pagina lenta 3 s completa" "curl -s '$U/slow.php?s=3' | grep -q LENTO_OK"
  t "pagina de 15 s se corta por timeout (503/504)" "c=\$(curl -s -o /dev/null -w '%{http_code}' '$U/slow.php?s=15'); [ \$c = 504 ] || [ \$c = 503 ]"
  t "status.sh lista el sitio" "$S/status.sh | grep -q labtest"
done

echo "== ROLLBACK"
t "rollback-site" "$S/rollback-site.sh labtest"
t "vuelve el PHP vigente" "curl -s $U/info.php | grep -q 'VER=$base'"
t "pools vacios" "! ls /opt/php[0-9][0-9]/etc/php-fpm.d/*.conf"
t "re-activar tras rollback" "$S/activate-site.sh labtest $first && curl -s $U/info.php | grep -q 'SAPI=fpm-fcgi'"
t "check-modphp-retirement informa un resultado" "$S/check-modphp-retirement.sh | grep -q '^RESULTADO:'"
t "segundo rollback" "$S/rollback-site.sh labtest && curl -s $U/info.php | grep -q 'VER=$base'"
t "baseline final igual a la inicial" "$S/baseline.sh compare $TD/base.tsv >/dev/null"

echo "== FALLO CONTROLADO: pool invalido revierte"
mkdir -p /etc/php-patch/sites/roto; cp /etc/php-patch/sites/labtest/site.conf /etc/php-patch/sites/roto/site.conf
printf '[roto]\nlisten = 127.0.0.1:9451\nno_existe_directiva = 1\npm = invalido\n' > /etc/php-patch/sites/roto/pool.conf
t "activar pool roto falla" "! $S/activate-site.sh roto $first"
t "tras el fallo el PHP vigente esta intacto" "curl -s $U/info.php | grep -q 'VER=$base'"
t "sin estado ni pool residual" "[ ! -f /etc/php-patch/state/roto ] && [ ! -f /opt/php$first/etc/php-fpm.d/roto.conf ]"

echo "== RESULTADO: PASS=$pass FAIL=$fail"
[ $fail = 0 ]

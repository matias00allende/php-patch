#!/bin/bash
# build-php.sh <version> - compila PHP X.Y.Z hacia /opt/phpMM usando las dependencias de /opt/deps.
# EJECUTAR EN EL LABORATORIO DE COMPILACION (CentOS 7 desechable), NUNCA en produccion.
# Uso: ./build-php.sh 8.4.27
# La version la fija quien opera: tomar de php.net/ChangeLog-8.php la primera version de cada rama que corrige la
# vulnerabilidad en cuestion (no confiar en memoria ni en este archivo). El hash de la fuente se verifica con
# build/sources.sha256 (valor publicado en php.net/downloads) o con ALLOW_UNPINNED=1 tras compararlo a mano.
set -euo pipefail
VER=${1:?version, por ejemplo 8.4.27}
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version invalida '$VER' (formato X.Y.Z)"; exit 1; }
MM=$(echo "$VER" | cut -d. -f1,2 | tr -d .); P=/opt/php$MM
SRC=${SRC:-/root/src}; B=${B:-/root/build}; HERE=$(cd "$(dirname "$0")" && pwd); D=/opt/deps
B=$(readlink -f -- "$B" 2>/dev/null) || B=""; [[ "$B" =~ ^/[^/]+(/[^/]+)+$ ]] || { echo "B debe ser una ruta absoluta de al menos dos niveles (por ejemplo /root/build), no una raiz del sistema"; exit 1; }
[[ "$B" =~ ^/(root|tmp|var/tmp|home/[^/]+)/ ]] || [ "${FORCE_B:-0}" = 1 ] || { echo "B ($B) debe estar bajo /root, /tmp, /var/tmp o /home/<usuario>: se borran subdirectorios de B. Usa FORCE_B=1 solo si sabes que la ruta es exclusiva del build"; exit 1; }
mkdir -p "$SRC" "$B"
f=$SRC/php-$VER.tar.xz
[ -f "$f" ] || curl -fL --retry 3 -o "$f" "https://www.php.net/distributions/php-$VER.tar.xz"
if grep -q "  php-$VER.tar.xz\$" "$HERE/sources.sha256" 2>/dev/null; then ( cd "$SRC" && grep "  php-$VER.tar.xz\$" "$HERE/sources.sha256" | sha256sum -c - ) || exit 1
elif [ "${ALLOW_UNPINNED:-0}" = 1 ]; then echo "SIN HASH REGISTRADO: $(sha256sum "$f")  (compararlo con php.net/downloads)"; echo "$(basename "$f") $(sha256sum "$f" | cut -d" " -f1) (hash calculado, fuente NO autenticada, $(date +%F))" >> "$B/SOURCES-NOT-AUTHENTICATED-php-$VER.txt"
else echo "SIN HASH REGISTRADO para php-$VER.tar.xz: $(sha256sum "$f"). Comparar con php.net/downloads y registrar, o ALLOW_UNPINNED=1"; exit 1; fi

if [ -f /opt/rh/devtoolset-9/enable ]; then set +u; source /opt/rh/devtoolset-9/enable; set -u; fi   # enable referencia MANPATH sin definir
export PKG_CONFIG_PATH=$D/openssl/lib/pkgconfig:$D/openssl/lib64/pkgconfig:$D/lib/pkgconfig:$D/lib64/pkgconfig
export LD_LIBRARY_PATH=$D/lib:$D/lib64:$D/openssl/lib:$D/openssl/lib64
# rpath: el PHP compilado encuentra SUS librerias en /opt/deps sin tocar las del sistema
export LDFLAGS="-Wl,-rpath,$D/lib -Wl,-rpath,$D/lib64 -Wl,-rpath,$D/openssl/lib -Wl,-rpath,$D/openssl/lib64"
rm -rf "$B/php-$VER"; tar xf "$f" -C "$B"; cd "$B/php-$VER"
# En 8.2/8.3 pdo_odbc se indica con prefijo; desde 8.4 se detecta por pkg-config
case $MM in 82|83) ODBCOPT=unixODBC,$D;; *) ODBCOPT=unixODBC;; esac
# Conjunto de extensiones tipico de aplicaciones legadas. Agregar o quitar segun el inventario del servidor real.
#   CONFIGURE_OPTS="..."  REEMPLAZA el conjunto de extensiones por defecto (la base --prefix/--enable-fpm/--with-fpm-user se mantiene).
#                         Util en un servidor que no es el laboratorio EL7 y no tiene /opt/deps (por ejemplo una distro moderna
#                         donde solo se necesita FPM + openssl + zlib + opcache + pdo_mysql).
#   EXTRA_CONFIGURE="..." se AGREGA al final (con el conjunto por defecto o con CONFIGURE_OPTS). Ejemplo para sumar una extension:
#                         EXTRA_CONFIGURE="--with-pdo-pgsql" ./build-php.sh 8.3.36
DEFAULT_OPTS="--enable-mbstring --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
  --with-openssl --with-curl --with-zlib --enable-bcmath --enable-soap --with-libxml --enable-gd --with-freetype --with-jpeg \
  --with-ldap --with-sodium --with-zip --enable-intl --with-pdo-odbc=$ODBCOPT --enable-opcache --with-bz2 --enable-calendar \
  --enable-exif --enable-pcntl --enable-sockets --with-gmp --with-readline --with-xsl --enable-ftp --with-gettext \
  --enable-shmop --enable-sysvmsg --enable-sysvsem --enable-sysvshm"
# shellcheck disable=SC2086  # las opciones se separan por palabras a proposito
./configure --prefix=$P --with-config-file-path=$P/etc --with-config-file-scan-dir=$P/etc/php.d \
  --with-fpm-user=apache --with-fpm-group=apache --enable-fpm ${CONFIGURE_OPTS:-$DEFAULT_OPTS} ${EXTRA_CONFIGURE:-} \
  > "$B/configure-$VER.log" 2>&1 \
  || { grep -E '^configure: error' -A4 "$B/configure-$VER.log" | head -8; exit 1; }
make -j"$(nproc)" > "$B/make-$VER.log" 2>&1 || { grep -E ' error|Error [0-9]' "$B/make-$VER.log" | head; exit 1; }
make install > "$B/install-$VER.log" 2>&1
# php.ini de referencia: install-package.sh usa lib/php.ini-production como base (sin php.ini PHP corre con valores por defecto, por ejemplo display_errors activo)
cp -f php.ini-production php.ini-development "$P/lib/" || { echo "no pude copiar php.ini-production a $P/lib"; exit 1; }
$P/bin/php -v | head -1
[ -f "$B/SOURCES-NOT-AUTHENTICATED-php-$VER.txt" ] && cp "$B/SOURCES-NOT-AUTHENTICATED-php-$VER.txt" "$P/SOURCES-NOT-AUTHENTICATED.txt"
echo "Siguiente: extensiones externas (sqlsrv/pdo_sqlsrv si aplica, ver references/02-compilar-paquete.md) y make-package.sh"

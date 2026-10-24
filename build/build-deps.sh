#!/bin/bash
# build-deps.sh - compila en /opt/deps las librerias que el CentOS 7 trae demasiado viejas para PHP 8.x.
# EJECUTAR EN EL LABORATORIO DE COMPILACION (CentOS 7 desechable), NUNCA en el servidor de produccion.
# Uso: ./build-deps.sh [zlib openssl libxml2 icu curl sqlite odbc libzip]    (por defecto, todas en ese orden)
#
# Por que cada una (minimos de PHP; verificar contra la documentacion de la version que se compile):
#   openssl   PHP 8.1+ pide OpenSSL >= 1.0.2 y 8.4+ >= 1.1.1; CentOS 7 trae 1.0.2k
#   libxml2   PHP 8.x pide >= 2.9.4; CentOS 7 trae 2.9.1
#   icu       ext/intl de PHP 8.x pide ICU >= 50 (8.1+: 57); CentOS 7 trae 50.x
#   curl      PHP 8.4+ pide libcurl >= 7.61; CentOS 7 trae 7.29
#   sqlite    las extensiones SQLite de PHP 8.x piden como minimo 3.7.7 (confirmar con el configure de la rama exacta que compiles); suele alcanzar con el del sistema, se compila por consistencia y fixes
#   zlib      dependencia de curl/libxml2; se fija para no mezclar versiones
#   odbc      unixODBC reciente para pdo_odbc / drivers SQL Server
#   libzip    ext/zip de PHP 8.x pide libzip >= 0.11 (y != 1.3.1, != 1.7.0); CentOS 7 trae 0.10.1 y EPEL no tiene libzip5.
#             Requiere cmake: yum install cmake3 (EPEL). Se usa 1.7.3, sin cifrado AES ni bzip2/lzma, para no depender de libs del sistema.
# Las versiones de abajo son las que funcionaron; cambiarlas solo con prueba. Las fuentes se verifican con
# build/sources.sha256 (formato sha256sum). Sin hash registrado el script se detiene, salvo ALLOW_UNPINNED=1,
# y en ese caso imprime el hash calculado para que lo registres tras compararlo con la web oficial del proyecto.
set -euo pipefail
PREFIX=${PREFIX:-/opt/deps}
[[ "$PREFIX" =~ ^/opt/[A-Za-z0-9_][A-Za-z0-9._-]*$ && "$PREFIX" != *..* ]] || [ "${FORCE_PREFIX:-0}" = 1 ] || { echo "PREFIX ($PREFIX) debe ser /opt/<nombre>: se borran y enlazan rutas bajo el. Usa FORCE_PREFIX=1 solo si sabes lo que haces"; exit 1; }
SRC=${SRC:-/root/src}; B=${B:-/root/build}; HERE=$(cd "$(dirname "$0")" && pwd)
B=$(readlink -f -- "$B" 2>/dev/null) || B=""; [[ "$B" =~ ^/[^/]+(/[^/]+)+$ ]] || { echo "B debe ser una ruta absoluta de al menos dos niveles (por ejemplo /root/build), no una raiz del sistema"; exit 1; }
[[ "$B" =~ ^/(root|tmp|var/tmp|home/[^/]+)/ ]] || [ "${FORCE_B:-0}" = 1 ] || { echo "B ($B) debe estar bajo /root, /tmp, /var/tmp o /home/<usuario>: se borran subdirectorios de B. Usa FORCE_B=1 solo si sabes que la ruta es exclusiva del build"; exit 1; }
mkdir -p "$SRC" "$B" "$PREFIX"
JOBS=${JOBS:-$(nproc)}
if [ -f /opt/rh/devtoolset-9/enable ]; then set +u; source /opt/rh/devtoolset-9/enable; set -u; fi   # gcc moderno (yum install devtoolset-9 desde vault.centos.org/sclo)
export LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib64:$PREFIX/openssl/lib:$PREFIX/openssl/lib64
export PKG_CONFIG_PATH=$PREFIX/openssl/lib/pkgconfig:$PREFIX/openssl/lib64/pkgconfig:$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig
export LDFLAGS="-Wl,-rpath,$PREFIX/lib -Wl,-rpath,$PREFIX/lib64 -Wl,-rpath,$PREFIX/openssl/lib -Wl,-rpath,$PREFIX/openssl/lib64 -L$PREFIX/lib"
export CPPFLAGS="-I$PREFIX/include"

V_ZLIB=${V_ZLIB:-1.3.1}; V_OPENSSL=${V_OPENSSL:-3.5.9}; V_LIBXML2=${V_LIBXML2:-2.9.14}; V_ICU=${V_ICU:-64.2}
V_CURL=${V_CURL:-8.23.0}; V_SQLITE=${V_SQLITE:-3.54.1}; V_SQLITE_YEAR=${V_SQLITE_YEAR:-2026}; V_ODBC=${V_ODBC:-2.3.12}; V_LIBZIP=${V_LIBZIP:-1.7.3}

fetch() { # fetch <archivo-local> <url>
  local f=$SRC/$1
  [ -f "$f" ] || env -u LD_LIBRARY_PATH curl -fL --retry 3 -o "$f" "$2"
  [ -s "$f" ] || { echo "descarga fallida o vacia: $1"; exit 1; }
  local h; h=$(sha256sum "$f" | cut -d' ' -f1)
  if grep -q "  $1\$" "$HERE/sources.sha256" 2>/dev/null; then
    ( cd "$SRC" && grep "  $1\$" "$HERE/sources.sha256" | sha256sum -c - ) || { echo "HASH NO COINCIDE: $1"; exit 1; }
  elif [ "${ALLOW_UNPINNED:-0}" = 1 ]; then
    echo "SIN HASH REGISTRADO para $1: $h  (compararlo con el sitio oficial y agregarlo a sources.sha256)"
    echo "$1 $h (hash calculado, fuente NO autenticada, $(date +%F))" >> "$PREFIX/SOURCES-NOT-AUTHENTICATED.txt"
  else
    echo "SIN HASH REGISTRADO para $1 (calculado: $h). Verificar contra el sitio oficial, registrar en sources.sha256 o usar ALLOW_UNPINNED=1"; exit 1
  fi
  echo "$f"
}
unpack() { [ -f "$1" ] || { echo "falta el archivo fuente $1 (fallo la descarga o la verificacion)"; exit 1; }; rm -rf "${B:?}/${2:?}"; mkdir -p "$B/$2"; tar xf "$1" -C "$B/$2" --strip-components=1; cd "$B/$2"; }

do_zlib()    { unpack "$(fetch zlib-$V_ZLIB.tar.gz https://zlib.net/fossils/zlib-$V_ZLIB.tar.gz | tail -1)" zlib
               ./configure --prefix=$PREFIX && make -j$JOBS && make install; }
do_openssl() { unpack "$(fetch openssl-$V_OPENSSL.tar.gz https://github.com/openssl/openssl/releases/download/openssl-$V_OPENSSL/openssl-$V_OPENSSL.tar.gz | tail -1)" openssl
               ./config --prefix=$PREFIX/openssl --openssldir=$PREFIX/openssl shared zlib -Wl,-rpath,$PREFIX/openssl/lib64 -Wl,-rpath,$PREFIX/openssl/lib
               make -j$JOBS && make install_sw install_ssldirs
               # los certificados de confianza los gestiona el sistema, no esta copia
               rm -rf -- "$PREFIX/openssl/certs"; ln -sfn /etc/pki/tls/certs "$PREFIX/openssl/certs"; ln -sfn /etc/pki/tls/cert.pem "$PREFIX/openssl/cert.pem"; }
do_libxml2() { unpack "$(fetch libxml2-$V_LIBXML2.tar.xz https://download.gnome.org/sources/libxml2/${V_LIBXML2%.*}/libxml2-$V_LIBXML2.tar.xz | tail -1)" libxml2
               ./configure --prefix=$PREFIX --without-python --without-lzma --with-zlib=$PREFIX --with-iconv && make -j$JOBS && make install; }
do_icu()     { unpack "$(fetch icu4c-${V_ICU//./_}-src.tgz https://github.com/unicode-org/icu/releases/download/release-${V_ICU//./-}/icu4c-${V_ICU//./_}-src.tgz | tail -1)" icu
               cd source && ./configure --prefix=$PREFIX --disable-tests --disable-samples && make -j$JOBS && make install; }
do_curl()    { unpack "$(fetch curl-$V_CURL.tar.xz https://curl.se/download/curl-$V_CURL.tar.xz | tail -1)" curl
               ./configure --prefix=$PREFIX --with-openssl=$PREFIX/openssl --with-zlib=$PREFIX --without-libpsl --disable-ldap --disable-ldaps \
                 --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libssh2 --with-ca-bundle=/etc/pki/tls/certs/ca-bundle.crt \
               && make -j$JOBS && make install; }
# SQLite: tarball "amalgamation" oficial de sqlite.org (el proyecto publica su SHA3-256; el SHA256 de build/sources.sha256 se contrasto contra ese).
# El nombre numerico es X*1000000+Y*10000+Z*100 (3.54.1 -> 3540100); el directorio de la URL es el anio de la publicacion.
do_sqlite()  { local n; n=$(echo "$V_SQLITE" | awk -F. '{printf "%d%02d%02d00", $1, $2, $3}')
               unpack "$(fetch sqlite-autoconf-$n.tar.gz https://www.sqlite.org/$V_SQLITE_YEAR/sqlite-autoconf-$n.tar.gz | tail -1)" sqlite
               CFLAGS="-O2 -DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_SECURE_DELETE" \
                 ./configure --prefix=$PREFIX --enable-load-extension && make -j$JOBS && make install; }
do_odbc()    { unpack "$(fetch unixODBC-$V_ODBC.tar.gz https://www.unixodbc.org/unixODBC-$V_ODBC.tar.gz | tail -1)" unixodbc
               ./configure --prefix=$PREFIX --sysconfdir=/etc --disable-gui --disable-drivers --enable-ltdl-install && make -j$JOBS && make install; }

do_libzip()  { CM=$(command -v cmake3 || command -v cmake) || { echo "falta cmake (yum install cmake3, EPEL)"; return 1; }
               unpack "$(fetch libzip-$V_LIBZIP.tar.xz https://github.com/nih-at/libzip/releases/download/v$V_LIBZIP/libzip-$V_LIBZIP.tar.xz | tail -1)" libzip
               mkdir -p build && cd build && "$CM" .. -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH=$PREFIX \
                 -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
                 -DENABLE_OPENSSL=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF \
                 -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF && make -j$JOBS && make install; }

# cada biblioteca se compila en un proceso aparte: dentro de "|| ..." bash ignora set -e y una falla a medias podria pasar por exito
if [ "${1:-}" = --only ]; then
  c=$2; "do_$c"
  case $c in zlib) a="$PREFIX/lib/libz.so";; openssl) a="$PREFIX/openssl/lib*/libssl.so.3";; libxml2) a="$PREFIX/lib/libxml2.so";; icu) a="$PREFIX/lib/libicuuc.so";;
    curl) a="$PREFIX/lib/libcurl.so";; sqlite) a="$PREFIX/lib/libsqlite3.so";; odbc) a="$PREFIX/lib/libodbc.so";; libzip) a="$PREFIX/lib/libzip.so";; esac
  ls $a >/dev/null 2>&1 || { echo "no existe el artefacto esperado de $c ($a): la compilacion no termino bien"; exit 1; }
  exit 0
fi
for c in ${@:-zlib openssl libxml2 icu curl sqlite odbc libzip}; do
  echo "=== $c"
  bash "$0" --only "$c" > "$B/$c.log" 2>&1 || { echo "FALLO $c: ver $B/$c.log"; tail -15 "$B/$c.log"; exit 1; }
  echo "ok $c"
done
ls $PREFIX/lib | grep -E 'libxml2|libicuuc|libcurl|libz' | head

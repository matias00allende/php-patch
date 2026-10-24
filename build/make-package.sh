#!/bin/bash
# make-package.sh - empaqueta /opt/deps y los /opt/phpMM del laboratorio en tar.gz con SHA256SUMS.
# Uso: ./make-package.sh <dir-salida> <MM:X.Y.Z> [<MM:X.Y.Z> ...]       ej.: ./make-package.sh /root/paq 83:8.3.36 84:8.4.27
# Opcional: BUNDLE_LIBS="libonig libsodium" copia esas librerias del sistema del laboratorio a /opt/deps/lib
# (con rpath no hace falta que el servidor las tenga). Hacerlo ANTES de empaquetar, si ldd las muestra fuera de /opt.
set -eu
OUT=${1:?directorio de salida}; shift
mkdir -p "$OUT"; cd "$OUT"
# no se pisan artefactos anteriores (pueden servir para rollback): usa un directorio nuevo o OVERWRITE=1
if [ -n "$(ls php-deps-*.tar.gz php-*-opt.tar.gz SHA256SUMS 2>/dev/null)" ] && [ "${OVERWRITE:-0}" != 1 ]; then echo "$OUT ya contiene paquetes: usa un directorio nuevo u OVERWRITE=1"; exit 1; fi
rm -f php-deps-*.tar.gz php-*-opt.tar.gz SHA256SUMS   # solo los archivos que genera este script
[ -f /opt/deps/SOURCES-NOT-AUTHENTICATED.txt ] && echo "AVISO: /opt/deps incluye fuentes NO autenticadas (SOURCES-NOT-AUTHENTICATED.txt): no usar este paquete en produccion sin la verificacion de references/02"
for l in ${BUNDLE_LIBS:-}; do
  for f in /usr/lib64/$l*.so*; do [ -e "$f" ] && cp -a "$f" /opt/deps/lib/; done
done
tar -czf php-deps-1.tar.gz -C / opt/deps
for p in "$@"; do
  mm=${p%%:*}; v=${p##*:}
  [[ "$mm" =~ ^[0-9]{2}$ && "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "argumento invalido '$p' (formato MM:X.Y.Z, por ejemplo 83:8.3.36)"; exit 1; }
  got=$(/opt/php$mm/bin/php -v | head -1 | awk '{print $2}')
  [ "$got" = "$v" ] || { echo "version distinta en /opt/php$mm: $got (esperada $v)"; exit 1; }
  tar -czf php-$v-el7-opt.tar.gz -C / opt/php$mm
done
sha256sum ./*.tar.gz | sed 's# \./# #' > SHA256SUMS
ls -la; cat SHA256SUMS
echo "== librerias del sistema (fuera de /opt) que el servidor destino debe tener:"
for m in $(for p in "$@"; do echo "${p%%:*}"; done); do
  for f in /opt/php$m/bin/php /opt/php$m/sbin/php-fpm $(find /opt/php$m/lib -name '*.so'); do ldd "$f" 2>/dev/null; done
done | grep '=>' | grep -v '/opt/' | awk '{print $1}' | sort -u | tr '\n' ' '; echo
echo "Guardar SHA256SUMS por un canal distinto al de los paquetes y registrar versiones y hashes de fuentes (SBOM minimo)."

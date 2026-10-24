#!/bin/bash
# compat-scan.sh - SOLO LECTURA sobre el codigo. Estima la compatibilidad de un sitio con PHP 8.x.
# Uso: ./compat-scan.sh <directorio-del-sitio> [binario-php]
#   binario-php por defecto: /opt/php83/bin/php (el PHP parchado ya instalado, o el del laboratorio)
# 1) php -l (lint) de todos los .php con el binario nuevo: detecta errores de sintaxis y fatales de compilacion.
# 2) busca funciones/patrones eliminados en PHP 8 que el lint NO detecta (fallan en tiempo de ejecucion).
# Un lint limpio NO prueba compatibilidad: solo descarta lo grueso. La prueba real es el piloto con el sitio vivo.
export LC_ALL=C
dir=${1:?directorio del sitio}; php=${2:-/opt/php83/bin/php}
[ -d "$dir" ] || { echo "no existe $dir"; exit 2; }
[ -x "$php" ] || { echo "no existe el binario $php"; exit 2; }
echo "== $dir con $($php -v | head -1)"
total=$(find "$dir" -name '*.php' -not -path '*/node_modules/*' -not -path '*/vendor/*' | wc -l)
echo "== lint de $total archivos (sin vendor/ ni node_modules/)"
bad=$(find "$dir" -name '*.php' -not -path '*/node_modules/*' -not -path '*/vendor/*' -print0 \
  | xargs -0 -P4 -n1 "$php" -n -l 2>&1 | grep -vE '^No syntax errors' | head -40)
[ -n "$bad" ] && echo "$bad" || echo "sin errores de sintaxis"
echo "== patrones eliminados o cambiados en PHP 7.x/8.x (revisar cada coincidencia)"
pat='get_magic_quotes_gpc|get_magic_quotes_runtime|create_function\(|\beach\(|mysql_(connect|query|fetch|select_db|real_escape|num_rows|close|error)|\bereg(i)?(_replace)?\(|\bsplit\(|mcrypt_|money_format\(|FILTER_SANITIZE_STRING|utf8_(en|de)code|\$HTTP_RAW_POST_DATA|\bwddx_|\bimap_|(^|[^>:\w])(strftime|gmstrftime)\('
find "$dir" -name '*.php' -not -path '*/node_modules/*' -print0 | xargs -0 grep -noE "$pat" 2>/dev/null | head -60   # solo archivo:linea:patron, nunca la linea completa (puede traer credenciales)
echo "== dependencias que suelen necesitar actualizacion"
find "$dir" -maxdepth 3 -name composer.lock -exec echo "composer.lock: {}" \; 2>/dev/null | head
echo "FIN. Interpretar: 'Deprecated' normalmente no es fatal para PHP, pero una aplicacion con manejador de errores propio puede fallar o llenar los logs; funciones eliminadas y errores de sintaxis si bloquean. Valida con pruebas funcionales."

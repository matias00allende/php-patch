#!/bin/bash
# remote-version-check.sh - PRE-VALIDACION PASIVA desde fuera: estima la version de PHP que anuncia cada URL.
# Uso: ./remote-version-check.sh <archivo-con-urls | URL> [...]     (una URL por linea; # comenta)
# Hace un GET normal por URL y lee las cabeceras Server y X-Powered-By. No envia cargas ni sube archivos, pero cualquier
# GET puede tener efectos en la aplicacion (crear una sesion, registrar la visita): apunta a una pagina revisada.
# Usalo solo contra sistemas propios o con autorizacion escrita.
#
# LIMITES (leer): es una INFERENCIA. Muchos servidores ocultan la cabecera (expose_php=Off, ServerTokens Prod) y
# los paquetes de RHEL, Ubuntu y Debian aplican parches sin subir el numero upstream: una version "baja" puede
# estar corregida y una ausencia de cabecera no prueba nada. Confirma siempre con scripts/inventory.sh en el
# servidor y con el aviso de seguridad del proveedor.
#
# Version corregida por rama (contrastada con php.net el 2026-10-24; si sale una posterior, sobrescribir FIXED_xx):
#   8.2 -> 8.2.35   8.3 -> 8.3.36   8.4 -> 8.4.27   8.5 -> 8.5.12
#   5.x, 7.x, 8.0 y 8.1 estan fuera de soporte: sin version corregida upstream.
set -u
FIXED_82=${FIXED_82:-8.2.35}; FIXED_83=${FIXED_83:-8.3.36}; FIXED_84=${FIXED_84:-8.4.27}; FIXED_85=${FIXED_85:-8.5.12}
TIMEOUT=${TIMEOUT:-15}
# Por defecto se valida el certificado TLS: un intermediario podria alterar las cabeceras. Para un sistema PROPIO con certificado
# autofirmado o vencido, INSECURE_TLS=1 lo omite y el resultado se marca "(TLS sin validar)": no es una lectura autenticada.
CURL_TLS=; [ "${INSECURE_TLS:-0}" = 1 ] && CURL_TLS=-k
[ $# -ge 1 ] || { echo "Uso: $0 <archivo-con-urls | URL> [...]   (lee los LIMITES en la cabecera del script)"; exit 2; }

# ver_lt A B: 0 si A < B (orden numerico por componentes)
ver_lt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

urls=()
for a in "$@"; do
  if [ -f "$a" ]; then
    while IFS= read -r l; do l=${l%%#*}; l=$(echo "$l" | tr -d '[:space:]'); [ -n "$l" ] && urls+=("$l"); done < "$a"
  else urls+=("$a"); fi
done

verdict() {   # verdict <version>
  local v=$1 mm fixed
  mm=$(echo "$v" | cut -d. -f1,2)
  case $mm in
    8.2) fixed=$FIXED_82;; 8.3) fixed=$FIXED_83;; 8.4) fixed=$FIXED_84;; 8.5) fixed=$FIXED_85;;
    5.*|7.*|8.0|8.1) echo "EOL-VULNERABLE|sin version corregida upstream (rama fuera de soporte; un proveedor con soporte extendido puede haber corregido por backport)"; return;;
    *) echo "DESCONOCIDA|rama no tabulada ($mm): revisar a mano"; return;;
  esac
  if ver_lt "$v" "$fixed"; then echo "VULNERABLE?|anuncia $v < $fixed (puede ser un backport del proveedor)"
  else echo "SOBRE-UMBRAL|anuncia $v >= $fixed (no prueba que este parchado: un backport o otra CVE pueden aplicar)"; fi
}

[ ${#urls[@]} -gt 0 ] || { echo "no hay URLs que revisar"; exit 2; }
printf '%-45s %-14s %-12s %s\n' URL VERSION VEREDICTO NOTA
bad=0; incon=0
for u in "${urls[@]}"; do
  case $u in http://*|https://*) ;; *) u="https://$u";; esac
  ud=$(printf '%s' "${u%%\?*}" | sed 's#//[^/@]*@#//***@#')   # al mostrar la URL se omiten usuario:clave y query
  raw=$(curl -s $CURL_TLS --proto '=http,https' --max-time "$TIMEOUT" -o /dev/null -D - -- "$u" 2>/dev/null; echo "@@RC=$?")
  crc=${raw##*@@RC=}; h=$(printf '%s' "${raw%@@RC=*}" | tr -d '\r')
  if [ -z "$h" ]; then
    incon=$((incon+1))
    if [ "$crc" = 60 ] || [ "$crc" = 35 ] || [ "$crc" = 51 ] || [ "$crc" = 58 ]; then printf '%-45s %-14s %-12s %s\n' "$ud" - ERROR-TLS "certificado no valido: si el sistema es tuyo, reintenta con INSECURE_TLS=1"
    else printf '%-45s %-14s %-12s %s\n' "$ud" - SIN-RESPUESTA "no respondio en ${TIMEOUT}s"; fi
    continue
  fi
  v=$(echo "$h" | grep -i '^x-powered-by:' | grep -io 'php/[0-9][0-9.]*' | head -1 | cut -d/ -f2)
  [ -z "$v" ] && v=$(echo "$h" | grep -i '^server:' | grep -io 'php/[0-9][0-9.]*' | head -1 | cut -d/ -f2)
  if [ -z "$v" ]; then
    incon=$((incon+1))
    printf '%-45s %-14s %-12s %s\n' "$ud" - NO-ANUNCIA "sin version en cabeceras: no concluyente, usar inventory.sh en el servidor"
    continue
  fi
  r=$(verdict "$v"); st=${r%%|*}; nt=${r#*|}
  case $st in 'VULNERABLE?'|EOL-VULNERABLE) bad=$((bad+1));; esac
  [ "${INSECURE_TLS:-0}" = 1 ] && case $u in https://*) nt="$nt (TLS sin validar)";; esac
  printf '%-45s %-14s %-12s %s\n' "$ud" "$v" "$st" "$nt"
done
echo "RESULTADO: $bad URL(s) con version anunciada vulnerable o sin soporte; $incon sin dato (inferencia, no prueba; codigo de salida 0 NO significa que todo este parchado)"
[ "$bad" = 0 ]

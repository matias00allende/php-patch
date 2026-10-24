#!/bin/bash
# baseline.sh - captura y compara el estado HTTP de los virtual hosts que Apache lista con -S (no cubre ServerAlias ni vhosts agregados despues), sin escribir en el servidor
# salvo el archivo de salida que indiques. Funciona con httpd (RHEL/CentOS/Amazon) y apache2 (Debian/Ubuntu).
# Uso:  ./baseline.sh save <archivo.tsv> [ruta]      guarda nombre, puerto, ruta, codigo, tiempo, bytes
#       ./baseline.sh compare <archivo.tsv>          vuelve a medir y marca diferencias
# Se consulta el propio Apache por 127.0.0.1 con --resolve (sin DNS ni balanceador), por lo que mide al servidor y
# no a la red. Usalo antes y despues de CADA cambio: es la defensa contra "creia que estaba bien".
export LC_ALL=C
mode=${1:?save|compare}; file=${2:?archivo}; path=${3:-/}
AP=$( (command -v httpd || command -v apache2ctl || command -v apachectl) 2>/dev/null | head -1 )
# SUSE: "httpd -S" a secas ignora los -D y modulos que arma start_apache2 (p. ej. vhosts bajo IfDefine SSL); apachectl los incluye
[ -x /usr/sbin/start_apache2 ] && command -v apachectl >/dev/null 2>&1 && AP=$(command -v apachectl)
[ -n "$AP" ] || { echo "no encontre httpd/apache2ctl"; exit 2; }
case "$AP" in */httpd) SOPT=-S;; *) SOPT=-S;; esac
# "httpd -S" tiene dos formatos segun cuantos vhosts comparten direccion:
#   "port 80 namevhost NOMBRE (archivo:linea)"   (varios vhosts en la misma direccion)
#   "*:80   NOMBRE (archivo:linea)"              (un solo vhost en esa direccion)
targets() { $AP $SOPT 2>&1 | awk '
  /port [0-9]+ namevhost / { for (i=1;i<=NF;i++) { if ($i=="port") p=$(i+1); if ($i=="namevhost") n=$(i+1) } print n, p; next }
  $1 ~ /:[0-9]+$/ && $3 ~ /^\(/ { m=split($1, a, ":"); print $2, a[m] }' | sort -u; }
measure() { # name port path
  local n=$1 p=$2 pa=$3 scheme=http out
  case " ${BASELINE_HTTPS_PORTS:-443} " in *" $p "*) scheme=https;; esac   # otros puertos TLS: BASELINE_HTTPS_PORTS="443 8443"
  out=$(curl -sk --noproxy '*' -o /dev/null --max-time "${PROBE_TIMEOUT:-60}" --resolve "$n:$p:127.0.0.1" -w '%{http_code}\t%{time_total}\t%{size_download}' "$scheme://$n:$p$pa" 2>/dev/null) || out=$'000\t0\t0'
  [ -z "$out" ] && out=$'000\t0\t0'
  printf '%s\t%s\t%s\t%s\n' "$n" "$p" "$pa" "$out"
}
case $mode in
  save)
    : > "$file"
    targets | while read -r n p; do measure "$n" "$p" "$path" >> "$file"; done
    echo "guardado $(wc -l < "$file") vhosts en $file"; cut -f1,2,4 "$file" | column -t 2>/dev/null || cut -f1,2,4 "$file";;
  compare)
    [ -f "$file" ] || { echo "no existe $file"; exit 2; }
    [ -s "$file" ] || { echo "la linea base $file esta vacia: no se puede comparar"; exit 2; }
    bad=0; unhealthy=0
    while IFS=$'\t' read -r n p pa c0 t0 s0; do
      now=$(measure "$n" "$p" "$pa"); c1=$(echo "$now" | cut -f4); t1=$(echo "$now" | cut -f5); s1=$(echo "$now" | cut -f6)
      flag=ok
      case "$c1" in 5*|000) unhealthy=$((unhealthy+1));; esac
      if [ "$c0" != "$c1" ]; then
        case "$c1" in 5*|000) flag=REGRESION;; *) flag=CAMBIO;; esac
      elif [ "$s0" -gt 0 ] 2>/dev/null && [ "$c1" = 200 ]; then
        d=$(( (s1 > s0 ? s1 - s0 : s0 - s1) * 100 / s0 )); [ "$d" -gt 20 ] && flag="TAMANO(${d}%)"
      fi
      [ "$flag" = ok ] || bad=$((bad+1))
      printf '%-12s %-45s %s antes=%s ahora=%s (%ss -> %ss)\n' "$flag" "$n:$p" "$pa" "$c0" "$c1" "$t0" "$t1"
    done < "$file"
    [ $unhealthy = 0 ] || echo "AVISO: $unhealthy vhosts sin respuesta o con 5xx ahora (si ya fallaban en la linea base, 'sin diferencias' NO significa que esten sanos)"
    [ $bad = 0 ] && echo "RESULTADO: sin diferencias" || echo "RESULTADO: $bad vhosts con diferencias (REGRESION = paso a 5xx o sin respuesta; revisar antes de continuar)"
    [ $bad = 0 ] && [ $unhealthy = 0 ];;
  *) echo "modo desconocido $mode"; exit 2;;
esac

#!/bin/bash
# generate-site.sh - crea las definiciones de un sitio (pool.conf y site.conf). No toca Apache ni FPM.
# Uso: sudo ./generate-site.sh <slug> <docroot> [--port N|auto] [--terminate SEG] [--memory 256M] [--upload 64M] [--children N]
# Resultado: /etc/php-patch/sites/<slug>/{pool.conf,site.conf}. Revisarlos a mano antes de activar:
# los limites deben partir de lo que el sitio ya usa, no de valores teoricos.
source "$(dirname "$0")/lib.sh"
need_root
TPL=${TPL:-$(cd "$(dirname "$0")/../assets/templates" && pwd)}
slug=${1:?slug}; doc=${2:?docroot}; shift 2; valid_slug "$slug"
port=auto; term=120; mem=256M; up=64M; kids=5
while [ $# -gt 0 ]; do case $1 in
  --port) port=$2; shift 2;; --terminate) term=$2; shift 2;; --memory) mem=$2; shift 2;;
  --upload) up=$2; shift 2;; --children) kids=$2; shift 2;; *) die "opcion desconocida $1";; esac; done
# validacion: estos valores se interpolan en sed y en archivos de configuracion
[[ "$term" =~ ^[0-9]{1,5}$ ]] || die "--terminate debe ser un numero de segundos"
[[ "$kids" =~ ^[0-9]{1,3}$ ]] && [ "$kids" -ge 1 ] || die "--children debe ser un entero entre 1 y 999"
[[ "$mem" =~ ^[0-9]{1,5}[MmGg]$ ]] || die "--memory debe tener la forma 256M o 1G"
[[ "$up" =~ ^[0-9]{1,5}[MmGg]$ ]] || die "--upload debe tener la forma 64M o 1G"
[ "$port" = auto ] || { [[ "$port" =~ ^[0-9]{2,5}$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; } || die "--port debe ser auto o un numero entre 1024 y 65535"
[ -d "$doc" ] || die "no existe el docroot $doc"
[ -f "$STATE/$slug" ] && die "$slug esta activo en FPM: regenerar sus definiciones cambiaria el puerto y la reversion. Haz rollback-site.sh $slug primero"
doc=${doc%/}
doc=$(cd "$doc" && pwd -P) || die "docroot no accesible"
[[ "$doc" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "el docroot contiene caracteres no admitidos (use letras, digitos, _ . - /)"
if [ "$port" = auto ]; then
  used=$( { ss -tln | awk '{print $4}' | sed -n 's/.*:\([0-9]*\)$/\1/p'; sed -n 's/^listen *= *127.0.0.1:\([0-9]*\).*/\1/p' "$SITES_DEF"/*/pool.conf 2>/dev/null; } | sort -u)
  for p in $(seq $PORT_MIN $PORT_MAX); do echo "$used" | grep -qx $p || { port=$p; break; }; done
  [ "$port" != auto ] || die "sin puertos libres en $PORT_MIN-$PORT_MAX"
else
  grep -lE "^listen *= *127.0.0.1:$port\$" "$SITES_DEF"/*/pool.conf 2>/dev/null | grep -qv "/$slug/" && die "el puerto $port ya lo usa otro sitio"
fi
slow=$(( term > 15 ? 15 : (term > 1 ? term / 2 : 1) ))  # FPM exige slowlog_timeout <= terminate_timeout
ensure_backup generate
d=$SITES_DEF/$slug; mkdir -p "$d"
# si ya habia definiciones (posiblemente editadas a mano), se conserva una copia fuera de sites/ (que alimenta la asignacion de puertos)
if [ -f "$d/pool.conf" ] || [ -f "$d/site.conf" ]; then
  prev=$LP_ETC/sites.prev/$slug.$(date +%Y%m%d%H%M%S); mkdir -p "$prev" && cp -a "$d/." "$prev/" || die "no pude conservar las definiciones anteriores de $slug"
  log "definiciones anteriores de $slug conservadas en $prev"
fi
sed -e "s|@SLUG@|$slug|g;s|@PORT@|$port|g;s|@WEB_USER@|$WEB_USER|g;s|@TERMINATE@|$term|g;s|@MEMORY@|$mem|g;s|@UPLOAD@|$up|g;s|@MAX_CHILDREN@|$kids|g;s|@SLOW@|$slow|g;s|@DOCROOT@|$doc|g" \
    "$TPL/pool.conf.tpl" > "$d/pool.conf.new" && mv -f "$d/pool.conf.new" "$d/pool.conf" || die "no pude escribir pool.conf"
sed -e "s|@SLUG@|$slug|g;s|@PORT@|$port|g;s|@DOCROOT@|$doc|g;s|@PROXY_TIMEOUT@|$((term+10))|g;s|@APA_ACTIVE@|$APA_ACTIVE|g;s|@APA_OFF@|$APA_OFF|g" \
    "$TPL/site.conf.tpl" > "$d/site.conf.new" && mv -f "$d/site.conf.new" "$d/site.conf" || die "no pude escribir site.conf"
log "definiciones de $slug en $d (puerto $port, docroot $doc). Siguiente: activate-site.sh $slug <MM>"

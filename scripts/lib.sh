#!/bin/bash
# lib.sh - funciones comunes de php-patch. Se carga con "source".
# Convenciones (todas sobreescribibles por variable de entorno):
#   /opt/phpMM                      binarios de PHP parchado (MM = 82, 83, 84, 85...)
#   /etc/php-patch           definiciones de sitios (sites/) y estado (state/)
#   /etc/httpd/php-patch     active/ (sitios en FPM) y off/ (sitios revertidos)
# Los mensajes de los scripts son ASCII a proposito: algunas consolas remotas
# (SSM, SSH sin locale UTF-8) corrompen los acentos.
set -u
export LC_ALL=C
LP_NAME=${LP_NAME:-php-patch}
LP_ETC=/etc/$LP_NAME
SITES_DEF=$LP_ETC/sites
STATE=$LP_ETC/state
HTTPD_BIN=${HTTPD_BIN:-httpd}
HTTPD_ETC=${HTTPD_ETC:-/etc/httpd}
APA_BASE=$HTTPD_ETC/$LP_NAME
APA_ACTIVE=$APA_BASE/active
APA_OFF=$APA_BASE/off
APA_INCLUDE=$HTTPD_ETC/conf.d/00-$LP_NAME.conf
WEB_USER=${WEB_USER:-apache}
# Estos scripts operan sobre la disposicion de la familia RHEL (/etc/httpd). En Debian/Ubuntu (/etc/apache2) la
# estrategia B no esta soportada: usar la estrategia A (scripts/pkg-upgrade-plan.sh y references/00 y 08).
if [ -z "${LP_ALLOW_NON_RHEL:-}" ] && [ ! -d /etc/httpd ] && [ -d /etc/apache2 ]; then
  echo "Este script es para la disposicion RHEL (/etc/httpd). Aqui hay /etc/apache2 (Debian/Ubuntu/SUSE)." >&2
  echo "Use la estrategia A: scripts/pkg-upgrade-plan.sh (references/00-decidir-estrategia.md y 08-distribuciones.md)." >&2
  exit 3
fi
PORT_MIN=${PORT_MIN:-9400}
PORT_MAX=${PORT_MAX:-9499}
LOG=/var/log/$LP_NAME.log
LP_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2; }
die() { log "ERROR: $*"; exit 1; }
need_root() {
  [ "$(id -u)" = 0 ] || die "ejecutar como root (sudo)"
  # una sola operacion a la vez: dos ejecuciones simultaneas podrian elegir el mismo puerto o pisar el estado. Los scripts hijos heredan el candado.
  # (directorio con el PID dentro: un candado de archivo lo heredarian los demonios que arranca el laboratorio sin systemd)
  [ -n "${LP_LOCK_HELD:-}" ] && return 0
  local lk=/run/lock/php-patch.d pid
  mkdir -p /run/lock 2>/dev/null
  if ! mkdir "$lk" 2>/dev/null; then
    pid=$(cat "$lk/pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then die "hay otra operacion de php-patch en curso (PID $pid)"; fi
    rm -r "$lk" 2>/dev/null; mkdir "$lk" 2>/dev/null || die "no pude tomar el candado $lk"
  fi
  echo $$ > "$lk/pid"; export LP_LOCK_HELD=1
  trap 'rm -r /run/lock/php-patch.d 2>/dev/null' EXIT
}
valid_mm() { echo "$1" | grep -Eq '^[0-9]{2}$' || die "version invalida '$1' (dos digitos, por ejemplo 83 para PHP 8.3)"; }
valid_slug() { echo "$1" | grep -Eq '^[a-z0-9][a-z0-9_.-]*$' && ! echo "$1" | grep -Eq '\.(shadow|tmp|rollback\..*)$' || die "slug invalido '$1' (minusculas, digitos, - _ .)"; }
mm_dotted() { echo "${1:0:1}.${1:1}"; }
site_mm() { [ -f "$STATE/$1" ] && sed -n 's/^MM=//p' "$STATE/$1" || true; }

# ensure_backup <motivo>: respaldo de la configuracion ANTES de cambiar el sistema (backup.sh). Si no puede crearlo
# (espacio, permisos), aborta sin haber cambiado nada. Reutiliza un respaldo de los ultimos BACKUP_REUSE_MIN minutos (10)
# para no crear decenas en una ola de activaciones. No hay variable para omitirlo: sin respaldo no se cambia nada.
ensure_backup() {
  local root=${BACKUP_DIR:-/var/backups/$LP_NAME} reuse=${BACKUP_REUSE_MIN:-10} recent
  recent=$(find "$root" -maxdepth 2 -name META -mmin "-$reuse" 2>/dev/null | head -1)
  # solo se reutiliza un respaldo reciente que PASA la verificacion (hashes y lectura); uno interrumpido no vale
  if [ -n "$recent" ] && "$LP_SCRIPTS/backup.sh" verify "$(basename "$(dirname "$recent")")" >/dev/null 2>&1; then
    log "respaldo reciente reutilizado: $(basename "$(dirname "$recent")")"; return 0
  fi
  "$LP_SCRIPTS/backup.sh" create "pre-${1:-cambio}" >/dev/null || die "no se pudo crear el respaldo previo: NO se realizo ningun cambio"
  log "respaldo previo creado (restaurar: backup.sh list / backup.sh restore <id>)"
}
# confirm_bulk <descripcion>: operaciones masivas (--all) piden confirmacion explicita (CONFIRM=yes o escribir SI).
confirm_bulk() {
  [ "${CONFIRM:-}" = yes ] && return 0
  [ -t 0 ] || die "operacion masiva ($1): define CONFIRM=yes para confirmar que la revisaste"
  printf 'Confirmar %s? Escribe SI: ' "$1" >&2; read -r a; [ "$a" = SI ] || die "cancelado"
}

# --- Alcance probado (assets/alcance-verificado.conf). Lo no probado se niega por defecto: decide una PERSONA, no el agente.
LP_SCOPE_FILE=${LP_SCOPE_FILE:-$LP_SCRIPTS/../assets/alcance-verificado.conf}
VERIFIED_COMBOS=""; SELINUX_ENFORCING_EL_MAJOR=""; VERIFIED_DISTROS=""
# shellcheck disable=SC1090
[ -f "$LP_SCOPE_FILE" ] && . "$LP_SCOPE_FILE"
el_major() { ( . /etc/os-release 2>/dev/null; echo "${VERSION_ID:-0}" | cut -d. -f1 ); }
os_rhel_like() { ( . /etc/os-release 2>/dev/null; echo " ${ID:-} ${ID_LIKE:-} " | grep -Eq ' (rhel|centos|fedora|rocky|almalinux|ol) ' ); }
# scope_reasons <MM>: una linea por cada motivo por el que esta combinacion no esta en el alcance probado (vacio = probada)
scope_reasons() {
  local mm=$1 maj; maj=$(el_major)
  if [ ! -f "$LP_SCOPE_FILE" ] || [ -z "$VERIFIED_COMBOS" ]; then echo "falta o esta vacio el alcance declarado ($LP_SCOPE_FILE): sin alcance no se opera"; return; fi
  os_rhel_like || echo "la distribucion no es RHEL ni derivada (la estrategia B solo se probo en esa familia)"
  local did; did=$(. /etc/os-release 2>/dev/null; echo "${ID:-desconocida}")
  case " $VERIFIED_DISTROS " in *" $did "*) ;; *) echo "distribucion '$did' sin probar (probadas: ${VERIFIED_DISTROS:-ninguna}): compatibilidad inferida";; esac
  [ "$(uname -m)" = x86_64 ] || echo "arquitectura $(uname -m): solo se probo x86_64"
  case " $VERIFIED_COMBOS " in *" $maj:$mm "*) ;; *) echo "la combinacion RHEL/derivadas $maj con PHP $mm no esta en lo probado ($VERIFIED_COMBOS)";; esac
  if [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
    case " $SELINUX_ENFORCING_EL_MAJOR " in *" $maj "*) ;; *) echo "SELinux Enforcing no probado en RHEL/derivadas $maj (probado: $SELINUX_ENFORCING_EL_MAJOR)";; esac
  fi
}
# gate_scope <MM>: aborta ante una combinacion no probada. ACK_UNTESTED=yes solo lo fija una persona que ya la ensayo en prueba.
gate_scope() {
  local r l; r=$(scope_reasons "$1"); [ -n "$r" ] || return 0
  while read -r l; do log "FUERA DEL ALCANCE PROBADO: $l"; done <<< "$r"
  [ "${ACK_UNTESTED:-}" = yes ] || die "combinacion no probada: no se cambia nada. Ensayala en un ambiente de prueba (references/10) y, si una persona responsable acepta el riesgo, repite con ACK_UNTESTED=yes (references/11)"
  log "ACK_UNTESTED=yes: una persona acepto operar fuera del alcance probado"
}
# gate_auth <tarball...>: aborta si el paquete o /opt/deps declaran fuentes sin autenticar. ACCEPT_UNAUTHENTICATED=yes lo fija una persona.
gate_auth() {
  local t bad=""
  for t in "$@"; do tar -tzf "$t" 2>/dev/null | grep -q 'SOURCES-NOT-AUTHENTICATED.txt$' && bad="$bad $(basename "$t")"; done
  [ -f /opt/deps/SOURCES-NOT-AUTHENTICATED.txt ] && bad="$bad /opt/deps"
  [ -n "$bad" ] || return 0
  log "FUENTES SIN AUTENTICAR en:$bad"
  [ "${ACCEPT_UNAUTHENTICATED:-}" = yes ] || die "el codigo fuente de estas bibliotecas no se pudo autenticar contra el proyecto: no se instala. Cumple los puntos de references/02 (Autenticidad de las fuentes) y, con una excepcion de riesgo aprobada por escrito, repite con ACCEPT_UNAUTHENTICATED=yes (references/11)"
  log "ACCEPT_UNAUTHENTICATED=yes: una persona acepto instalar con fuentes sin autenticar"
}

fpm_dir() { echo "/opt/php$1/etc/php-fpm.d"; }
fpm_unit() { echo "php$1-fpm"; }
fpm_test() { /opt/php$1/sbin/php-fpm -t --fpm-config /opt/php$1/etc/php-fpm.conf -c /opt/php$1/etc/php.ini; }

# Recarga o arranca el FPM de la version; si ya no quedan pools lo detiene.
fpm_sync() {
  local mm=$1 u; u=$(fpm_unit "$mm")
  if ls "$(fpm_dir "$mm")"/*.conf >/dev/null 2>&1; then
    fpm_test "$mm" >/dev/null 2>&1 || return 1
    if systemctl is-active --quiet "$u"; then systemctl reload "$u" || return 1
    else systemctl start "$u" || return 1; fi
    systemctl is-enabled --quiet "$u" 2>/dev/null || systemctl enable "$u" >/dev/null 2>&1
  else
    # sin pools la unidad no arranca (php-fpm -t falla): se detiene y se deshabilita para que no quede en bucle tras un reinicio
    if systemctl is-active --quiet "$u"; then systemctl stop "$u" || return 1; fi
    systemctl is-enabled --quiet "$u" 2>/dev/null && systemctl disable "$u" >/dev/null 2>&1
  fi
  return 0
}

# port_labeled <puerto>: 0 si el puerto (o un rango que lo contiene) esta etiquetado como http_port_t
port_labeled() {
  semanage port -l 2>/dev/null | awk -v p="$1" '$1=="http_port_t" && $2=="tcp" { $1=""; $2=""; gsub(/,/," "); n=split($0,a," ");
    for (i=1;i<=n;i++) { if (a[i] ~ /^[0-9]+-[0-9]+$/) { split(a[i],r,"-"); if (p>=r[1]+0 && p<=r[2]+0) f=1 } else if (a[i]==p) f=1 } } END { exit f?0:1 }'
}

# Con SELinux Enforcing, httpd_t solo puede conectarse al pool (puerto http_port_t) si esta activo httpd_can_network_relay
# (o el mas amplio httpd_can_network_connect). Sin eso proxy_fcgi da 503 (probado en Rocky 9). No se cambia nada aqui.
selinux_proxy_ok() {
  [ "$(getenforce 2>/dev/null)" = Enforcing ] || return 0
  command -v getsebool >/dev/null || return 0
  getsebool httpd_can_network_relay 2>/dev/null | grep -q -- '--> on' && return 0
  getsebool httpd_can_network_connect 2>/dev/null | grep -q -- '--> on' && return 0
  return 1
}
SELINUX_PROXY_MSG="SELinux Enforcing: httpd no puede conectarse al pool (503). Con autorizacion: setsebool -P httpd_can_network_relay on (references/05-selinux.md); para deshacer: setsebool -P httpd_can_network_relay off"

apache_check_reload() {
  $HTTPD_BIN -t >/dev/null 2>&1 || { $HTTPD_BIN -t 2>&1 | tail -5 >&2; return 1; }
  # Con systemd, recargar por la unidad: en las pruebas, "httpd -k graceful" lanzado a mano dejo la unidad en failed mientras Apache seguia sirviendo
  # (probado en Rocky 9: la unidad pasa a "failed" aunque Apache siga sirviendo).
  local unit=${HTTPD_UNIT:-httpd}
  if [ -d /run/systemd/system ] && systemctl is-active --quiet "$unit" 2>/dev/null; then
    systemctl reload "$unit" || { echo "ERROR: systemctl reload $unit fallo" >&2; return 1; }
  else
    $HTTPD_BIN -k graceful || { echo "ERROR: $HTTPD_BIN -k graceful fallo" >&2; return 1; }
  fi
  # comprobar que Apache sigue arriba (un Listen que no se puede abrir lo detiene al recargar)
  sleep 1
  if ! pgrep -x "$(basename "$HTTPD_BIN")" >/dev/null 2>&1 && ! pgrep -x apache2 >/dev/null 2>&1; then
    echo "ERROR: no hay procesos de Apache despues de recargar; revisar el log de errores" >&2
    return 1
  fi
  if [ -d /run/systemd/system ] && ! systemctl is-active --quiet "$unit" 2>/dev/null; then
    echo "ERROR: Apache no esta activo despues de recargar; revisar: journalctl -u $unit -n 20" >&2
    return 1
  fi
  return 0
}

render() { # render <archivo> <MM>  -> stdout (cambia el marcador @MM@ por la version)
  # Si ese PHP se compilo sin ext/soap, omite php_admin_value[soap.wsdl_cache_dir]: FPM registra un ERROR por cada
  # hijo que levanta ("Unable to set php_admin_value") y ese ruido tapa los errores reales (visto en la prueba de carga).
  if [ -x "/opt/php$2/bin/php" ] && ! "/opt/php$2/bin/php" -m 2>/dev/null | grep -qix soap; then
    sed -e "s/@MM@/$2/g" -e '/soap\.wsdl_cache_dir/d' "$1"
  else
    sed -e "s/@MM@/$2/g" "$1"
  fi
}

# Codigo HTTP de un sitio contra el propio Apache, sin DNS ni balanceador.
# probe <host> [path] [scheme]
probe() {
  local host=$1 path=${2:-/} scheme=${3:-https} port=443 code
  [ "$scheme" = http ] && port=80
  code=$(curl -sk --noproxy '*' -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-60}" \
    --resolve "$host:$port:127.0.0.1" "$scheme://$host$path" 2>/dev/null) || true
  [[ "$code" =~ ^[0-9]{3}$ ]] || code=000
  echo "$code"
}

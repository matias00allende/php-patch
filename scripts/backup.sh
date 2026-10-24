#!/bin/bash
# backup.sh - respaldo y restauracion de la CONFIGURACION que esta skill puede tocar.
# Uso (como root):
#   backup.sh create [etiqueta]        crea un respaldo. Solo copia: no modifica el sistema.
#   backup.sh list                     lista los respaldos
#   backup.sh verify <id>              comprueba hashes y que el archivo se pueda leer
#   backup.sh restore <id>             SIMULA: muestra que cambiaria al restaurar (no toca nada)
#   backup.sh restore <id> --apply     restaura. Antes crea un respaldo "pre-restore" del estado actual.
#
# Incluye: configuracion de Apache, php.ini y php.d del sistema, definiciones y estado de php-patch, unidades
#   systemd y wrappers de PHP parchado, /opt/phpNN/etc, crontabs, listado de paquetes, estado de SELinux y salida de httpd -S.
# NO incluye: el codigo de los sitios, las bases de datos ni los binarios de /opt/phpNN. Respaldalos aparte. Con
#   BACKUP_DOCROOTS=1 agrega los DocumentRoot detectados (comprueba antes el espacio libre; puede ser grande).
# Variables: BACKUP_DIR (por defecto /var/backups/php-patch, modo 700: puede contener secretos de configuracion).
#
# Limites (leer): la restauracion devuelve ARCHIVOS DE CONFIGURACION; no deshace cambios de paquetes (ver pkg-upgrade-plan.sh),
#   de datos ni de SELinux ya aplicados con semanage/setsebool (el respaldo guarda su estado en facts/ para revertirlos a mano).
LP_ALLOW_NON_RHEL=1
source "$(dirname "$0")/lib.sh"
need_root
umask 077
BK_ROOT=${BACKUP_DIR:-/var/backups/$LP_NAME}

if [ -d /etc/httpd ]; then AETC=/etc/httpd; elif [ -d /etc/apache2 ]; then AETC=/etc/apache2; else AETC=""; fi

# rutas candidatas (relativas a /); solo se respaldan las que existen
candidates() {
  [ -n "$AETC" ] && echo "${AETC#/}"
  for p in etc/php.ini etc/php.d etc/php etc/php-patch etc/cron.d etc/crontab var/spool/cron \
           etc/logrotate.d/php-fpm; do echo "$p"; done
  for p in /etc/systemd/system/php[0-9][0-9]-fpm.service /etc/logrotate.d/php[0-9][0-9]-fpm /usr/local/bin/php[0-9][0-9] /opt/php[0-9][0-9]/etc; do
    [ -e "$p" ] && echo "${p#/}"
  done
}
existing() { candidates | sort -u | while read -r p; do [ -e "/$p" ] && echo "$p"; done; }

docroots() {
  [ -n "$AETC" ] || return 0
  grep -rhE '^[[:space:]]*DocumentRoot' "$AETC" 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u | while read -r d; do [ -d "$d" ] && echo "$d"; done
}

# apa <args>: httpd/apache2ctl; en SUSE "httpd -M/-S" a secas no ven los modulos que arma start_apache2, apachectl si
apa() {
  if [ -x /usr/sbin/start_apache2 ] && command -v apachectl >/dev/null 2>&1; then apachectl "$@"
  else $HTTPD_BIN "$@" 2>&1 || apache2ctl "$@" 2>&1; fi
}

avail_kb() { df -Pk "$1" | awk 'NR==2{print $4}'; }

do_create() {
  local label=${1:-manual} id dir paths need have tarx=""
  label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9_.-' '-' | cut -c1-40); [ -n "$label" ] || label=manual
  id=$(date +%Y%m%d-%H%M%S)-$label; dir=$BK_ROOT/$id
  mkdir -p "$BK_ROOT"; chmod 700 "$BK_ROOT"
  [ ! -e "$dir" ] || die "ya existe el respaldo $id (reintentar en un segundo)"
  paths=$(existing)
  [ -n "$paths" ] || die "no encontre configuracion que respaldar"
  need=$(cd / && du -sk $paths 2>/dev/null | awk '{s+=$1} END{print s*3+51200}')
  have=$(avail_kb "$BK_ROOT")
  [ "${have:-0}" -gt "${need:-0}" ] || die "espacio insuficiente para el respaldo en $BK_ROOT (necesito ~${need} KB, hay ${have} KB). No se realizan cambios"
  mkdir -p "$dir/facts" || die "no pude crear $dir"
  tar --help 2>/dev/null | grep -q -- '--selinux' && tarx="--selinux --xattrs"
  # shellcheck disable=SC2086
  ( cd / && tar -czpf "$dir/config.tar.gz" $tarx $paths ) 2>"$dir/tar.err" || { cat "$dir/tar.err" >&2; die "fallo la copia de la configuracion"; }
  [ -s "$dir/tar.err" ] || rm -f "$dir/tar.err"
  if [ "${BACKUP_DOCROOTS:-0}" = 1 ]; then
    local dr; dr=$(docroots | tr '\n' ' ')
    if [ -n "$dr" ]; then
      need=$(du -sk $dr 2>/dev/null | awk '{s+=$1} END{print s}'); have=$(avail_kb "$BK_ROOT")
      [ "${have:-0}" -gt $(( ${need:-0} * 11 / 10 + 51200 )) ] || die "espacio insuficiente para respaldar los docroots (~${need} KB). Respaldalos por otro medio y reintenta sin BACKUP_DOCROOTS"
      # shellcheck disable=SC2086
      tar -czpf "$dir/docroots.tar.gz" $dr 2>/dev/null || die "fallo la copia de los docroots"
    fi
  fi
  {
    echo "ID=$id"; echo "FECHA=$(date '+%F %T')"; echo "HOST=$(hostname)"; echo "ETIQUETA=$label"
    echo "APACHE_ETC=${AETC:-ninguno}"; echo "RUTAS=$(echo $paths)"
  } > "$dir/META"
  {
    echo "== uname"; uname -a; echo "== os-release"; cat /etc/os-release 2>/dev/null
    echo "== SELinux"; getenforce 2>/dev/null
    echo "== booleanos relacionados"; getsebool -a 2>/dev/null | grep -E 'httpd_(can_network|execmem|unified|enable)'
    command -v semanage >/dev/null && { echo "== semanage port (http)"; semanage port -l 2>/dev/null | grep -E '^http_port_t'; echo "== semanage fcontext (cambios locales)"; semanage fcontext -l -C 2>/dev/null; }
    echo "== PHP del sistema"; php -v 2>/dev/null | head -2
    echo "== paquetes php/apache"
    if command -v rpm >/dev/null; then rpm -qa 2>/dev/null | grep -Ei '^(php|httpd|apache2|mod_php)' | sort
    elif command -v dpkg >/dev/null; then dpkg -l 2>/dev/null | awk '/^ii/ && /(php|apache2)/{print $2"="$3}'; fi
    echo "== Apache -S"; apa -S | head -60
    echo "== modulos de Apache"; apa -M | head -80
    echo "== unidades php"; systemctl list-unit-files 'php*' 2>/dev/null
    echo "== puertos en escucha"; ss -tln 2>/dev/null
  } > "$dir/facts/estado.txt" 2>&1
  ( cd "$dir" && sha256sum config.tar.gz META facts/estado.txt $( [ -f docroots.tar.gz ] && echo docroots.tar.gz ) > SHA256SUMS )
  tar -tzf "$dir/config.tar.gz" >/dev/null 2>&1 || die "el respaldo recien creado no se puede leer"
  chmod -R go-rwx "$dir"
  log "RESPALDO creado: $id ($(du -sk "$dir" | cut -f1) KB) en $BK_ROOT"
  echo "$id"
}

bk_dir() { [ -n "${1:-}" ] || die "indicar el id (backup.sh list)"; [[ "$1" =~ ^[A-Za-z0-9._-]+$ && "$1" != *..* ]] || die "id de respaldo invalido: $1"; [ -d "$BK_ROOT/$1" ] || die "no existe el respaldo $1 en $BK_ROOT"; echo "$BK_ROOT/$1"; }

do_verify() {
  local d; d=$(bk_dir "${1:-}")
  ( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) || die "los hashes del respaldo $1 NO coinciden: no lo uses sin revisarlo"
  tar -tzf "$d/config.tar.gz" >/dev/null 2>&1 || die "no se puede leer config.tar.gz de $1"
  log "respaldo $1 verificado"
}

do_list() {
  [ -d "$BK_ROOT" ] || { echo "sin respaldos"; return 0; }
  for d in "$BK_ROOT"/*/; do [ -f "$d/META" ] && printf '%s  %s KB  %s\n' "$(basename "$d")" "$(du -sk "$d" | cut -f1)" "$(sed -n 's/^FECHA=//p' "$d/META")"; done
}

do_restore() {
  local id=${1:-} apply=0 d p ts pre n=0
  [ "${2:-}" = --apply ] && apply=1
  d=$(bk_dir "$id"); do_verify "$id"
  tmp=$(mktemp -d); trap 'rm -r "${tmp:-/nonexistent}" 2>/dev/null' EXIT
  tar -xzpf "$d/config.tar.gz" --selinux --xattrs -C "$tmp" || die "no pude extraer el respaldo"
  echo "== diferencias entre el respaldo $id y el sistema actual (solo configuracion)"
  for p in $(sed -n 's/^RUTAS=//p' "$d/META"); do
    [ -e "$tmp/$p" ] || continue
    if [ -d "$tmp/$p" ]; then diff -rq --no-dereference "$tmp/$p" "/$p" 2>/dev/null | sed "s#$tmp##" | head -40
    else cmp -s "$tmp/$p" "/$p" || echo "difiere: /$p"; fi
  done
  if [ $apply = 0 ]; then
    echo "SIMULACION: no se cambio nada. Para restaurar: backup.sh restore $id --apply"
    return 0
  fi
  [ "${RESTORE_CONFIRM:-}" = yes ] || [ -t 0 ] || die "restauracion no interactiva: define RESTORE_CONFIRM=yes para confirmar que revisaste la simulacion"
  if [ -t 0 ] && [ "${RESTORE_CONFIRM:-}" != yes ]; then
    printf 'Restaurar la configuracion del respaldo %s? Se hara antes un respaldo del estado actual. Escribe SI: ' "$id"; read -r a; [ "$a" = SI ] || die "cancelado"
  fi
  ts=$(date +%Y%m%d%H%M%S)
  pre=$(do_create "pre-restore-$id") || die "no pude crear el respaldo previo a la restauracion; no se cambia nada"
  log "estado actual guardado como $pre (si la restauracion no te sirve: backup.sh restore $pre --apply)"
  # si algo falla a mitad, se vuelve solo al estado guardado (la reversion no se encadena: RESTORE_NOAUTO)
  auto_back() {
    [ "${RESTORE_NOAUTO:-}" = 1 ] && return 1
    log "REVIRTIENDO la restauracion fallida: se vuelve al estado guardado $pre"
    RESTORE_NOAUTO=1 RESTORE_CONFIRM=yes bash "$LP_SCRIPTS/backup.sh" restore "$pre" --apply </dev/null && log "se volvio al estado previo ($pre)" || log "ERROR: la reversion automatica tambien fallo; el estado previo esta en $pre: restaurarlo a mano"
  }
  trap 'log "interrumpido"; auto_back; rm -r "${tmp:-/nonexistent}" 2>/dev/null; exit 1' INT TERM HUP
  for p in $(sed -n 's/^RUTAS=//p' "$d/META"); do
    [ -e "$tmp/$p" ] || continue
    if [ -d "$tmp/$p" ]; then ( umask 022; mkdir -p "/$p" ); cp -a "$tmp/$p/." "/$p/" || { auto_back; die "fallo al restaurar /$p"; }
    else cp -a "$tmp/$p" "/$p" || { auto_back; die "fallo al restaurar /$p"; }; fi
  done
  # directorios donde el estado exacto importa: lo que no estaba en el respaldo se aparta (no se borra)
  for dd in "${APA_ACTIVE#/}" "${STATE#/}" "${APA_BASE#/}/shadow"; do
    [ -d "/$dd" ] || continue
    for f in /$dd/*; do
      [ -e "$f" ] || continue
      [ -e "$tmp/$dd/$(basename "$f")" ] && continue
      mkdir -p "/$dd.after-restore.$ts"; mv "$f" "/$dd.after-restore.$ts/" && n=$((n+1)) && log "apartado (no estaba en el respaldo): $f"
    done
  done
  for dd in /opt/php[0-9][0-9]/etc/php-fpm.d; do
    [ -d "$dd" ] || continue
    for f in "$dd"/*.conf; do
      [ -e "$f" ] || continue
      [ -e "$tmp/${f#/}" ] && continue
      mkdir -p "$dd.after-restore.$ts"; mv "$f" "$dd.after-restore.$ts/" && n=$((n+1)) && log "pool apartado (no estaba en el respaldo): $f"
    done
  done
  # solo las rutas que se restauraron (no todo /etc ni /opt, que pueden tener etiquetas manuales de otros servicios)
  if command -v restorecon >/dev/null; then for p in $(sed -n 's/^RUTAS=//p' "$d/META"); do [ -e "/$p" ] && restorecon -R "/$p" 2>/dev/null; done; fi
  systemctl daemon-reload 2>/dev/null
  bad=0
  for u in /opt/php[0-9][0-9]; do
    [ -d "$u" ] || continue
    fpm_sync "${u#/opt/php}" || { log "AVISO: php${u#/opt/php}-fpm no quedo en el estado esperado tras restaurar"; bad=1; }
  done
  if $HTTPD_BIN -t >/dev/null 2>&1 || apache2ctl -t >/dev/null 2>&1; then apache_check_reload || { log "AVISO: Apache no recargo; revisar a mano"; bad=1; }
  else log "AVISO: el configtest de Apache falla tras restaurar"; auto_back; exit 1; fi
  if [ "$bad" = 1 ]; then log "la restauracion desde $id dejo avisos"; auto_back; exit 1; fi
  trap - INT TERM HUP
  log "RESTAURADO desde $id ($n elementos apartados). Verifica los sitios con baseline.sh compare"
}

case ${1:-} in
  create)  do_create "${2:-manual}";;
  list)    do_list;;
  verify)  do_verify "${2:-}";;
  restore) do_restore "${2:-}" "${3:-}";;
  *) sed -n 2,12p "$0"; exit 2;;
esac

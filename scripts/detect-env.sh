#!/bin/bash
# detect-env.sh - SOLO LECTURA. Detecta distribucion, gestor de paquetes, servidor web, SAPI de PHP y controles
# de seguridad, y sugiere la estrategia (A: paquetes, B: compilar al lado, C: solo mitigar). La sugerencia es un
# punto de partida: se confirma con references/00-decidir-estrategia.md y con el administrador.
# Uso: [sudo] ./detect-env.sh        (sin sudo funciona; con sudo ve mas del servidor web)
export LC_ALL=C
kv() { printf '%-18s %s\n' "$1" "$2"; }
. /etc/os-release 2>/dev/null
id=${ID:-unknown}; ver=${VERSION_ID:-}; major=${ver%%.*}
case "$id" in
  rhel|centos|rocky|almalinux|ol|fedora|scientific) family=rhel;;
  amzn) family=amazon;;
  ubuntu|debian|linuxmint|raspbian) family=debian;;
  sles|sled|opensuse*|suse) family=suse;;
  alpine) family=alpine;;
  *) family=unknown;;
esac
[ -z "$ver" ] && [ -f /etc/redhat-release ] && ver=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1) && major=${ver%%.*}
pm=none; for c in dnf yum apt-get zypper apk; do command -v $c >/dev/null && { pm=$c; break; }; done
echo "== entorno $(hostname) $(date '+%F %T')"
kv distribucion "${PRETTY_NAME:-$(cat /etc/redhat-release 2>/dev/null)}"
kv id/familia "$id / $family (version $ver)"
kv arquitectura "$(uname -m)"
kv kernel "$(uname -r)"
kv gestor_paquetes "$pm"
kv systemd "$([ -d /run/systemd/system ] && echo si || echo no)"
kv contenedor "$([ -f /.dockerenv ] || grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null && echo posible || echo no)"
# --- servidor web
web=ninguno; wbin=""
for c in httpd apache2 nginx; do command -v $c >/dev/null 2>&1 && { web=$c; wbin=$(command -v $c); break; }; done
kv servidor_web "$web $( [ -n "$wbin" ] && ($wbin -v 2>&1 | head -1) )"
sapi=desconocido
if [ "$web" = httpd ] || [ "$web" = apache2 ]; then
  # SUSE: start_apache2 arma los modulos (php, proxy_fcgi...) desde /etc/sysconfig/apache2; "httpd -M" a secas no los ve, "apachectl -M" si
  if [ -x /usr/sbin/start_apache2 ] && command -v apachectl >/dev/null 2>&1; then mods=$(apachectl -M 2>/dev/null)
  else mods=$( (httpd -M || apache2ctl -M || apachectl -M) 2>/dev/null ); fi
  echo "$mods" | grep -qi 'php' && sapi="mod_php"
  echo "$mods" | grep -qE 'mpm_event|mpm_worker' && mpm=event/worker; echo "$mods" | grep -q mpm_prefork && mpm=prefork
  kv mpm "${mpm:-?}"
  kv proxy_fcgi "$(echo "$mods" | grep -q proxy_fcgi && echo cargado || echo NO)"
fi
if ss -xl 2>/dev/null | grep -q 'php.*fpm' || pgrep -x php-fpm >/dev/null 2>&1 || pgrep -f 'php-fpm: master' >/dev/null 2>&1; then
  [ "$sapi" = mod_php ] && sapi="mod_php + php-fpm" || sapi="php-fpm"
fi
kv sapi_php "$sapi"
# --- PHP
phpv=$(php -v 2>/dev/null | head -1); kv php_cli "${phpv:-no encontrado}"
case "$pm" in
  yum|dnf) pk=$(rpm -qa 2>/dev/null | grep -iE '^(php|remi|scl)' | sort | head -8 | tr '\n' ' ');;
  apt-get) pk=$(dpkg -l 2>/dev/null | awk '/^ii +(php|libapache2-mod-php)/{print $2"="$3}' | head -8 | tr '\n' ' ');;
  zypper) pk=$(rpm -qa 2>/dev/null | grep -i '^php' | head -8 | tr '\n' ' ');;
  *) pk="";;
esac
kv paquetes_php "${pk:-ninguno}"
ls -d /opt/php[0-9][0-9] /opt/remi* /opt/rh/*php* 2>/dev/null | tr '\n' ' ' | sed 's/^/    ya_instalado_aparte: /'; echo
# --- controles
kv selinux "$(getenforce 2>/dev/null || echo no-instalado)"
kv apparmor "$(command -v aa-status >/dev/null && (aa-status --enabled 2>/dev/null && echo activo || echo inactivo) || echo no-instalado)"
kv firewall "$(systemctl is-active firewalld 2>/dev/null || true) $(command -v ufw >/dev/null && ufw status 2>/dev/null | head -1)"
kv ram_mb "$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
kv libre_opt_gb "$(df -Pk /opt 2>/dev/null | awk 'NR==2{printf "%.1f",$4/1048576}')"
# --- sugerencia de estrategia (a confirmar)
echo; echo "== sugerencia (Inferido; confirmar con references/00-decidir-estrategia.md)"
eol=""
case "$family:$major" in
  rhel:6|rhel:7) eol="el sistema esta sin actualizaciones estandar (EL7: fin de mantenimiento 2024-06-30; verificar si hay soporte extendido contratado)";;
  amazon:1|amazon:2018) eol="Amazon Linux 1 esta sin soporte";;
  debian:*) case "$id:$major" in ubuntu:1[0-8]|ubuntu:[0-9]|debian:[0-9]|debian:10) eol="version sin soporte estandar (confirmar fecha con el proveedor)";; esac;;
esac
[ -n "$eol" ] && echo "  EOL: $eol"
if [ "$(uname -m)" != x86_64 ]; then
  echo "  Los paquetes precompilados de esta skill son x86_64. Esta arquitectura exige compilar en un laboratorio equivalente."
fi
case "$family:$major" in
  rhel:6|rhel:7|amazon:1|amazon:2018|amazon:2)
    echo "  B) COMPILAR AL LADO (scripts/ + build/). Antes, verificar que ningun repositorio mantenido publica la version corregida."
    echo "     En Amazon Linux 2 revisar primero si hay paquetes PHP de amazon-linux-extras que ya incluyan la correccion.";;
  rhel:*|amazon:*|debian:*|suse:*)
    echo "  A) PAQUETES. Ver scripts/pkg-upgrade-plan.sh (solo lectura: muestra version instalada, candidata y los comandos propuestos)."
    echo "     Si el repositorio aun no publica la version corregida: C) mitigar y esperar, o B) compilar al lado (en Debian/Ubuntu/SUSE la estrategia B no esta implementada en los scripts: seria una adaptacion manual).";;
  *) echo "  Distribucion no reconocida: usar references/00 y decidir con el administrador.";;
esac
[ "$web" = nginx ] && echo "  Servidor web nginx: los scripts de activacion son para Apache; adaptar site.conf.tpl a fastcgi_pass (references/00)."
[ "$web" = ninguno ] && echo "  Sin servidor web detectado: puede ser un servidor solo CLI/cron o un contenedor."
[ "$(getenforce 2>/dev/null)" = Enforcing ] && echo "  SELinux Enforcing: leer references/05-selinux.md ANTES de activar sitios."

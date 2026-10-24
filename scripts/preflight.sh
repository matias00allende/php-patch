#!/bin/bash
# preflight.sh - SOLO LECTURA. Verifica que el servidor esta listo para instalar PHP parchado en paralelo.
# Uso: sudo ./preflight.sh
# Sale con codigo 1 si alguna comprobacion obligatoria falla. Las advertencias no bloquean.
source "$(dirname "$0")/lib.sh"
fail=0; warn=0
chk()  { if eval "$2" >/dev/null 2>&1; then echo "OK     $1"; else echo "FALLA  $1"; fail=$((fail+1)); fi; }
wchk() { if eval "$2" >/dev/null 2>&1; then echo "OK     $1"; else echo "AVISO  $1"; warn=$((warn+1)); fi; }
echo "== preflight $(hostname) $(date '+%F %T')"
wchk "familia RHEL/CentOS 7 (los paquetes se compilan para EL7)" "grep -q 'release 7' /etc/redhat-release"
chk  "x86_64" "[ \"\$(uname -m)\" = x86_64 ]"
chk  "systemd" "[ -d /run/systemd/system ]"
chk  "Apache 2.4" "$HTTPD_BIN -v | grep -q 'Apache/2.4'"
chk  "proxy_module cargado" "$HTTPD_BIN -M 2>/dev/null | grep -q ' proxy_module'"
chk  "proxy_fcgi_module cargado" "$HTTPD_BIN -M 2>/dev/null | grep -q proxy_fcgi_module"
chk  "usuario del servidor web ($WEB_USER)" "id $WEB_USER"
chk  "configtest de Apache limpio" "$HTTPD_BIN -t"
chk  "espacio libre en /opt >= 3 GB" "[ \$(df -Pk /opt | awk 'NR==2{print \$4}') -gt 3145728 ]"
chk  "memoria disponible >= 512 MB" "[ \$(awk '/MemAvailable/{print \$2}' /proc/meminfo) -gt 524288 ]"
for l in libldap libgmp libxslt libbz2 libpng1 libjpeg libfreetype libreadline libtinfo libncurses libssl libcrypto; do
  wchk "libreria del sistema $l (si falta: instalar con yum o apt; ver references/04)" "ldconfig -p | grep -Eq \"^[[:space:]]+$l\""
done
echo "== SELinux: $(getenforce 2>/dev/null || echo no-instalado)"
if [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
  wchk "semanage disponible (policycoreutils-python)" "command -v semanage"
  wchk "httpd puede conectarse al pool (booleano httpd_can_network_relay; se activa con autorizacion, references/05)" "selinux_proxy_ok"
  echo "   Enforcing: antes de activar el primer sitio hay que etiquetar los puertos $PORT_MIN-$PORT_MAX (references/05)."
fi
echo "== Alcance probado (assets/alcance-verificado.conf): $VERIFIED_COMBOS | SELinux Enforcing en RHEL $SELINUX_ENFORCING_EL_MAJOR | este servidor: RHEL/derivadas $(el_major)"
for mm in ${CHECK_MM:-$(for c in $VERIFIED_COMBOS; do [ "${c%%:*}" = "$(el_major)" ] && echo "${c#*:}"; done)}; do
  r=$(scope_reasons "$mm")
  if [ -z "$r" ]; then echo "OK     PHP $mm en este servidor: combinacion probada"
  else echo "$r" | sed 's/^/AVISO  FUERA DE LO PROBADO: /'; warn=$((warn+1)); echo "       install-package.sh y activate-site.sh se negaran sin ACK_UNTESTED=yes (references/11). Para evaluar otra version: CHECK_MM=86 preflight.sh"; fi
done
[ -n "$(for c in $VERIFIED_COMBOS; do [ "${c%%:*}" = "$(el_major)" ] && echo x; done)" ] || { echo "AVISO  FUERA DE LO PROBADO: ninguna version de PHP esta probada en RHEL/derivadas $(el_major)"; warn=$((warn+1)); }
echo "== PHP vigente (no se toca): $(php -v 2>/dev/null | head -1) | modulos Apache: $($HTTPD_BIN -M 2>/dev/null | grep -E 'php' | tr -s ' ' | tr '\n' ' ')"
echo "== puertos $PORT_MIN-$PORT_MAX en uso:"; ss -tln | awk '{print $4}' | grep -E ":(9[4-9][0-9][0-9])\$" || echo "ninguno"
echo "== instalado: $(ls -d /opt/php[0-9][0-9] 2>/dev/null | tr '\n' ' ')"
if [ "$fail" = 0 ]; then echo "RESULTADO: LISTO ($warn avisos)"; else echo "RESULTADO: $fail comprobaciones fallidas ($warn avisos)"; exit 1; fi

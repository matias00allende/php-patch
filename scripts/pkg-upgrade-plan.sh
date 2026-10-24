#!/bin/bash
# pkg-upgrade-plan.sh - SOLO LECTURA. Para la estrategia A (actualizar paquetes del repositorio): muestra la version
# instalada, la candidata, el origen, y IMPRIME los comandos propuestos para respaldo, actualizacion y rollback.
# No instala ni modifica nada (no ejecuta apt-get install/yum update). La persona o el agente los ejecuta despues,
# uno por uno, con autorizacion.
# Uso: [sudo] ./pkg-upgrade-plan.sh [rama]      rama = 8.4, 8.3, 7.4 ... (por defecto la del php instalado)
export LC_ALL=C
branch=${1:-$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)}
[ -n "$branch" ] || { echo "no pude determinar la rama de PHP; indicala como argumento"; exit 2; }
echo "== rama $branch en $(hostname) $(date '+%F %T')"
echo "Version corregida: tomarla de php.net/ChangeLog (primera de la rama que cierra la CVE). OJO: RHEL, Ubuntu y Debian suelen aplicar BACKPORTS sin subir al numero upstream; confirma tambien el aviso de seguridad del proveedor y la version completa del paquete (revision/release) para tu CVE."
if command -v apt-get >/dev/null; then
  echo "== instalados"; dpkg -l | awk -v b="$branch" '/^ii +(php|libapache2-mod-php)/ && $2 ~ b {print $2, $3}'
  echo "== candidata y origen"; for p in php$branch libapache2-mod-php$branch php$branch-fpm php$branch-cli; do apt-cache policy $p 2>/dev/null | sed -n '1p;2,3p'; done
  echo "== .deb anteriores disponibles para rollback (cache de apt)"; ls /var/cache/apt/archives 2>/dev/null | grep -E "php$branch|mod-php$branch" | head -20
  cat <<EOF
== comandos propuestos (NO ejecutados)
  1) respaldo:   sudo scripts/backup.sh create antes-de-paquetes   (configuracion, vhosts, paquetes; restaurar: backup.sh restore <id>)
                 respalda aparte el codigo y las bases de datos de los sitios (backup.sh NO los incluye)
                 dpkg -l | grep -E 'php|mod-php' > /root/php-paquetes-antes.txt
                 (si faltan los .deb viejos: apt-get download <paquete>=<version> o dpkg-repack <paquete>)
  2) simulacion: apt-get -s install --only-upgrade 'php$branch*' libapache2-mod-php$branch     (revisar que SOLO suba PHP)
  3) aplicar:    apt-get install --only-upgrade 'php$branch*' libapache2-mod-php$branch
  4) verificar:  php -v && apache2ctl configtest && systemctl restart apache2     (si usas FPM, reinicia tambien php<X.Y>-fpm)
                 luego: scripts/baseline.sh compare ANTES.tsv ; comprueba la version SERVIDA con una pagina de diagnostico temporal protegida (php -v es el CLI)
  5) rollback:   dpkg -i /ruta/a/los/.deb/anteriores ; systemctl restart apache2
EOF
elif { command -v dnf >/dev/null || command -v yum >/dev/null; } && ! grep -qiE "suse" /etc/os-release 2>/dev/null; then   # SUSE usa zypper aunque tenga dnf instalado
  pm=$(command -v dnf || command -v yum)
  echo "== instalados"; rpm -qa | grep -iE '^php' | sort
  echo "== repositorios que ofrecen PHP"; $pm repolist 2>/dev/null | head -20
  echo "== versiones disponibles"; $pm list --showduplicates available 'php*' 2>/dev/null | head -30
  command -v dnf >/dev/null && { echo "== modulos"; dnf module list php 2>/dev/null | head -20; }
  cat <<EOF
== comandos propuestos (NO ejecutados)
  1) respaldo:   sudo scripts/backup.sh create antes-de-paquetes   (configuracion, vhosts, paquetes; restaurar: backup.sh restore <id>)
                 respalda aparte el codigo y las bases de datos de los sitios (backup.sh NO los incluye)
                 rpm -qa | grep -i php > /root/php-paquetes-antes.txt ; $pm history list | head
  2) simulacion: $pm update --assumeno 'php*'    (o $pm --setopt=tsflags=test update 'php*')  -> revisar que SOLO suba PHP
  3) aplicar:    $pm update 'php*'
  4) verificar:  php -v && httpd -t && systemctl restart httpd     (si usas FPM, reinicia tambien php-fpm)
                 luego: scripts/baseline.sh compare ANTES.tsv ; comprueba la version SERVIDA con una pagina de diagnostico temporal protegida (php -v es el CLI)
  5) rollback:   $pm history undo <id>    (el id sale de '$pm history list') ; systemctl restart httpd
                 OJO: undo/downgrade necesitan que los RPM anteriores sigan en el repositorio. Antes de aplicar, descargalos: $pm downgrade --downloadonly o yumdownloader <paquete>-<version> y guardalos junto al respaldo.
  Con modulos (dnf module): cambiar de rama es un cambio mayor ('dnf module switch-to php:X.Y'); tratarlo como migracion, no como parche.
EOF
elif command -v zypper >/dev/null; then
  # En SUSE el paquete lleva solo la version mayor: php7, php8 (y apache2-mod_php8, php8-fpm...); no existe un "php8.4".
  major=${branch%%.*}; pk="php$major"
  echo "== instalados"; rpm -qa | grep -E "^(php|apache2-mod_php)" | sort
  echo "== versiones disponibles de $pk y apache2-mod_$pk (S: i+ instalada, v otra version del repositorio; el repositorio solo ofrece la rama que publica SUSE, normalmente no es la rama $branch exacta)"
  zypper --non-interactive search -s -x "$pk" "apache2-mod_$pk" 2>/dev/null | grep -E '^(S |---|[a-z ]+\+? *\|)'
  echo "== origen y estado de $pk"; zypper --non-interactive info "$pk" 2>/dev/null | grep -E '^(Repository|Name|Version|Installed|Status)'
  echo "== actualizaciones pendientes de PHP (si no sale nada, el repositorio no publica una version mas nueva)"; zypper --non-interactive list-updates 2>/dev/null | grep -i php
  echo "== parches de seguridad que mencionan PHP (consultar tambien: zypper list-patches --cve=CVE-AAAA-NNNN para tu CVE)"; zypper --non-interactive list-patches 2>/dev/null | grep -i php
  cat <<EOF
== comandos propuestos (NO ejecutados)
  1) respaldo:   tar -czf /root/apache2-etc-antes.tgz /etc/apache2 /etc/php$major /etc/sysconfig/apache2 ; apachectl -S > /root/vhosts-antes.txt
                 rpm -qa | grep -E '^(php|apache2-mod_php)' > /root/php-paquetes-antes.txt
                 (si hay snapper/btrfs: snapper create -d "antes de parchear PHP")
  2) simulacion: zypper --non-interactive update --dry-run '$pk*' 'apache2-mod_$pk'     (revisar que SOLO suba PHP)
  3) aplicar:    zypper update '$pk*' 'apache2-mod_$pk'      (o, si hay un parche concreto: zypper patch --cve=CVE-AAAA-NNNN)
  4) verificar:  php -v && apachectl configtest && systemctl restart apache2      (si usas FPM, reinicia tambien php-fpm)
                 luego: scripts/baseline.sh compare ANTES.tsv ; comprueba la version SERVIDA con una pagina de diagnostico temporal protegida (php -v es el CLI)
  5) rollback:   zypper install --oldpackage $pk=<version-release anterior> apache2-mod_$pk=<version-release anterior> ; systemctl restart apache2
                 (las versiones anteriores salen de: zypper search -s -x $pk ; si ya no estan en el repositorio, usa el snapshot de snapper o los RPM guardados antes de aplicar)
EOF
else
  echo "gestor de paquetes no soportado por este script: usar references/00-decidir-estrategia.md"
fi

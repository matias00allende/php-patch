# 00 - Decidir la estrategia

Antes de compilar nada, descarta caminos más simples. Compilar PHP te hace mantenedor de un paquete; solo vale la pena cuando no hay alternativa.

Primero ejecuta `scripts/detect-env.sh`: detecta distribución, gestor de paquetes, servidor web y SAPI, y propone A, B o C. El detalle por distribución está en `08-distribuciones.md`.

## Árbol de decisión

| Situación verificada | Camino | Nota |
|---|---|---|
| Debian/Ubuntu con repositorio de PHP mantenido (distribución o PPA de terceros de confianza) | **Actualizar paquetes** (sección siguiente) | No compilar. Cambio mínimo y reversible |
| RHEL/Rocky/Alma 8 o 9, o Amazon Linux 2023 | Paquetes del proveedor o repositorio de terceros mantenido (módulos `php:remi-8.x`, etc.) | Verifica que la versión del repositorio ya incluye la corrección |
| CentOS 7, RHEL 7, Oracle Linux 7, Amazon Linux 1/2 u otro EOL **sin** repositorio que publique la versión corregida | **Esta skill** (PHP compilado en `/opt`, FPM por sitio) | El sistema sigue sin soporte: pedir plan de salida |
| Hay que cerrar el riesgo hoy y el parche tomará días | Mitigación temporal (`07-mitigacion-y-riesgo-residual.md`) y luego el camino que corresponda | La mitigación no reemplaza al parche |
| El servidor se puede reinstalar/migrar a un SO soportado en el plazo que exige el riesgo | Migrar | Es la solución de fondo; esta skill es un puente |

## Verificar antes de decidir (no inferir)

1. Versión instalada y origen del paquete: `php -v`, `rpm -qa | grep -i php` o `dpkg -l | grep php`, y en Debian/Ubuntu `apt-cache policy php8.4` para ver qué repositorio la provee.
2. Versión corregida: si el PHP viene de un paquete de la distribución, manda el aviso del proveedor y la versión completa del paquete (los backports corrigen sin cambiar la versión anunciada). Para PHP upstream, la primera de cada rama en `https://www.php.net/ChangeLog-8.php` (y la rama correspondiente) o en el aviso oficial de la CVE. Anótala con su fuente.
3. Si el repositorio del sistema ya la publica: `apt-get update && apt-cache policy <paquete>` o `yum --showduplicates list <paquete>`.
4. SAPI en uso: `mod_php` (prefork), PHP-FPM, CGI o solo CLI. Cambia dónde está la exposición y el riesgo de cada cambio.

## Variante simple: Debian/Ubuntu con repositorio mantenido

Cuando el repositorio ya trae la versión corregida y PHP corre como `mod_php`:

1. **Línea base** (solo lectura): `apache2ctl -S`, `apache2ctl -M | grep php`, `php -v`, `dpkg -l | grep -E 'php|libapache2-mod-php'`, código HTTP de cada vhost.
2. **Respaldo para volver atrás:** `ls /var/cache/apt/archives/ | grep php` (los `.deb` anteriores suelen seguir ahí); si no están, `dpkg-repack <paquete>` para reconstruirlos o `apt-get download <paquete>=<versión-actual>` si el repositorio aún la publica. Copia `/etc/php` y `/etc/apache2`.
3. **Actualizar solo los paquetes PHP:** `apt-get install --only-upgrade 'php8.4*' libapache2-mod-php8.4` (ajusta la rama). Sin `dist-upgrade` ni actualización del sistema completo.
4. **Reiniciar Apache** en la ventana acordada (`apache2ctl configtest && systemctl restart apache2`; con `mod_php` prefork el reinicio corta conexiones) y comparar código HTTP de cada vhost con la línea base.
5. **Rollback:** `dpkg -i` de los `.deb` anteriores y reinicio.

No hay pools por sitio en esta variante; si el usuario quiere aislamiento por sitio, se puede pasar a FPM con `php8.x-fpm` y `proxy_fcgi` usando los mismos conceptos de la skill.

## Cuándo NO usar esta skill

- El servidor ejecuta PHP solo por CLI/cron y no sirve web: basta reemplazar el binario invocado, sin Apache ni FPM.
- Los sitios corren bajo Nginx: los conceptos (FPM por sitio, puerto fijo, rollback por sitio) sirven, pero las plantillas de Apache no. Adapta `site.conf.tpl` a `fastcgi_pass`.
- Hay contenedores: reconstruir la imagen con la versión corregida es más simple.

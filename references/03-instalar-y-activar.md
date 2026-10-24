# 03 - Instalar, activar sitios y cerrar

Procedimiento por servidor. Se aplica con autorización y ventana. Cada paso tiene un criterio de éxito; si no se cumple, no se avanza.

## 0. Antes de empezar

- [ ] Autorización escrita (alcance: instalar / activar sitios / retirar mod_php son tres decisiones distintas) y ventana fuera de la hora punta.
- [ ] Responsable de cada sitio avisado: **las sesiones PHP guardadas en archivos dejan de ser accesibles al activar y al revertir** y los usuarios pueden tener que volver a iniciar sesión (el pool usa su propio directorio de sesiones; si el sitio guarda las sesiones fuera de archivos, verifica el handler)
- [ ] Revisados los reinicios programados de Apache (cron, logrotate) para no activar encima.
- [ ] Credenciales de operación vigentes y límites de intentos de la cuenta respetados.
- [ ] Paquetes y `SHA256SUMS` en el equipo del operador, hash comprobado.

## 1. Transferir

```bash
scp SHA256SUMS php-deps-1.tar.gz php-8.3.*-el7-opt.tar.gz  usuario@servidor:~/pp/paq/
scp -r scripts assets usuario@servidor:~/pp/
```

Solo se copian las versiones que usará ese servidor; `install-package.sh` copia lo necesario a un área privada de root en `/opt` (0700), verifica los hashes sobre esa copia, extrae allí, revisa el árbol (sin setuid ni enlaces que escapen) y lo mueve a su lugar con un rename: quien tenga escritura en el directorio de origen no puede cambiar un paquete después de verificado, y un paquete que falla no deja una instalación a medias. Verifica únicamente lo presente (CentOS 7 no tiene `sha256sum --ignore-missing`, por eso el script filtra por su cuenta). Necesita espacio libre en `/opt` para la copia.

## 2. Preflight (solo lectura) y respaldo

```bash
sudo bash ~/pp/scripts/preflight.sh      # RESULTADO: LISTO
sudo bash ~/pp/scripts/backup.sh create antes-de-fpm   # respaldo verificado de la configuración (ver "Respaldo y restauración")
sudo cp -a /etc/httpd /root/httpd.etc.antes-fpm
sudo sh -c 'httpd -S > /root/httpd-S.antes-fpm.txt 2>&1; ss -tlnp > /root/ss.antes-fpm.txt'
```

Si el preflight pide librerías (`libldap`, `libgmp`...), instálalas con `yum` (están en los repositorios base). Si el servidor tiene SELinux Enforcing, lee `05-selinux.md` **antes** de seguir: el instalador solo avisa y no cambia SELinux salvo que, con autorización, lo ejecutes con `PREPARE_SELINUX=1`; sin esa preparación `activate-site.sh` se niega.

Guarda también la **línea base de todos los vhosts**, que se compara después de cada cambio:

```bash
sudo bash ~/pp/scripts/baseline.sh save /root/antes.tsv /
```

## 3. Instalar (aditivo, sin activar)

```bash
sudo bash ~/pp/scripts/install-package.sh ~/pp/paq 83
php -v                 # sigue siendo el PHP vigente
/usr/local/bin/php83 -v
```

Criterio: el PHP vigente y todos los sitios no cambiaron; `ldd /opt/php83/sbin/php-fpm | grep 'not found'` vacío; `httpd -t` OK; `php83-fpm` detenido y deshabilitado; `active/` vacío.

Instala el `php.ini` del servidor: parte del `php.ini-production` de la versión NUEVA y traslada de forma selectiva los valores efectivos del `php.ini` actual (`date.timezone`, límites, `error_log`, `session.*`); no copies `extension_dir` ni líneas de extensiones del PHP viejo (el ABI no coincide). Guarda el original como `php.ini.base` y verifica el valor efectivo con una petición al FPM.

## 4. Definir los sitios

```bash
sudo bash ~/pp/scripts/generate-site.sh <slug> <docroot> --port auto --terminate 120 --memory 256M --upload 64M
```

Revisa a mano `pool.conf` y `site.conf` de cada sitio. Lo que importa:

- **Límites desde lo que el sitio ya usa**, no desde valores teóricos: lee su `php.ini`, `.htaccess` y `php_value` en vhost. Un `memory_limit` absurdo (decenas de GB en un servidor de 4 GB) es un hallazgo, no algo que copiar.
- **`php_value`/`php_flag` de `.htaccess` y vhost se ignoran con FPM** mientras `mod_php` siga cargado (Apache los acepta pero no llegan al pool): trasládalos al `pool.conf`. Con `mod_php` retirado darían 500.
- `max_input_time`: en las pruebas solo surtió efecto con `php_admin_value` (verifica el valor efectivo); `memory_limit` va como `php_value` si el sitio lo sube con `ini_set`.
- `user_ini.filename` vacío para no cambiar comportamiento (`.user.ini` sí se lee con FPM).
- `request_terminate_timeout` y `ProxySet timeout` (el generador lo deja 10 s mayor) deben cubrir la página más lenta legítima (reportes, exportaciones).
- Todos los pools corren con el mismo usuario (`WEB_USER`): la separación es **operativa** (límites, logs, sesiones y rollback por sitio; el maestro y la recarga son por versión de PHP, no por sitio), no un aislamiento de seguridad entre sitios. Para aislar de verdad usa un usuario y permisos de archivos distintos por sitio.
- `clear_env = no` hace que PHP reciba el entorno del servicio `phpMM-fpm` (no el de Apache, que puede diferir). Si el entorno del servicio contiene secretos, o el sitio solo necesita algunas variables, usa `clear_env = yes` y declara solo esas con `env[...]`.
- `pm = ondemand`, `max_children` bajo; mide RAM (`free -m`, procesos `php-fpm`) y sube solo si hace falta. Comportamiento medido al saturar (laboratorio Rocky 9.8, 2 vCPU, ver `references/12-resultados-de-verificacion.md`): las peticiones en exceso **hacen cola** (no hay 502/503 inmediato) y su latencia crece en proporción; si esperan más que el `ProxySet timeout` (terminate + 10 s) Apache responde **504** y el FPM igual ejecuta después las peticiones abandonadas, así que tarda en recuperarse. No apareció ningún aviso `max_children` en `php-fpm.log` con `log_level = warning`: no dependas de ese mensaje para alertar; usa la duración en el `access.log` del pool o el 504 de Apache. Dimensiona `max_children` por la latencia de la página más lenta (capacidad aproximada = hijos / segundos por petición).
- `open_basedir` queda comentado como Fase 2: se activa tras una semana sin errores.

## 5. Piloto

0. Opcional y recomendado: prueba el sitio con el PHP nuevo **sin tráfico real** con `shadow-site.sh up <slug> 83 <ServerName>` y consultas de lectura por loopback (ver `10-ambiente-de-prueba.md`); luego `shadow-site.sh down <slug>`.
1. Elige el sitio de menor riesgo. Línea base: código HTTP y una transacción real (login, consulta, subida).
2. Activa con la comprobación automática:

```bash
sudo CHECK_HOST=<dns-del-sitio> bash ~/pp/scripts/activate-site.sh <slug> 83
```

`CHECK_HOST` hace la consulta contra el propio Apache con `--resolve` (sin DNS ni balanceador). Si el sitio pasa a 5xx y antes no lo era, el script revierte solo.

3. Verifica (sección 6). Observa el tiempo acordado (mínimo 24 h para el piloto si es posible) antes de la ola.

## 6. Verificación por sitio

- [ ] `status.sh` muestra el sitio con `MM`, `PORT` y fecha, y `php83-fpm: active`.
- [ ] La página principal responde igual que la línea base y el contenido es el esperado.
- [ ] Lo atiende FPM: `tail /var/log/php83-fpm/<slug>-access.log` registra la solicitud; el SAPI es `fpm-fcgi`.
- [ ] Prueba funcional del dueño (login, consulta a BD, subida, PDF, correo, integración).
- [ ] Sin `Fatal error`/`Parse error`/`Uncaught` en `<slug>-error.log`; sin `Connection refused` hacia el puerto del pool en el log de Apache.
- [ ] Los demás sitios siguen respondiendo igual.

`Deprecated` y `Warning` son frecuentes en código legado y normalmente no bloquean (se anotan para el equipo de desarrollo), pero evalúa el mensaje, su frecuencia y el efecto funcional: un `Warning` puede ser una operación que falló. En el log de Apache aparecen como `AH01071`, que es el stderr del pool y también puede traer errores fatales: no apruebes por la etiqueta.

## 7. Olas

Un sitio por vez, según el orden de la matriz. No actives el siguiente de riesgo medio/alto hasta pasar ~30 minutos sin errores nuevos. Anota la hora de cada activación.

## 8. Rollback

```bash
sudo bash ~/pp/scripts/rollback-site.sh <slug>      # un sitio
CONFIRM=yes sudo -E bash ~/pp/scripts/rollback-site.sh --all   # emergencia (pide confirmación; sin terminal exige CONFIRM=yes)
```

Mueve el `.conf` a `off/`, recarga Apache y elimina el pool. El sitio vuelve al PHP anterior. Registra causa y hora.

### Respaldo y restauración

`install-package.sh`, `activate-site.sh` (y `change-version.sh`), `rollback-site.sh`, `shadow-site.sh up` y `uninstall.sh` llaman a `backup.sh create` antes de cambiar nada; si el respaldo no se puede crear (espacio, permisos) el script se detiene sin haber cambiado el sistema. Reutilizan un respaldo de los últimos `BACKUP_REUSE_MIN` minutos (10 por defecto) para no crear decenas en una ola de activaciones. No existe una variable para saltarse el respaldo.

```bash
sudo bash ~/pp/scripts/backup.sh list
sudo bash ~/pp/scripts/backup.sh verify <id>
sudo bash ~/pp/scripts/backup.sh restore <id>             # SIMULA: muestra las diferencias, no cambia nada
sudo bash ~/pp/scripts/backup.sh restore <id> --apply     # restaura (pide SI, o RESTORE_CONFIRM=yes sin terminal)
```

Qué incluye: configuración de Apache, `php.ini`/`php.d` del sistema, `/etc/php-patch`, unidades systemd y envoltorios de PHP parchado, `/opt/phpNN/etc`, crontabs, y en `facts/` el listado de paquetes, `httpd -S`, el estado de SELinux y los booleanos y contextos locales. Se guarda en `/var/backups/php-patch` (modo 700, puede contener secretos de configuración; `BACKUP_DIR` lo cambia) con hashes SHA256.

Qué **no** incluye: el código de los sitios y las bases de datos (respáldalos aparte; `BACKUP_DOCROOTS=1` agrega los DocumentRoot detectados si hay espacio), los binarios de `/opt/phpNN` (se reinstalan desde el paquete) ni los cambios de SELinux ya aplicados (sus valores previos quedan en `facts/estado.txt` para revertirlos a mano con autorización). Restaurar no deshace cambios de paquetes (estrategia A: usa el rollback de `pkg-upgrade-plan.sh`).

La restauración guarda antes el estado actual como un respaldo `pre-restore-<id>` (así la restauración misma se puede deshacer), y si falla a mitad o el configtest de Apache no pasa, vuelve sola a ese estado, sobrescribe los archivos de configuración del respaldo y **aparta** (no borra) a `*.after-restore.<fecha>` los sitios activos, estados y pools que no estaban en el respaldo. Después ejecuta el `configtest` de Apache y recarga. Verifica con `baseline.sh compare`. Los respaldos no se podan solos: retíralos tú cuando termine el proyecto.

## 9. Criterios de abortar

Detén la ola y revierte si: falla el hash o el preflight; falla `httpd -t` tras instalar el include (el script ya revierte); un sitio activado se desvía de su línea base sin autorización (código distinto del que tenía antes, no solo "distinto de 200": una redirección o un 401 pueden ser lo normal) o falla su prueba funcional y no se corrige en el tiempo acordado; errores 5xx persistentes o RAM saturada; eventos AVC que bloqueen el funcionamiento; cualquier efecto sobre un sitio no activado; segundo intento fallido de una cuenta con bloqueo.

## 10. Cierre: retirar mod_php y cron

Solo cuando **todos** los sitios estén en FPM, con autorización:

```bash
sudo bash ~/pp/scripts/check-modphp-retirement.sh    # RESULTADO: se puede retirar mod_php
```

Retirar = desactivar el módulo y su `php.conf` (por ejemplo, renombrar `conf.d/php.conf` y la línea `LoadModule php*_module`), `httpd -t` y `systemctl reload httpd` (con systemd; `httpd -k graceful` solo si Apache no lo gestiona una unidad), y comprobar todos los sitios de nuevo. Conserva respaldo para revertir. Después decide qué hacer con un **handler global** para sitios nuevos (o exige `activate-site.sh` para cada uno).

El **PHP de cron/CLI** sigue siendo el del sistema: inventaría los scripts que llaman a `php` y decide si pasan a `/usr/local/bin/php83`. Si el código CLI es no confiable o expone entrada externa, trátalo como el resto.

## 11. Desinstalar

```bash
sudo bash ~/pp/scripts/uninstall.sh 83      # exige que no queden pools en esa versión
```

Renombra `/opt/php83` a `/opt/php83.removed.<fecha>` (no borra). `/opt/deps` y `/etc/php-patch` quedan; su retiro es manual y con confirmación.

## 12. Documentar durante, no al final

Por servidor: versión instalada, sitios activados con hora, pruebas hechas, errores y su causa, hallazgos fuera de alcance, pendientes. Guarda `status.sh` como evidencia y revisa `/var/log/php-patch.log`.

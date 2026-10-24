# 04 - Errores conocidos y su causa

Cada fila salió de una falla real durante la implementación o la prueba. Úsala antes de improvisar.

## Instalación y paquete

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `SHA256 no coincide` al copiar solo algunas versiones | `SHA256SUMS` lista archivos que no copiaste | `install-package.sh` ya verifica solo lo presente. Si verificas a mano: `while read h f; do [ -f $f ] && echo "$h  $f"; done < SHA256SUMS \| sha256sum -c -` |
| `sha256sum: unrecognized option --ignore-missing` | CentOS 7 trae coreutils 8.22 | Filtrar la lista como arriba |
| `ldd` muestra `not found` al instalar | Faltan librerías de sistema (`libldap`, `libgmp`, `libonig`, `libzip`, `libsodium`, `libodbc`...) | `yum install` de la librería de runtime, o empaquetar con `BUNDLE_LIBS` en el laboratorio |
| `semanage: command not found` con SELinux Enforcing | Falta `policycoreutils-python` | `yum install policycoreutils-python` y etiquetar puertos (`05-selinux.md`); no se activa nada antes |
| `yum` no resuelve en el laboratorio CentOS 7 | Repositorios movidos | Apuntar a `vault.centos.org` (`02-compilar-paquete.md`) |
| libxml2 desde un tag de git no genera `configure` | Falta `autoreconf`; además `PKG_CHECK_VAR` de ICU falla | Usar el tarball de release; con git: `yum install autoconf automake libtool gettext-devel` y `autoreconf -fi` |
| `Could not open config directory .../shadow` o `.../active` en `httpd -t` | `IncludeOptional` con comodín sobre un directorio que no existe falla en Apache 2.4 (solo tolera archivos que no coinciden) | Crear los directorios antes (el instalador ya lo hace) |
| `baseline.sh` no encuentra vhosts | `httpd -S` usa dos formatos: `port 80 namevhost NOMBRE` (varios vhosts por dirección) y `*:80  NOMBRE (archivo:línea)` (uno solo) | El script ya entiende ambos; si es otro formato, revisar `httpd -S` a mano |
| `configure` de `pdo_odbc` falla en 8.2/8.3 | Sintaxis distinta de la opción | `--with-pdo-odbc=unixODBC,/opt/deps` en 8.2/8.3; `unixODBC` en 8.4+ |

## Configuración del pool

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `request_slowlog_timeout can't be greater than request_terminate_timeout` y FPM no arranca | Se fijó un timeout de terminación menor que el del slowlog | `generate-site.sh` calcula el slowlog; si editas a mano, mantén slowlog <= terminate |
| `max_input_time` no cambia | En las pruebas `php_value[max_input_time]` no tuvo efecto en el pool | Usa `php_admin_value[max_input_time]` y verifica el valor efectivo con una petición al pool |
| `ini_set('memory_limit', ...)` del CMS no tiene efecto | El pool lo fijó con `php_admin_value` (bloquea `ini_set`) | `php_value[memory_limit]` si la aplicación lo sube en caliente |
| La configuración de `.htaccess` (`php_value`) "no hace nada" | Con FPM, Apache acepta la directiva pero no llega al pool | Trasladar el valor al `pool.conf` |
| Con `mod_php` retirado, 500 en sitios con `php_value` | La directiva ya no existe como comando | Revisar con `check-modphp-retirement.sh` antes de retirar |
| Cambia el comportamiento de `.user.ini` | FPM sí lo lee, `mod_php` no | `php_admin_value[user_ini.filename] =` (vacío) |
| Cabecera `Authorization` no llega a PHP | `mod_php` la exponía; con FPM no | `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1` (ya en la plantilla) |
| `PATH_INFO` vacío en URLs tipo `index.php/ruta` | Handler mal asociado | La plantilla con `SetHandler` dentro de `FilesMatch` funciona; verifica con `curl .../info.php/extra/ruta` |
| 503/504 en páginas lentas legítimas | `ProxySet timeout` o `request_terminate_timeout` menores al tiempo real | Subirlos para ese sitio; el proxy debe ser >= terminate |
| Con Enforcing, `php83-fpm` no arranca: `failed to open error_log ... Permission denied` | El directorio de logs quedó como `var_log_t`; el FPM corre como `httpd_t` | `semanage fcontext -m -t httpd_log_t "/var/log/php83-fpm(/.*)?"` y `restorecon -R` (`05-selinux.md`) |
| Con Enforcing, 503 al activar aunque el pool escuche y los puertos estén etiquetados | `httpd_t` no puede conectarse a `http_port_t` sin `httpd_can_network_relay` | Con autorización: `setsebool -P httpd_can_network_relay on` (`05-selinux.md`) |
| Apache queda en `failed` tras `shadow-site.sh up` con Enforcing | `Listen` en un puerto que no es `http_port_t` (18080): `name_bind denied` al recargar | Usar `SHADOW_PORT` con un puerto ya etiquetado (p. ej. 8008). Para recuperar: retirar la sombra, `httpd -k stop`, `systemctl start httpd` |
| La unidad `httpd` figura `failed` pero Apache sigue sirviendo | `httpd -k graceful` lanzado a mano deja a systemd sin su proceso principal | Los scripts ya recargan con `systemctl reload httpd`; si ocurre, `httpd -k stop` y `systemctl start httpd` |
| El paquete compilado para EL7 no instala en RHEL/Rocky/Alma 8 o 9: `libreadline.so.6`, `libldap-2.4.so.2`, `libpng15`... not found | Los paquetes se compilan contra los sonames de EL7 | No usar la estrategia B en EL8/9: usar paquetes del proveedor o de un repositorio mantenido (estrategia A). Incluir esas bibliotecas obliga a arrastrar OpenSSL 1.0 junto al 3 en el mismo proceso: no recomendado |
| JIT y SELinux (`httpd_execmem`) | JIT pide memoria ejecutable | `opcache.jit=disable` (ya en la plantilla) |
| Servicio no arranca por `RuntimeDirectory` / pid | Directorio de `/run` inexistente | La unidad systemd lo crea con `RuntimeDirectory`; en laboratorio sin systemd, crear `/run/phpMM-fpm` |

## Activación y verificación

| Síntoma | Causa | Qué hacer |
|---|---|---|
| El script revierte solo con "el sitio pasa a error" | El sitio dio 5xx con la nueva versión y no antes | Es el comportamiento esperado. Lee `<slug>-error.log`; típico: función eliminada en PHP 8 |
| WordPress antiguo (núcleo de 2018 o anterior) da 500 con 8.x | `get_magic_quotes_gpc()` y otras funciones eliminadas | Actualizar el CMS, retirarlo o aislarlo en PHP-FPM antiguo (vulnerable, con WAF) |
| Línea base HTTP 403 al comprobar con `CHECK_HOST` | El `Host` o la ruta no corresponden al vhost, o hay control de acceso | Usa el `ServerName` real y una ruta que responda 200/3xx con `mod_php` |
| Líneas `AH01071` en el log de Apache | Mensajes del stderr del pool: suelen ser `Deprecated`/`Warning`, pero también pueden ser errores fatales | Lee el mensaje y su efecto funcional; anota los avisos para desarrollo (p. ej. parámetro opcional antes de requerido) y trata los fatales como fallo |
| Sitio ya devolvía 500 antes de migrar | Falla preexistente (base inexistente, config) | Se descubre en la línea base; documentar para no atribuirlo a la migración |
| Usuarios cierran sesión al activar o revertir | `session.save_path` pasa a ser del pool (con sesiones en archivos) | Avisar al responsable; puede evitarse si la aplicación guarda sesiones en un almacén externo o se migra el directorio de sesiones de forma compatible |
| Un vhost con docroot dentro de otro toma el handler del padre | `<Directory>` del padre cubre el subárbol | Define el `<Directory>` del sitio más específico, o excluye el subárbol |
| Conexiones a SQL Server fallan | Falta `msodbcsql17/18` o la cadena de conexión cambió | Validar con una consulta real en el piloto; no se prueba en laboratorio |
| Salida con caracteres rotos por SSM/SSH | Locale no UTF-8 en el canal | `LC_ALL=C`, mensajes ASCII (los scripts ya lo son) y `tr -cd '\11\12\40-\176'` |

## Operación

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Apache se reinicia a horas fijas | Cron/logrotate/watchdog del servidor | Investigar la causa raíz y evitar esas horas en la ventana |
| Mucho uso de RAM tras activar decenas de sitios | `pm` estático o `max_children` alto | `pm = ondemand`, hijos bajos, revisar `pm.max_requests` |
| Cron sigue ejecutando el PHP viejo | CLI usa `/usr/bin/php` | Decidir caso a caso si pasa a `/usr/local/bin/php83` |
| `systemctl reload php83-fpm` no aplica un pool nuevo | El `.conf` no estaba en `php-fpm.d/` o `-t` falla | `php83 -v`, `fpm_test`; `activate-site.sh` ya lo valida |

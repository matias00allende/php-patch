# Resultados de las pruebas

Este documento resume qué se ejecutó, en qué entorno y con qué resultado. Es la base de `assets/alcance-verificado.conf`: lo que no aparece aquí no forma parte del alcance verificado y los scripts lo niegan o lo advierten.

Para repetir las pruebas en tu propio entorno: `scripts/lab-test.sh` (exige `LAB_CONFIRM=yes`) y `scripts/lab-reset.sh`.

## Matriz de entornos

| Entorno | Qué se ejecutó | Resultado |
|---|---|---|
| CentOS 7.9, SELinux Enforcing, systemd, Apache 2.4.6 con `mod_php` | `scripts/lab-test.sh` con PHP 8.3 y 8.4, y con 8.2 y 8.5, sin excepciones (`ACK_UNTESTED` y `ACCEPT_UNAUTHENTICATED` sin fijar) | 68 PASS, 0 FAIL en cada serie; 0 denegaciones AVC |
| CentOS 7.9, SELinux Enforcing, systemd | Recuperación tras `kill -9` al FPM, respaldo y restauración con etiquetas conservadas, `uninstall.sh` con un pool activo, reinicio completo con el sitio en 8.4, `TERM` a mitad de `activate-site.sh` | Correctos; la activación interrumpida revirtió sola |
| CentOS 7.9, sin SELinux ni systemd, Apache con `mod_php` | `scripts/lab-test.sh` con PHP 8.3 y 8.4 | 68 PASS, 0 FAIL |
| Rocky Linux 9.8, SELinux Enforcing, systemd 252, Apache 2.4.62 | Sombra, activación con reversión automática, cambio de versión 8.3/8.4, rollback, `kill -9`, respaldo y restauración, reinicio completo, PDO MySQL contra MariaDB local | Correctos; 0 AVC |
| Ubuntu 24.04, systemd | Detección, inventario, línea base y estrategia A completa (respaldo, simulación, `apt --only-upgrade`, `configtest`, reinicio, comparación); unidad `phpMM-fpm.service` con `systemd-analyze verify`, arranque, recarga y reinicio tras `kill -9` | Sin diferencias en la comparación; la unidad cumple |
| openSUSE Leap 16.0 | Detección, inventario, línea base y generación del plan de la estrategia A | Correctos |

## Compilación (`build/`)

Reconstrucción limpia, sin `ALLOW_UNPINNED`, de las ocho bibliotecas y de PHP 8.2.35, 8.3.36, 8.4.27 y 8.5.12 en CentOS 7.9 (unos 14 minutos en total). Binarios verificados: `php -v`, extensiones esperadas, `ldd` sin `not found`, y PHP-FPM respondiendo por FastCGI real con OpenSSL 3.5.9 y OPcache activo. El paquete resultante se instaló sin excepciones en el entorno CentOS 7.9 de la matriz.

Autenticidad de las fuentes (los hashes están en `build/sources.sha256`):

| Fuente | Método | Confianza |
|---|---|---|
| PHP, libxml2, OpenSSL | Hash publicado por el proyecto | Alta |
| zlib 1.3.1, ICU 64.2, curl 8.23.0 | Firma GPG del mantenedor (la clave se tomó del propio proyecto, sin cruzarla con un keyserver) | Alta |
| SQLite 3.54.1 | SHA3-256 publicado por sqlite.org (tarball `sqlite-autoconf`) | Alta |
| unixODBC 2.3.12, libzip 1.7.3 | El proyecto no publica hash ni firma; coincide con FreeBSD ports y Debian | Media |

## Comportamientos que las pruebas obligaron a corregir (ya incorporados)

- Etiqueta SELinux del directorio de logs de FPM: debe ser `httpd_log_t`.
- Con SELinux Enforcing hace falta el booleano `httpd_can_network_relay` (y `httpd_can_network_connect_db` para una base de datos). Los scripts lo comprueban, se niegan y avisan; activarlo requiere autorización.
- Un `Listen` en un puerto fuera de `http_port_t` detiene Apache: `shadow-site.sh` se niega antes de escribir.
- Recargar con `httpd -k graceful` desincroniza la unidad de systemd: se usa `systemctl reload`.
- Una unidad FPM sin pools quedaba habilitada y entraba en bucle al reiniciar: `fpm_sync` la deshabilita.
- `rollback-site.sh` sin `mod_php` cargado dejaba a Apache sirviendo el código como texto: se niega salvo `FORCE_ROLLBACK=1`.
- Archivos movidos desde `/tmp` conservaban una etiqueta SELinux equivocada: se escriben con `cat` y `restorecon`.
- `php.ini` vacío en los paquetes: `build-php.sh` ahora empaqueta `php.ini-production` y `activate-site.sh` se niega si queda el marcador vacío.
- `build-deps.sh` llamaba a un objetivo de OpenSSL inexistente (`install_ssldir`; el correcto es `install_ssldirs`).

## Comportamiento con carga

PDO MySQL contra MariaDB local en un laboratorio de 2 vCPU: una página con consulta rindió unos 135 req/s sin respuestas no 2xx con un pool de 5 hijos; con 2 hijos y una página de 1 s, 119 de 200 peticiones dieron 504 por saturación (el pool hace cola, no cae). Es una observación de comportamiento, no una medición de capacidad.

## Fuera del alcance verificado

Los scripts de escritura de la estrategia B se niegan fuera de la familia RHEL, y fuera de las combinaciones de `assets/alcance-verificado.conf` exigen una excepción fijada por una persona.

- Paquetes compilados para EL7 en EL8 o EL9: no corren (sonames distintos). Allí corresponde la estrategia A.
- Estrategia B en SUSE, Debian y Ubuntu.
- Actualización real con `zypper` y su rollback (solo se generó el plan).
- Capacidad a escala, código real de sitios de terceros, base de datos en otro servidor, correo, LDAPS, CIFS y NFS.
- Arquitecturas distintas de x86_64.
- Sitios que comparten `DocumentRoot` o llegan a otro docroot por `Alias`: el handler se asocia por directorio, no por VirtualHost.
- Derivadas de RHEL distintas de CentOS 7.9 y Rocky 9.8 (Alma, Oracle, RHEL): `scope_reasons` las marca como "sin probar" (campo `VERIFIED_DISTROS` de `assets/alcance-verificado.conf`) y exige la excepción de una persona; valídalas con `scripts/lab-test.sh` antes de agregarlas.
- `backup.sh restore --apply` en Debian, Ubuntu y SUSE.

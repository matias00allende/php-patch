# 08 - Distribuciones y estrategia por sistema

La skill orienta la decisión en sistemas Linux con PHP, pero **la estrategia cambia según el sistema** y la automatización y las pruebas solo cubren lo que detalla `11-perfiles-y-alcance-probado.md`. Primero ejecuta `scripts/detect-env.sh`: detecta familia, versión, gestor de paquetes, servidor web y SAPI, y sugiere A, B o C. Lo de abajo es el criterio detrás de esa sugerencia.

## Las tres estrategias

| | Qué es | Cuándo | Herramientas de la skill |
|---|---|---|---|
| **A. Paquetes** | Actualizar los paquetes PHP desde un repositorio mantenido | El repositorio ya publica la versión corregida para tu sistema | `pkg-upgrade-plan.sh`, `baseline.sh` |
| **B. Compilar al lado** | PHP corregido en `/opt/phpMM`, FPM por sitio, migración sitio a sitio | El sistema es EOL o ningún repositorio ofrece la versión corregida | todo `scripts/`, `build/` |
| **C. Mitigar** | WAF, aislamiento, reducción de superficie | Hay que cerrar el riesgo ya y A/B tardarán | `references/07-...` |

Siempre se pueden combinar: C mientras se prepara A o B.

## Matriz por familia (punto de partida; verificar con el proveedor)

| Familia / versión | Situación habitual | Estrategia sugerida | Notas |
|---|---|---|---|
| **RHEL, CentOS, Oracle Linux 7** | Fin de mantenimiento (CentOS 7: junio 2024). Solo hay soporte si hay suscripción de soporte extendido | **B** (o A si hay repositorio de pago/ELS que publique la corrección) | Es el caso principal de la skill. Scripts probados aquí |
| **CentOS 6 / RHEL 6** | Sin soporte hace años; glibc muy antigua | B es dudoso: los paquetes compilados para EL7 no corren. Compilar en un laboratorio EL6 o migrar | Sin verificar. Recomendar migración como prioridad |
| **RHEL, Rocky, AlmaLinux, Oracle 8 y 9** | Soportados | **A**: AppStream (`dnf module`) o repositorio de terceros mantenido | Cambiar de rama con `dnf module switch-to` es una migración, no un parche. Confirmar que la versión del repositorio incluye la corrección Los paquetes compilados para EL7 no corren aquí (sonames distintos; probado en Rocky 9.8). La activación por sitio y SELinux Enforcing sí se probaron en Rocky 9 con un PHP compilado allí (`references/12-resultados-de-verificacion.md`) |
| **CentOS Stream** | Rolling | A | Recibe las correcciones del upstream de RHEL |
| **Amazon Linux 1** | Sin soporte | B | Verificar glibc/openssl del laboratorio |
| **Amazon Linux 2** | Soporte limitado a una fecha publicada por AWS | A si `amazon-linux-extras` o el repositorio ya trae la versión corregida; si no, B | Revisar fecha de fin de soporte vigente |
| **Amazon Linux 2023** | Soportado | A | |
| **Ubuntu LTS (20.04, 22.04, 24.04...)** | PHP de la distribución es antiguo; muchos usan el PPA de un mantenedor reconocido para ramas nuevas | **A** con `apt-get install --only-upgrade` | Ubuntu sin soporte estándar (16.04, 18.04...) puede requerir ESM/Pro o B |
| **Debian 10/11/12** | La rama de PHP de la distribución recibe parches de seguridad mientras la versión tenga soporte (LTS incluido). Repositorios de terceros ofrecen ramas más nuevas | **A** | Debian sin soporte: migrar, contratar mantenimiento extendido o desarrollar y validar una adaptación manual (la estrategia B no está implementada para Debian en esta skill) |
| **SLES / openSUSE** | Repositorios del proveedor y OBS | **A** (`zypper patch`) | Verificar el boletín de seguridad del proveedor. Probado en openSUSE Leap 16.0 : Apache es `apache2` (unidad `apache2.service`, configuración en `/etc/apache2`, usuario `wwwrun`), PHP es `php8` + `apache2-mod_php8` (no existe `php8.4`), y `apache2ctl`/`apache2` no existen: se usa `apachectl` (envoltorio de `start_apache2`) o `httpd`. `httpd -M`/`-S` a secas NO ven los módulos de `/etc/sysconfig/apache2` (php, proxy_fcgi): usar `apachectl -M`/`-S`. Los scripts de solo lectura ya lo resuelven |
| **Alpine, imágenes de contenedor** | Imagen base con PHP | Reconstruir la imagen con la versión corregida | No aplica FPM-por-sitio del host |
| **Arquitectura distinta de x86_64** | ARM, etc. | B compilando en un laboratorio de esa arquitectura | Los paquetes de `build/` son x86_64 |

Las fechas de fin de soporte cambian; no las des por ciertas desde esta tabla: consúltalas en el sitio del proveedor y cítalas con fecha.

## Servidores web

- **Apache + mod_php (prefork):** el caso cubierto por `scripts/` (RHEL-family: `httpd`, `/etc/httpd`, usuario `apache`). En Debian/Ubuntu los equivalentes son `apache2`, `/etc/apache2`, usuario `www-data`, `a2enmod proxy_fcgi`; **la activación por sitio con estos scripts no existe allí**: `lib.sh` se detiene con un mensaje si encuentra `/etc/apache2` sin `/etc/httpd`; la lectura (`detect-env`, `inventory`, `baseline`, `pkg-upgrade-plan`) sí se probó en Ubuntu 24.04 (variables `HTTPD_BIN`, `HTTPD_ETC`, `WEB_USER` existen en `lib.sh`, pero la ruta de includes de Debian es distinta). En Debian/Ubuntu la vía normal es A.
- **Apache + PHP-FPM ya existente:** solo hay que actualizar el paquete FPM (A) o apuntar los `SetHandler` a pools nuevos (B).
- **Nginx:** los conceptos valen (pool por sitio, puerto fijo, rollback = volver el `fastcgi_pass`), pero hay que escribir `site.conf` en sintaxis de Nginx. La detección y la línea base con `baseline.sh` solo cubren Apache.
- **IIS u otros:** fuera de alcance.

## Qué cambia en estrategia A

1. `pkg-upgrade-plan.sh` muestra versión instalada, candidata y origen, y **escribe los comandos sin ejecutarlos**: respaldo, simulación (`-s` / `--assumeno`), aplicación, verificación y rollback.
2. Se ejecutan uno a uno (`references/09-modos-de-operacion.md`).
3. Con `mod_php` el reinicio de Apache corta conexiones: ventana acordada. Con FPM suele bastar `reload`, pero tras actualizar el paquete reinicia la unidad FPM si el empaquetado lo indica y comprueba la versión que sirve la web con una petición real (por ejemplo una página de diagnóstico temporal protegida), no solo `php -v`.
4. Antes y después: `baseline.sh save` / `compare`.
5. Si la simulación muestra que la actualización arrastra otros paquetes (kernel, libc, MySQL), **detente**: no es el parche acotado que se pidió. Usa `apt-mark hold` / `yum versionlock` para el resto o actualiza solo los paquetes PHP por nombre.

## Cuándo preguntar al usuario

- Si el sistema está en la matriz con "dudoso" o "verificar" y la decisión cambia el plan (A o B).
- Si hay más de una versión de PHP instalada a la vez (por ejemplo, la del sistema y otra de un repositorio de terceros): cuál sirve a cada sitio no se infiere, se lee de la configuración.

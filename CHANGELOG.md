# Cambios

## 1.0.0 - 2026-10-24

Primera versión pública.

### Qué incluye
- Detección del entorno y elección de estrategia: A (actualizar paquetes), B (PHP compilado al lado con PHP-FPM, un pool por sitio) o C (mitigar).
- Inventario de solo lectura, línea base de todos los vhosts, sitio sombra, activación y rollback por sitio, cambio de versión por sitio y desinstalación.
- Pre-validación pasiva desde fuera (`remote-version-check.sh`), con código propio.
- Respaldo y restauración de la configuración (`backup.sh`): obligatorio antes de cualquier cambio; restaurar simula por defecto y guarda antes el estado actual.
- Confirmación explícita para operaciones masivas (`--all`).
- Puertas de seguridad: lo no probado y las fuentes sin autenticar se niegan por defecto; solo una persona puede aceptar la excepción.
- Perfil guiado para quien opera por primera vez y perfil experto (`references/11`).
- Scripts de compilación (`build/`) con un hash verificado por cada fuente; reconstrucción de las dependencias y de PHP 8.2 a 8.5 en 14 minutos, sin excepciones, partiendo de un laboratorio sin `/opt/deps` ni `/opt/phpMM`.

### Seguridad de los propios scripts
- Instalación de paquetes por área privada: los paquetes se copian a un directorio de root (0700), se verifican y se extraen desde esa copia, se revisa el árbol extraído (sin setuid, sin enlaces que escapen, permisos sin escritura para grupo ni otros) y solo entonces se mueven a `/opt` con un rename; un paquete que falla no deja una instalación a medias.
- Una sola operación de escritura a la vez (candado con PID en `/run/lock/php-patch.d`); `uninstall.sh` no retira nada si no puede renombrar el directorio, y `fpm_sync` informa si no logra detener una unidad sin pools.
- Restauración con reversión automática: si falla a mitad o el configtest de Apache no pasa, `backup.sh` vuelve solo al estado guardado antes de restaurar.
- Respaldo verificado antes de reutilizarse, reversión ante interrupciones, validación de parámetros que van a configuración de Apache, TLS validado por defecto en la pre-validación remota y alcance verificado como combinaciones explícitas.

### Probado
- CentOS 7.9: PHP 8.2, 8.3, 8.4 y 8.5 con SELinux Enforcing y systemd real; PHP 8.3 y 8.4 también sin SELinux ni systemd.
- Rocky Linux 9.8: SELinux Enforcing, PHP 8.3 y 8.4.
- Ubuntu 24.04: lectura y estrategia A completa. openSUSE Leap 16.0: lectura y generación del plan de la estrategia A (sin actualización real ni rollback).
- Detalle en `references/12-resultados-de-verificacion.md`.

### Límites conocidos
- Los paquetes compilados para EL7 no corren en EL8 ni EL9: allí corresponde la estrategia A.
- unixODBC y libzip se autentican con una distribución independiente (confianza media), porque sus proyectos no publican hash ni firma: ver `references/02`.
- Las claves GPG de zlib, ICU y curl se tomaron del propio proyecto y no se cruzaron con un keyserver.
- Sin pruebas de carga y rendimiento a escala ni con el código real de sitios de terceros.

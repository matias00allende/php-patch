# 01 - Inventario de solo lectura

Objetivo: tener, con evidencia, el mapa de qué corre, dónde y de qué depende. Todo lo que no salga de una lectura se marca "no verificado".

## Cómo obtener acceso sin riesgo

Elige uno y déjalo escrito:

- **A. La persona opera, el agente guía.** La persona ejecuta los comandos con `sudo` y pega la salida. Más lento, cero delegación de privilegios.
- **B. `sudo` limitado a lectura.** Se otorga a una cuenta de auditoría una lista cerrada de comandos de lectura (`NOPASSWD` solo para esa lista). El agente ejecuta por SSH/SSM.
- **C. Cuenta con `sudo` completo.** Solo si está autorizado por escrito y con ventana. Es la que más exige disciplina de "no escribir nada".

Reglas de la conexión remota:

- Llave SSH en vez de contraseña. Si la cuenta es de dominio y tiene bloqueo por intentos, respeta la política de la organización (por ejemplo, dos intentos fallidos por servidor y por hora); al llegar al límite, detente y avisa.
- Un solo intento de conexión por servidor antes de planear: si falla, el problema suele ser del lado del servidor (sshd, libssh, PAM), no de la clave.
- Los scripts de apoyo viven en tu máquina. Para ejecutarlos sin escribir en el servidor: `ssh host "sudo bash -s" < script.sh`, o codificar en base64 y decodificar al vuelo. Esto sirve solo para los scripts de solo lectura que no cargan `lib.sh` (`detect-env.sh`, `inventory.sh`, `baseline.sh`, `compat-scan.sh`, `pkg-upgrade-plan.sh`); los que cargan `lib.sh` deben estar instalados como carpeta completa. `sudo bash -s` equivale a root completo: úsalo solo con un acceso ya autorizado. Si hay que dejar archivos, usa el home del operador y avisa.
- Consolas remotas que no manejan UTF-8 corrompen los acentos: usa `LC_ALL=C` y filtra con `tr -cd '\11\12\40-\176'` si necesitas texto limpio.
- No pegues contraseñas ni claves en el chat. Si el usuario las expone, márcalas para rotación inmediata y no las reutilices.

## Qué recolectar

`scripts/inventory.sh` entrega lo siguiente en una sola pasada de solo lectura:

| Bloque | Para qué sirve |
|---|---|
| SO, recursos | ¿Hay RAM y disco para `/opt` (3 GB) y los pools? |
| PHP del sistema, módulos de Apache | Qué SAPI sirve hoy; si hay `mod_php`, `proxy_fcgi`, MPM |
| `httpd -S` | Lista de VirtualHost con `ServerName`, puerto y archivo de configuración: **fuente de los nombres DNS** |
| DocumentRoot | Mapa vhost -> carpeta de código |
| `php_value`/`php_flag` | Quién dependerá de `mod_php` (darán 500 al retirarlo; con FPM se ignoran en silencio) |
| SELinux | Define si hace falta preparar contextos y puertos |
| Puertos en escucha | Para elegir un rango libre para los pools |
| Cron | Qué usa el PHP del sistema por CLI |
| Frameworks/CMS | Versión de WordPress, CodeIgniter, Laravel...: determina compatibilidad |

Complementos manuales (según el caso): accesos a base de datos externas, extensiones realmente usadas (`grep -r "sqlsrv_\|ldap_\|imap_\|mcrypt_" docroot`), tamaño de subidas, tráfico por sitio (logs de Apache de los últimos 30-90 días), reinicios programados de Apache (cron/logrotate), montajes de red servidos por Apache (CIFS/NFS).

## Matriz de sitios

Una fila por sitio, en CSV, con al menos:

`slug, dns (ServerName/ServerAlias), docroot, vhost-archivo, framework/versión, php-actual, base-de-datos, extensiones-críticas, tráfico-90d, riesgo(bajo/medio/alto), versión-objetivo, puerto, ola`

- `slug`: minúsculas, dígitos, `-`, `_`, `.`. Es el nombre del pool, del `.conf` y del estado.
- `dns`: el de los `ServerName`/`ServerAlias`. Si un vhost responde a varios nombres, anótalos todos. Un vhost que solo redirige (sin PHP) no necesita pool.
- Docroots anidados (un sitio dentro de la carpeta de otro): decide a qué sitio pertenece cada handler; el `<Directory>` más específico gana.
- **Duplicados y sin tráfico:** el mismo sitio en dos servidores, o sitios sin visitas en 90 días, son candidatos a retiro. Retirar reduce superficie y trabajo, pero lo decide el dueño del sistema.
- **Sitios ya rotos antes de empezar** (base de datos inexistente, 500 constante): regístralo en la línea base. Si no, se te atribuirá la falla.

## Orden de activación (olas)

Ordena de menor a mayor riesgo y ajusta con el dueño:

0. Sitio piloto: bajo tráfico, código simple, sin integraciones externas.
1. Sitios internos o de desarrollo.
2. Sitios medianos con base de datos propia.
3. Sitios críticos o con integraciones (SQL Server, LDAP, SOAP, correo).
4. Sitios condicionados (CMS antiguos, dependencias dudosas): requieren decisión previa.

El orden de **servidores** también cuenta: parte por el de menor riesgo para ensayar el procedimiento.

## Hallazgos que aparecerán (y no son parte de la tarea)

Credenciales en comentarios, directorios `.git` en el docroot, respaldos `*.bak`/`*_bkp` legibles, bases de datos expuestas en la red, servicios innecesarios, permisos setuid en carpetas web, WordPress sin actualizar. Regístralos en una tabla aparte con servidor, hallazgo y recomendación, **sin reproducir secretos**, y no los corrijas sin autorización.

## Prevalidación pasiva desde fuera

Antes de entrar a un servidor puedes estimar qué versión de PHP anuncia cada sitio con `scripts/remote-version-check.sh <archivo-de-urls>`. Solo lee las cabeceras `Server` y `X-Powered-By` y compara con la versión corregida de cada rama. Úsalo únicamente contra sistemas propios o con autorización escrita.

Es una **inferencia**, no una prueba: `expose_php=Off` o `ServerTokens Prod` ocultan la versión (resultado `NO-ANUNCIA`, no concluyente) y los paquetes de RHEL, Ubuntu y Debian corrigen con backports sin subir el número (un `VULNERABLE?` puede estar corregido). Para decidir, confirma con `inventory.sh` en el servidor y con el aviso del proveedor. Las versiones corregidas (8.2.35, 8.3.36, 8.4.27 y 8.5.12) se contrastaron con php.net el 2026-10-24; si aparece una versión posterior, se pueden sobrescribir con `FIXED_82`, `FIXED_83`, `FIXED_84` y `FIXED_85`. El código es propio y usa solo lectura pasiva de cabeceras. Cada consulta es un GET normal, que una aplicación puede registrar o responder creando una sesión: apunta a una página revisada. Por defecto se valida el certificado TLS; para un sistema propio con certificado autofirmado o vencido, `INSECURE_TLS=1` lo omite y el resultado queda marcado como no autenticado.


# 07 - Mitigación mientras tanto y riesgo residual

## Mitigación temporal (no sustituye al parche)

Mientras el parche no está desplegado, reduce la exposición:

1. **Lee el aviso oficial** de la CVE para identificar el vector real (qué SAPI, qué función o entrada, si requiere autenticación o archivos subidos). Sin vector claro no hay mitigación honesta.
2. **WAF o reglas del proxy** en el borde: si el proveedor publica reglas o firmas, actívalas en modo bloqueo tras un periodo de observación (modo `Count`/`Detect`) para medir falsos positivos. Sin firma publicada, acota por comportamiento: bloquea la subida de archivos ejecutables, restringe rutas administrativas por IP y limita métodos.
3. **Reducir superficie:** retira sitios sin uso, desactiva paneles de administración expuestos, restringe el acceso a redes de confianza lo que no sea público.
4. **Endurecer PHP:** `disable_functions` para las de ejecución de sistema donde la aplicación no las use, `open_basedir`, directorios de subida sin ejecución: con `mod_php`, `php_admin_flag engine off`; con PHP-FPM esa directiva no existe, así que deniega por HTTP las extensiones ejecutables en esas carpetas (también con `mod_php`: `engine off` por sí solo puede dejar el archivo descargable) (`<FilesMatch "\.(php|phtml|phar)$">Require all denied</FilesMatch>`) o guarda los archivos fuera del docroot, y prueba la precedencia real de Apache. `disable_functions` y `open_basedir` reducen el daño pero no son una frontera de seguridad.
5. **Monitoreo:** alertas sobre procesos hijos inesperados de `httpd`/`php-fpm`, archivos `.php` nuevos en carpetas de subida y conexiones salientes del servidor web.

## Riesgo residual de esta solución

| Riesgo | Detalle | Qué hacer |
|---|---|---|
| Librerías propias en `/opt/deps` | OpenSSL, libxml2, ICU, curl... quedan a cargo de quien despliega | Calendario mensual de CVE y recompilación; SBOM versionado |
| Fuentes sin firma verificada | Algunas fuentes se verifican solo por hash | Contrastar hash y firma GPG con el sitio oficial al compilar |
| SO sin soporte | El kernel, glibc y Apache siguen sin parches | Plan de salida con fecha; segmentar el servidor; WAF |
| CLI/cron con PHP viejo | Los scripts por CLI usan el PHP del sistema | Inventariar; migrar a `phpMM` donde se pueda |
| Sitios aislados en PHP antiguo | Excepciones vulnerables | WAF, fecha de retiro, dueño nombrado |
| Compatibilidad no garantizada | El código legado puede fallar en rutas poco usadas | Piloto, olas, monitoreo de logs post activación, rollback |
| Extensiones no compiladas | `mcrypt`, `wddx`, `imap`, `imagick` | Declarar el hallazgo por sitio; compilar solo si el sitio lo exige |
| Credencial del operador expuesta | Si se pegó una clave en un chat | Rotarla de inmediato |

## Indicadores para gobierno

- Sitios totales / sitios en PHP parchado / sitios aislados vulnerables / sitios retirados.
- Fecha de la última recompilación de `/opt/deps` y de la revisión de CVE.
- Tiempo medio de rollback demostrado.

## Marcos de referencia (alineación, sin forzar)

CIS Controls (gestión de vulnerabilidades, configuración segura), NIST CSF (Protect, Respond), ISO/IEC 27002 (gestión de vulnerabilidades técnicas, control de cambios). Cita el que corresponda a tu organización, no todos.

## Qué reportar al directivo en una frase

"La exposición se reduce sitio por sitio y cada activación tiene una reversión probada; X de Y sitios están parchados, Z siguen expuestos con mitigación y fecha de retiro, y el sistema operativo sigue sin soporte hasta que se migre."

## Actualizar las bibliotecas de `/opt/deps`

`install-package.sh` no sobrescribe un `/opt/deps` existente. Para actualizarlas: compila el paquete nuevo en el laboratorio, prueba **todas** las versiones de PHP que comparten esas bibliotecas, y en una ventana renombra `/opt/deps` (no lo borres), instala el paquete nuevo y compara con `baseline.sh`; el rollback es volver a renombrar el directorio anterior. Después reinicia **todas** las unidades `phpMM-fpm` (los procesos en marcha siguen con las bibliotecas viejas cargadas hasta reiniciarlos), verifica cada sitio con una petición real y, si algo falla, restaura el directorio anterior y reinicia otra vez.

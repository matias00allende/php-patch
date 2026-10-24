# Política de seguridad

## Reportar un problema de seguridad de la skill

Si encuentras un defecto en los scripts que pueda causar pérdida de datos, escalada de privilegios, ejecución de código no deseada o la instalación de software sin autenticar, **no lo publiques en un issue abierto**. Usa el reporte privado de vulnerabilidades de GitHub ("Security" > "Report a vulnerability") en este repositorio.

Incluye la versión de la skill, la distribución y versión del sistema operativo, los pasos para reproducirlo y, si puedes, la salida del script. **No incluyas credenciales, nombres de servidores reales ni datos de personas.**

## Qué esperar

Se confirma la recepción, se reproduce en un laboratorio y se corrige con una prueba nueva en `scripts/lab-test.sh`. El cambio se anota en `CHANGELOG.md`.

## Alcance y responsabilidad

La skill automatiza tareas que modifican servidores. Úsala primero en un ambiente de prueba, con respaldo del código y de las bases de datos, y con la autorización del dueño del sistema. Está proporcionada "tal cual", según la licencia Apache-2.0. Los límites de lo probado están en `README.md` y en `assets/alcance-verificado.conf`.

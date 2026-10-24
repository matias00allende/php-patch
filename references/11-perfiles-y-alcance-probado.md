# 11 - Perfiles de uso, alcance probado y excepciones

Esta skill debe servir tanto a quien opera servidores por primera vez como a un administrador con experiencia. Para lograrlo sin provocar fallas, los límites del alcance verificado y de la autenticidad de las fuentes no quedan solo como texto: los scripts los convierten en **puertas** que se niegan por defecto.

## Las dos puertas

| Puerta | Qué comprueba | Dónde actúa | Excepción (solo una persona) |
|---|---|---|---|
| **Alcance probado** | La combinación versión de PHP + familia RHEL + SELinux está en `assets/alcance-verificado.conf` | `install-package.sh`, `activate-site.sh` (y por tanto `change-version.sh`); `preflight.sh` la informa | `ACK_UNTESTED=yes` |
| **Autenticidad de fuentes** | El paquete o `/opt/deps` declaran `SOURCES-NOT-AUTHENTICATED.txt` | `install-package.sh`, `activate-site.sh` | `ACCEPT_UNAUTHENTICATED=yes` |

Además, dos confirmaciones ya existentes: `CONFIRM=yes` (operaciones masivas `--all`) y `RESTORE_CONFIRM=yes` (restaurar un respaldo no interactivo).

Estado actual del alcance probado (fecha en el propio archivo): PHP 8.2 a 8.5 en CentOS 7 (en Rocky 9 solo 8.3 y 8.4); SELinux Enforcing en CentOS 7 y Rocky 9. Quedan fuera, por tanto, RHEL 8 y derivadas, Amazon Linux y cualquier otra versión de PHP, hasta que haya resultados registrados en `references/12-resultados-de-verificacion.md` que lo respalden.

## Regla para el agente

1. **El agente nunca fija estas variables por su cuenta**, ni "para que el script avance". Si una puerta se niega, el agente se detiene, explica el motivo con las palabras del script y propone la alternativa segura.
2. Solo las fija una persona responsable que lo dijo con claridad en el chat ("acepto instalar fuera del alcance probado"). El agente lo anota en el informe de la fase.
3. Cada excepción queda en la bitácora (`/var/log/php-patch.log`) con la línea `ACK_UNTESTED=yes` o `ACCEPT_UNAUTHENTICATED=yes`.

## Perfil guiado (para quien opera por primera vez)

Preguntar una sola vez: *"¿Has instalado o actualizado PHP en un servidor de producción antes?"* En la duda, usar este perfil.

- **Siempre en acompañamiento:** una tarjeta de paso por mensaje (`assets/step-card.md`), con el comando, lo que debe ver y cómo deshacerlo. El agente no avanza hasta recibir la salida pegada y comprobarla.
- **Lenguaje simple:** primero qué hace el paso y qué puede salir mal; la sigla después.
- **Camino preferente:** estrategia A (actualizar paquetes) o plan de salida del sistema. La estrategia B se ofrece solo si hay una persona con experiencia que revise el plan y la combinación está dentro del alcance probado.
- **Sin excepciones:** en este perfil el agente no propone `ACK_UNTESTED` ni `ACCEPT_UNAUTHENTICATED`. Si una puerta se niega, se escala a una persona con experiencia.
- **Antes de tocar nada, tres confirmaciones en palabras de la persona:** el nombre del servidor (`hostname`) donde está ejecutando; que hay copia del código y de las bases de datos de los sitios (el respaldo de la skill es solo de configuración); y que existe una ventana de cambio autorizada.
- **Se detiene y pide ayuda** si: el estado leído difiere de la línea base, un script termina con error, aparece algo que el agente no sabe explicar, o el servidor es de producción y no hay ambiente de prueba.

## Perfil experto

- Puede operar en modo autónomo con identidad de mínimo privilegio, autorización escrita, bitácora e interruptor humano (`references/09`).
- Puede aceptar excepciones, con este mínimo por escrito: qué se ensayó y dónde, quién aprobó, qué riesgo se acepta (fuentes sin autenticar, versión no probada), cómo se revierte y fecha de revisión.
- Para fuentes sin autenticar, lo correcto antes de aceptar es cumplir `references/02` ("Autenticidad de las fuentes"): firma PGP del proyecto, comparación con un espejo independiente o compilación desde el paquete de la distribución.
- Si la excepción se ensaya y funciona, lo valioso es **ampliar el alcance**: probar, registrar los resultados en `references/12-resultados-de-verificacion.md` y agregar el valor a `assets/alcance-verificado.conf`.

## Cómo se amplía el alcance probado

1. Ejecutar `scripts/lab-test.sh` (con SELinux Enforcing si ese es el modo del destino) en un laboratorio de esa combinación.
2. Registrar fecha y resultados en `references/12-resultados-de-verificacion.md`.
3. Agregar el valor a `assets/alcance-verificado.conf` citando esos resultados. Sin resultados registrados, no se agrega.

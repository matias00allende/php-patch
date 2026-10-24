---
name: php-patch
description: Guía a un agente de IA, de forma cuidadosa y gradual, para remediar PHP vulnerable u obsoleto (RCE, "php to shell", CVE sin parche para la versión instalada) en servidores Linux (RHEL, CentOS, Rocky, Alma, Oracle Linux, Amazon Linux, Ubuntu, Debian, SUSE), incluidos los sistemas sin soporte como CentOS 7 donde no se puede migrar. Detecta el entorno y elige entre actualizar paquetes, compilar PHP parchado en /opt con PHP-FPM un pool por sitio (activación y rollback por sitio) o solo mitigar. Funciona de forma autónoma con acceso seguro o acompañando paso a paso a un operador. Incluye inventario y chequeos previos, línea base de vhosts, sitio sombra, compatibilidad, SELinux y errores conocidos. Úsala siempre que el usuario hable de parchear o actualizar PHP en producción, de una CVE de PHP, de PHP sin soporte, de CentOS 7 sin actualizaciones, de pasar de mod_php a PHP-FPM, de varias versiones de PHP en un servidor o de compilar PHP, aunque no nombre la skill.
---

# php-patch: remediar PHP con respaldo y reversión

Esta skill acompaña a un agente de IA (y a la persona que lo opera) a cerrar una vulnerabilidad de PHP en servidores reales, incluidos los de sistemas operativos sin soporte donde migrar no es posible. La prioridad es **no romper nada y mantener siempre un camino de vuelta probado para la configuración** (los scripts no restauran datos de las aplicaciones, bases de datos ni sesiones); la velocidad viene de automatizar el descubrimiento y las verificaciones, no de saltarse pasos.

## Principios (por qué trabajamos así)

1. **Aditivo antes que sustitutivo.** Lo nuevo se instala al lado de lo viejo y nada existente se modifica hasta el final. Así cada paso se puede deshacer.
2. **Un cambio a la vez, con ciclo cerrado.** Cada cambio sigue el ciclo de abajo. Si el paso anterior no se verificó, no se hace el siguiente.
3. **Ninguna inferencia se presenta como verificación.** Lo que no se leyó en un comando se marca "no verificado" o "inferido". Una suposición razonable que resulta falsa es la causa típica de una caída: por eso se revisa lo que "se sabe", no solo lo que se ignora.
4. **El estado se vuelve a leer.** Después de cada cambio se lee el estado real (no se confía en que el comando "salió bien"), y se compara con la línea base.
5. **Autorización por alcance.** Instalar, activar sitios y retirar `mod_php` son tres decisiones distintas; cada una requiere su visto bueno.
6. **Lo que no se pidió se reporta, no se corrige.** SELinux, firewall, bases de datos, credenciales expuestas y otros hallazgos van a una tabla aparte.
7. **Sin respaldo no hay cambio.** Todo script operativo que modifica la configuración del servidor (instalar, generar, activar, cambiar, revertir, retirar, sombra) crea antes un respaldo con `scripts/backup.sh` (o reutiliza uno de los últimos 10 minutos) y, si no puede crearlo, no cambia nada. Las operaciones masivas (`--all`) piden confirmación explícita. Los binarios y datos no se borran (se renombran o se apartan) y la configuración generada que se retira queda en el respaldo. El respaldo cubre **configuración**, no el código ni las bases de datos de los sitios: pide al responsable que los respalde aparte y no avances sin esa confirmación. Restaurar es `backup.sh restore <id>` (simula) y `--apply` (aplica, tras guardar el estado actual).
8. **Nada automático ni sin supervisión.** La skill no programa tareas, no activa sitios sin que se nombre el sitio, y en el modo autónomo se detiene ante cualquier diferencia con la línea base en lugar de "arreglar" algo.

9. **Lo no probado se niega por defecto.** Los límites que reconoce este documento son puertas en los scripts: una versión de PHP, una familia RHEL o un SELinux fuera de `assets/alcance-verificado.conf`, o fuentes de bibliotecas sin autenticar, detienen `install-package.sh` y `activate-site.sh`. Solo una persona responsable puede fijar `ACK_UNTESTED=yes` o `ACCEPT_UNAUTHENTICATED=yes`; **el agente nunca las fija por su cuenta** ni para "que avance" (`references/11`).

### Ciclo de cambio seguro (obligatorio para toda escritura)

```
1. PRE-CHEQUEO   confirmar servidor (hostname), usuario, espacio, estado actual y línea base guardada
2. PLAN          decir qué se va a ejecutar, el efecto esperado y el comando exacto de rollback
3. CAMBIO        un solo cambio, con un script de la skill cuando exista (deja bitácora)
4. POST-CHEQUEO  leer el estado real y comparar con la línea base (scripts/baseline.sh compare)
5. DECISIÓN      coincide -> siguiente paso | difiere -> detenerse, reportar, revertir si hay daño
```

Etiqueta cada afirmación como **Verificado** (la viste en una salida), **Inferido** (deducido, por confirmar) o **Recomendado** (criterio tuyo).

## Modos de operación (elegir al inicio)

| Modo | Cómo funciona | Detalle |
|---|---|---|
| **Autónomo** | El agente ejecuta por SSH/SSM con una identidad propia de mínimo privilegio, con autorización escrita, bitácora y un interruptor humano | `references/09-modos-de-operacion.md` |
| **Acompañamiento** | El agente prepara y la persona ejecuta: entrega **una tarjeta de paso por mensaje** (comando, esperado, cómo deshacer), interpreta la salida pegada y recién entonces da el siguiente | `references/09-...` y `assets/step-card.md` |

Por defecto: lectura autónoma si hay acceso; escritura en acompañamiento hasta que la persona autorice explícitamente más autonomía. Si no hay certeza del modo, pregunta una vez.

**Perfil de quien opera** (`references/11`): pregunta una vez si ha actualizado PHP en producción antes; en la duda, perfil **guiado**. El guiado va siempre en acompañamiento, con lenguaje simple, prefiere la estrategia A o el plan de salida, pide tres confirmaciones antes de tocar nada (el `hostname`, copia de código y bases de datos, ventana autorizada) y no propone excepciones: si una puerta se niega, escala a una persona con experiencia. El **experto** puede operar en autónomo y aceptar excepciones por escrito, con lo ensayado, quién aprobó y cómo se revierte.

## Flujo de trabajo

| Fase | Qué se hace | Automatizado por | Detalle |
|---|---|---|---|
| 0 | Detectar el entorno y elegir estrategia (A paquetes, B compilar al lado, C mitigar) | `scripts/detect-env.sh` | `references/00`, `references/08` |
| 0b | Pre-validación pasiva desde fuera: qué versión anuncia cada URL (inferencia, con autorización) | `scripts/remote-version-check.sh` | `references/01` |
| 1 | Inventario de solo lectura y matriz de sitios | `scripts/inventory.sh` | `references/01` |
| 2 | Respaldo de la configuración y línea base de todos los vhosts | `scripts/backup.sh create`, `scripts/baseline.sh save` | `references/10` |
| 3 | Ambiente de prueba (laboratorio, réplica, sitio sombra) | `scripts/lab-test.sh`, `scripts/shadow-site.sh` | `references/10` |
| 4A | Estrategia A: actualizar paquetes | `scripts/pkg-upgrade-plan.sh` | `references/00`, `08` |
| 4B | Estrategia B: compilar y empaquetar (en laboratorio) | `build/` | `references/02` |
| 5B | Instalar aditivo, definir sitios, piloto, olas, rollback | `scripts/preflight.sh`, `install-package.sh`, `generate-site.sh`, `activate-site.sh`, `rollback-site.sh`, `status.sh` | `references/03` |
| 6B | Retirar `mod_php`, cron/CLI, desinstalar | `scripts/check-modphp-retirement.sh`, `uninstall.sh` | `references/03` |
| Transversal | Errores conocidos, SELinux, compatibilidad, mitigación | `scripts/compat-scan.sh` | `references/04` a `07` |

Carga solo la referencia de la fase en curso.

### Fase 0 - Detectar y decidir

```bash
sudo bash scripts/detect-env.sh      # distribución, gestor de paquetes, servidor web, SAPI, SELinux, estrategia sugerida
```

La sugerencia es **Inferida**: se confirma con `references/00-decidir-estrategia.md` y con el administrador. Antes de compilar nada comprueba que ningún repositorio mantenido publica ya la versión corregida: compilar te convierte en mantenedor del paquete.

La versión corregida de PHP **no se toma de memoria**: se consulta en php.net (`ChangeLog`) o en el aviso oficial de la CVE, y se anota con fuente y fecha.

### Fase 1 y 2 - Inventario y línea base

```bash
sudo bash scripts/inventory.sh > inventario.txt     # solo lectura
sudo bash scripts/baseline.sh save /root/antes.tsv /   # código, tiempo y tamaño de cada vhost
```

Con eso se arma la matriz de sitios (slug, DNS del vhost, docroot, framework y versión, base de datos, riesgo, ola). Los nombres DNS salen de `ServerName`/`ServerAlias`, no de suposiciones. Marca los sitios sin tráfico y los duplicados: retirarlos es lo más barato, pero decide el dueño.

### Fase 3 - Ambiente de prueba (obligatorio en el perfil guiado; recomendado siempre)

Cuatro niveles, de menor a mayor cercanía a producción (`references/10-ambiente-de-prueba.md`): laboratorio de la plataforma, réplica sin datos reales, **sitio sombra** en loopback dentro del mismo servidor, y piloto real. Recomienda al menos el primero y el sitio sombra antes de activar nada.

### Fase 4B/5B - Estrategia B en comandos

```bash
sudo scripts/preflight.sh                                   # debe terminar en LISTO
sudo scripts/install-package.sh /ruta/paquetes 83           # aditivo: no activa nada
sudo scripts/generate-site.sh <slug> <docroot> --port auto  # luego REVISAR pool.conf y site.conf
sudo scripts/shadow-site.sh up <slug> 83 <ServerName>       # opcional: probar sin tráfico real
sudo scripts/shadow-site.sh down <slug>
sudo CHECK_HOST=<dns> scripts/activate-site.sh <slug> 83    # un sitio por vez; revierte solo si pasa a 5xx
sudo scripts/baseline.sh compare /root/antes.tsv            # nada más cambió
sudo scripts/rollback-site.sh <slug>                        # vuelta atrás de un sitio
```

Cuando el último sitio esté en FPM y haya pasado el tiempo de observación, retirar `mod_php` es un paso aparte (`check-modphp-retirement.sh` primero) y pide su propia autorización.

## Cómo decidir en los puntos delicados

- **Qué versión por sitio:** parte por la más nueva soportada que pase `compat-scan.sh` y las pruebas funcionales del sitio (dentro de las ramas del alcance probado) y baja solo si el código no corre. Los CMS muy antiguos no corren en 8.x: actualizar, retirar o aislar (`references/06`).
- **Sitio que no corre en PHP 8:** no lo dejes en `mod_php` si vas a retirarlo. Aíslalo en un PHP-FPM propio de la versión antigua, decláralo **explícitamente vulnerable** y exige mitigación (WAF) y fecha de retiro. Es una excepción documentada, no una solución.
- **Cuántos hijos de FPM:** `pm = ondemand`, `max_children` bajo; mide la RAM real.
- **SELinux Enforcing:** no cambies el modo. Si el administrador decidió no tocarlo, no actives sitios en un servidor Enforcing hasta preparar contextos y puertos con su acuerdo (`references/05`).
- **Cron y CLI:** los scripts de cron que llaman a `php` usan el PHP del sistema, que sigue sin parche. Inventariarlos y decidir.
- **Cuentas con bloqueo por intentos:** respeta la política de bloqueo de la cuenta (por ejemplo, dos intentos fallidos por servidor y por hora, o lo que fije la organización); al llegar al límite, detente y avisa.
- **Sin secretos en el chat:** si aparece una credencial, reporta sin reproducirla y recomienda rotarla.

## Qué entregar al usuario

Al cerrar cada fase: qué se hizo (con la salida que lo prueba), qué quedó sin hacer, el siguiente paso concreto y los hallazgos fuera de alcance. Por cada sitio activado: versión, puerto, hora, línea base antes/después y comando de rollback. Los scripts dejan bitácora en `/var/log/php-patch.log`.

## Alcance y límites

Lo que sigue no es solo una advertencia: `preflight.sh` informa si tu servidor está dentro del alcance verificado y los scripts se niegan a instalar o activar fuera de él (principio 9).

- **Verificado** (detalle en `references/12-resultados-de-verificacion.md`): CentOS 7.9 con Apache 2.4.6 y `mod_php` (68 comprobaciones de `scripts/lab-test.sh` con SELinux Enforcing y systemd real, sin denegaciones AVC); Rocky Linux 9.8 con SELinux Enforcing y systemd real (instalación, sombra, activación, cambio de versión, rollback y reinicio); Ubuntu 24.04 (lectura, estrategia A y unidad FPM); openSUSE Leap 16.0 (lectura y plan de la estrategia A). Base de datos local y carga ligera en Rocky 9: comportamiento, no capacidad.
- **Fuera del alcance verificado:** capacidad a escala; el código real de cada sitio; bases de datos en otro servidor, correo y LDAPS; la estrategia B en SUSE y Debian (allí la vía es la A); una actualización real con `zypper`.
- La activación por sitio con estos scripts está pensada para la familia RHEL con Apache (`httpd`). En Debian/Ubuntu y SUSE la vía normal es la estrategia A. Los paquetes compilados para EL7 no corren en EL8/9.
- `build/` se ejecutó completo para PHP 8.2, 8.3, 8.4 y 8.5 (`references/12-resultados-de-verificacion.md`). Las fuentes de las bibliotecas están fijadas por hash en `build/sources.sha256`: seis bibliotecas con confianza alta y dos (unixODBC y libzip) con confianza media, porque sus proyectos no publican hash ni firma (`references/02`, "Autenticidad de las fuentes"). Si cambias una versión sin hash contrastado, el paquete queda marcado y los scripts de instalación se niegan.
- Compilar PHP y sus librerías te hace responsable de vigilar las CVE de **esas librerías** (OpenSSL, libxml2, ICU, curl...). Ver `references/07`.
- El resultado es una mitigación seria, no una migración: un sistema sin soporte sigue sin soporte. Recomienda siempre un plan de salida del sistema operativo.

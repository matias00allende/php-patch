# php-patch

Skill para agentes de IA que ayuda a **remediar PHP vulnerable u obsoleto en servidores Linux reales**, incluidos los de sistemas sin soporte (CentOS 7, RHEL 7 y similares) donde no se puede migrar ni reinstalar, con controles para reducir el riesgo de regresiones y un procedimiento de reversión de configuración por sitio (sujeto a que exista el handler anterior).

Qué hace, en una línea: detecta el entorno, elige la estrategia más simple y segura (actualizar paquetes, compilar PHP parchado al lado con PHP-FPM un pool por sitio, o mitigar), y guía cada cambio con pre-chequeo, línea base, post-chequeo y rollback, ya sea operando de forma autónoma con acceso seguro o acompañando paso a paso a una persona.

## Qué incluye

```
php-patch/
├── SKILL.md                  instrucciones para el agente (punto de entrada)
├── LICENSE / NOTICE          Apache License 2.0
├── CHANGELOG.md / SECURITY.md  versiones y cómo reportar un problema de seguridad
├── references/               detalle por fase, se carga solo lo necesario
│   ├── 00-decidir-estrategia.md        árbol de decisión y variante Debian/Ubuntu
│   ├── 01-inventario.md                levantamiento de solo lectura y matriz de sitios
│   ├── 02-compilar-paquete.md          compilar y empaquetar (estrategia B)
│   ├── 03-instalar-y-activar.md        instalar aditivo, piloto, olas, rollback, retirar mod_php
│   ├── 04-errores-conocidos.md         síntoma, causa, solución
│   ├── 05-selinux.md                   preparación con SELinux Enforcing
│   ├── 06-compatibilidad-codigo.md     qué se rompe en PHP 8 y cómo medirlo
│   ├── 07-mitigacion-y-riesgo-residual.md
│   ├── 08-distribuciones.md            estrategia por distribución y servidor web
│   ├── 09-modos-de-operacion.md        autónomo y acompañamiento
│   ├── 10-ambiente-de-prueba.md        laboratorio, réplica, sitio sombra, piloto
│   ├── 11-perfiles-y-alcance-probado.md  perfil guiado y experto, puertas de seguridad y excepciones
│   └── 12-resultados-de-verificacion.md  qué se probó, dónde y con qué resultado
├── scripts/                  automatización en el servidor (bash)
│   ├── detect-env.sh                   detecta distribución, SAPI, SELinux; sugiere estrategia   [solo lectura]
│   ├── remote-version-check.sh         pre-validación pasiva por cabeceras HTTP (inferencia)     [solo lectura, remoto]
│   ├── backup.sh                       respaldo, verificación y restauración de la configuración [copia; restaura con --apply]
│   ├── inventory.sh                    inventario completo                                       [solo lectura]
│   ├── baseline.sh                     guarda y compara el estado HTTP de todos los vhosts       [solo lectura]
│   ├── compat-scan.sh                  lint y patrones eliminados en el código de un sitio       [solo lectura]
│   ├── pkg-upgrade-plan.sh             estrategia A: muestra versiones y propone comandos        [solo lectura]
│   ├── preflight.sh                    verifica requisitos antes de instalar                     [solo lectura]
│   ├── status.sh                       estado de sitios y servicios                              [solo lectura]
│   ├── check-modphp-retirement.sh      ¿es seguro retirar mod_php?                               [solo lectura]
│   ├── install-package.sh              instala PHP parchado en /opt (aditivo, no activa nada)
│   ├── generate-site.sh                crea pool.conf y site.conf de un sitio
│   ├── shadow-site.sh                  prueba un sitio con el PHP nuevo por loopback, sin tráfico real
│   ├── activate-site.sh                activa un sitio en PHP-FPM, con reversión automática
│   ├── change-version.sh               cambia un sitio de versión de PHP
│   ├── rollback-site.sh                devuelve un sitio (o todos) al PHP anterior
│   ├── uninstall.sh                    retira una versión (renombra, no borra)
│   ├── lab-test.sh  lab-reset.sh       suite de extremo a extremo para un laboratorio desechable (exige LAB_CONFIRM=yes)
│   └── lib.sh                          funciones comunes
├── build/                    compilar en un laboratorio (estrategia B)
│   ├── build-deps.sh   build-php.sh   make-package.sh   sources.sha256
├── assets/templates/         plantillas de pool FPM, sitio Apache, unidad systemd, opcache...
├── assets/step-card.md       plantilla de paso para el modo acompañamiento
├── assets/alcance-verificado.conf  combinaciones realmente probadas (PHP, RHEL, SELinux); fuera de ellas los scripts se niegan
```

## Cómo instalarla según el agente

La skill es Markdown + scripts bash: no depende de un agente en particular.

- **Claude Code:** copiar la carpeta a `~/.claude/skills/php-patch/` (o `.claude/skills/` del proyecto). Se invoca sola cuando la conversación trata de parchear PHP, o con `/php-patch`.
- **Otros agentes con soporte de skills o instrucciones de proyecto** (por ejemplo los que leen `AGENTS.md`, reglas de proyecto o prompts de sistema): poner `SKILL.md` como instrucciones y dejar `references/`, `scripts/`, `build/` y `assets/` accesibles en el repositorio de trabajo; indicar al agente que lea `references/NN-*.md` según la fase.
- **Sin agente:** los scripts y las referencias se pueden usar a mano. `references/03-instalar-y-activar.md` es un procedimiento completo para un operador.

## Uso rápido (estrategia B, familia RHEL con Apache)

```bash
sudo bash scripts/detect-env.sh                     # ¿qué estrategia corresponde?
sudo bash scripts/inventory.sh > inventario.txt     # levantamiento de solo lectura
sudo bash scripts/baseline.sh save /root/antes.tsv /
sudo bash scripts/preflight.sh
sudo bash scripts/install-package.sh /ruta/paquetes 83
sudo bash scripts/generate-site.sh miweb /var/www/html/miweb --port auto
sudo bash scripts/shadow-site.sh up miweb 83 www.miweb.example      # opcional
sudo CHECK_HOST=www.miweb.example bash scripts/activate-site.sh miweb 83
sudo bash scripts/baseline.sh compare /root/antes.tsv
```

Los paquetes de PHP se construyen una vez con `build/` en un laboratorio (`references/02-compilar-paquete.md`). **No se distribuyen binarios en este repositorio**: cada organización compila, verifica los hashes de las fuentes y mantiene sus paquetes.

## Alcance verificado

Resumen; el detalle por entorno está en `references/12-resultados-de-verificacion.md`.

| Entorno | Verificado |
|---|---|
| CentOS 7.9, SELinux Enforcing, systemd | `scripts/lab-test.sh` con PHP 8.2 a 8.5 sin excepciones: 68 PASS, 0 FAIL y 0 denegaciones AVC; `kill -9`, respaldo y restauración, reinicio completo e interrupción de una activación |
| CentOS 7.9 con `mod_php`, sin SELinux | `scripts/lab-test.sh` con PHP 8.3 y 8.4: 68 PASS, 0 FAIL |
| Rocky Linux 9.8, SELinux Enforcing, systemd | Sombra, activación con reversión automática, cambio de versión, rollback, `kill -9`, respaldo y restauración, reinicio completo y PDO MySQL contra MariaDB local, con PHP compilado en el propio servidor |
| Ubuntu 24.04 | Lectura y estrategia A completa; unidad `phpMM-fpm.service` verificada con `systemd-analyze verify` |
| openSUSE Leap 16.0 | Lectura y plan de la estrategia A |

Fuera de ese alcance los scripts se niegan o avisan: capacidad a escala, el código real de cada sitio, base de datos en otro servidor, correo, LDAPS, la estrategia B en SUSE y Debian, y una actualización real con `zypper`. Los paquetes compilados para EL7 no corren en EL8 ni EL9: allí corresponde la estrategia A.

Los scripts de solo lectura (`detect-env.sh`, `inventory.sh`, `baseline.sh`) funcionan con `httpd` y `apache2`.

## Para novatos y para expertos: los límites son puertas, no solo avisos

Los límites del alcance verificado y de la autenticidad de las fuentes se aplican en los scripts, para que quien tiene poca experiencia no provoque una falla por avanzar donde nadie ha comprobado que funciona:

- **Alcance verificado** (`assets/alcance-verificado.conf`): PHP 8.2 a 8.5 en CentOS 7 (8.3 y 8.4 también en Rocky 9), SELinux Enforcing en CentOS 7 y Rocky 9. `preflight.sh` informa si tu servidor está dentro; `install-package.sh` y `activate-site.sh` se niegan fuera de ello.
- **Autenticidad de fuentes:** `build/sources.sha256` fija el hash de cada fuente (de las ocho bibliotecas, seis con confianza alta por hash o firma del proyecto; unixODBC y libzip con confianza media, contrastadas con FreeBSD ports y Debian porque sus proyectos no publican hash ni firma). Si un paquete incluye fuentes sin autenticar (porque cambiaste una versión y usaste `ALLOW_UNPINNED=1`), la instalación y la activación se niegan.
- **Excepciones:** solo una persona responsable las fija (`ACK_UNTESTED=yes`, `ACCEPT_UNAUTHENTICATED=yes`), quedan en la bitácora y **el agente nunca las fija por su cuenta**. Para ampliar el alcance hay que probar y registrar los resultados en `references/12-resultados-de-verificacion.md`.
- **Perfil guiado** (por defecto si hay duda): acompañamiento paso a paso, lenguaje simple, estrategia A o plan de salida como camino preferente, tres confirmaciones antes de tocar nada y escalamiento a una persona con experiencia si una puerta se niega. **Perfil experto:** modo autónomo y excepciones documentadas. Detalle en `references/11-perfiles-y-alcance-probado.md`.

Esto reduce el riesgo, no lo elimina: ninguna puerta reemplaza el ambiente de prueba, el respaldo del código y de las bases de datos, ni la autorización del dueño del sistema.

## Seguridad y responsabilidad

- Los scripts que escriben exigen `root`, dejan bitácora y revierten ante fallos conocidos; aun así, **úsalos primero en un ambiente de prueba** (`references/10-ambiente-de-prueba.md`).
- La skill no sustituye la autorización del dueño del servidor, la ventana de cambio ni el criterio del operador.
- Compilar PHP y sus dependencias implica mantenerlas: planifica la vigilancia de CVE y la recompilación.
- No incluyas credenciales ni nombres de sistemas reales en issues, bitácoras compartidas o en este repositorio.

## Licencia

Apache License 2.0 (ver `LICENSE` y `NOTICE`). Puedes usar, modificar y redistribuir la skill, incluso con fines comerciales, conservando el aviso de copyright y el archivo `NOTICE`. Copyright 2026 Matías Allende.

## Contribuir

Probar en otra distribución, sumar casos a `references/04-errores-conocidos.md`, o ampliar `scripts/lab-test.sh` con escenarios nuevos son los aportes más valiosos. Cada cambio a un script debe mantener `scripts/lab-test.sh` en `FAIL=0` y reflejarse en la documentación.

## Autor

Matías Allende
[LinkedIn](https://www.linkedin.com/in/matiasallende/) · matias.allende.contreras@gmail.com

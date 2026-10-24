# 09 - Modos de operación: autónomo y acompañamiento

La skill funciona igual de bien con un agente que opera por sí mismo con acceso seguro, o con un agente que **acompaña a una persona** y le entrega cada paso. Se elige al principio y se puede cambiar a mitad de camino (por ejemplo, autónomo para lectura y acompañado para escritura).

## Elegir el modo

| | Modo autónomo | Modo acompañamiento |
|---|---|---|
| Quién ejecuta | El agente, por SSH/SSM con credenciales acotadas | La persona, en su sesión; el agente prepara y analiza |
| Ventaja | Rápido, repetible, deja bitácora | Cero delegación de privilegios; la persona aprende y valida |
| Cuándo | Servidores con acceso de auditoría ya concedido; muchas máquinas; lectura masiva | Primera vez, servidor crítico, sin acceso remoto, política que no permite acceso a un agente |
| Riesgo principal | Un comando mal formado hace daño real | Errores de copia/pega, salidas truncadas |

Preguntar al usuario solo si no está claro. Por defecto: **lectura en autónomo si hay acceso, escritura en acompañamiento hasta que la persona dé confianza explícita**.

## Acceso seguro para el modo autónomo

Prerrequisitos que el agente exige antes de empezar (y no negocia):

1. **Autorización escrita** del dueño del servidor, con alcance (qué servidores, qué fases) y ventana.
2. **Identidad propia del agente**, no la cuenta personal de nadie: usuario o rol dedicado.
3. **Autenticación sin contraseña pegable**: llave SSH (idealmente con certificado de corta vida) o un canal gestionado (SSM Session Manager, bastión con grabación). Las credenciales las inyecta el entorno; nunca pasan por el contexto del agente.
4. **Mínimo privilegio y por fases:**
   - Fase de lectura: `sudo` limitado a comandos de solo lectura (lista cerrada).
   - Fase de instalación y activación: `sudo` solo para los scripts de la skill por ruta absoluta, no `sudo` general. **Instala `scripts/` y `assets/` en un directorio propiedad de root y sin escritura para la cuenta del agente** (por ejemplo `/opt/php-patch-tools`, con `chown -R root:root` y `chmod -R go-w`): si la cuenta puede modificar los scripts que `sudo` le permite ejecutar, tiene root completo. Copiarlos a `~/pp/` sirve solo en el modo acompañamiento, donde ejecuta una persona.
5. **Registro:** sesiones grabadas o `script`/auditd; cada comando de escritura queda en `/var/log/php-patch.log` (lo escriben los scripts).
6. **Contención:** el agente puede detenerse y revertir por sí mismo (`rollback-site.sh`), y existe un interruptor humano (revocar la llave o el rol).
7. **Cuentas con bloqueo por intentos:** respetar la política de bloqueo de la cuenta (por ejemplo, dos intentos fallidos por servidor y por hora); al llegar al límite, detenerse y avisar. No reintentar en bucle.

Reglas de conducta del agente autónomo:

- Un comando de escritura por vez, con **pre-chequeo, cambio y post-chequeo** (ver "Ciclo de cambio seguro" en SKILL.md). No encadena varias escrituras en un solo comando.
- Antes de cada fase de escritura, **muestra el plan** (qué va a ejecutar, en qué orden, cómo revertir) y espera el visto bueno si la autorización no cubre esa fase.
- Si una salida no coincide con lo esperado, **se detiene**: no "arregla sobre la marcha". Reporta lo observado, la hipótesis y la propuesta.
- No instala herramientas, no sube scripts y no modifica archivos fuera de la ruta de trabajo acordada sin pedirlo.
- En el modo con `sudo` restringido, ejecuta solo los scripts instalados bajo un directorio de root, por ruta absoluta y con argumentos validados; define la regla sin `SETENV` y con entorno depurado (`env_reset`): los scripts leen variables como `LP_SCOPE_FILE`, `HTTPD_BIN` o `BACKUP_DIR`, y no deben poder fijarlas quienes solo tienen `sudo` restringido; `sudo bash -s` con el script por stdin equivale a root completo y solo corresponde a un acceso ya autorizado como administrador.
- Nunca ejecuta comandos que impriman secretos al contexto. Si necesita una credencial, usa el mecanismo de inyección del entorno.
- Los límites de tiempo y de volumen de salida protegen el contexto: `| head`, `| tail`, filtros.

## Modo acompañamiento: la "tarjeta de paso"

El agente entrega **un paso a la vez** con esta estructura (plantilla en `assets/step-card.md`):

```
PASO N de M - <título corto>
Para qué:     <una frase>
Riesgo:       ninguno (solo lectura) | bajo | medio | alto  - <por qué>
Antes:        <lo que debe ser cierto; cómo comprobarlo>
Comando:      <exacto, en un bloque para copiar>
Esperado:     <cómo se ve la salida correcta>
Si no coincide: detenerse y pegarme solo la salida pertinente, sin credenciales, nombres internos ni datos personales
Deshacer:     <comando exacto o "no aplica">
Después:      <comprobación que confirma el efecto>
```

Reglas del acompañamiento:

- **Un paso por mensaje** en las fases de escritura. En lectura se pueden agrupar varios comandos en un bloque.
- El agente **no avanza** hasta recibir la salida del paso. Cuando la recibe, la interpreta con etiquetas Verificado / Inferido / Recomendado y recién entonces entrega el siguiente.
- Los comandos son **completos y ejecutables**, sin marcadores ambiguos; si hay un valor que la persona debe completar, va en mayúsculas entre `<>` y se explica de dónde sale.
- Las salidas largas se filtran en el propio comando (`| head -50`).
- Ofrece siempre la vía de **aplicar un script de la skill** en lugar de varios comandos sueltos: es repetible y deja bitácora.
- Si la persona se equivoca de servidor o de usuario, el pre-chequeo del paso (`hostname`, `whoami`) lo detecta. Empieza cada sesión con `hostname; whoami; date`.
- Pregunta al final de cada fase si hay dudas y entrega un resumen con lo hecho, lo pendiente y el siguiente paso.

## Transición entre modos

Una buena secuencia para ganar confianza:

1. **Lectura autónoma** (inventario, detect-env, línea base) -> el agente muestra hallazgos.
2. **Preparación acompañada** (instalar de forma aditiva en un servidor de prueba): la persona ejecuta; el agente verifica con lectura.
3. **Piloto acompañado** en producción (un sitio).
4. **Olas autónomas** solo si la persona lo autoriza y los scripts demostraron revertir bien.

## Qué se le entrega a la persona siempre

Con cualquiera de los modos: un resumen por fase, la bitácora de comandos y resultados, la matriz de sitios actualizada, y los hallazgos fuera de alcance en una tabla aparte.

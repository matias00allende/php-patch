# 10 - Ambiente de prueba

Probar donde no duele es la mejor defensa contra "creía que estaba bien". Hay cuatro niveles; usa tantos como el riesgo justifique, de menor a mayor cercanía a producción.

## Nivel 1 - Laboratorio de la plataforma (siempre)

Un sistema desechable equivalente al destino (CentOS 7.9 u otro) con Apache + el PHP actual y una aplicación de prueba. Se corre `scripts/lab-test.sh` con los paquetes que se van a desplegar. Demuestra que **el mecanismo** funciona: instalar, activar, cambiar de versión, revertir y fallar de forma controlada.

Opciones para montarlo: VM (VirtualBox, KVM, VMware, nube), contenedor con systemd, o WSL con una importación de la imagen de la distribución (los scripts traen un sustituto mínimo de `systemctl` si no hay systemd). Documenta qué **no** reproduce: SELinux, systemd real, carga, datos reales.

## Nivel 2 - Réplica del servidor (recomendado para el primer servidor de cada tipo)

Una copia lo más fiel posible del servidor real, sin datos sensibles:

- **Snapshot o imagen del servidor** (VM/nube) restaurado en una red aislada, **sin salida a bases de datos ni servicios de producción**. Es la mejor opción si se puede.
- Si no hay snapshot: instalar el mismo sistema y paquetes, copiar `/etc/httpd` (o `/etc/apache2`), `/etc/php*` y los docroots; cambiar cadenas de conexión a una base de pruebas con datos sintéticos.
- Reproduce SELinux en el mismo modo que producción si es posible: es lo que el laboratorio genérico no cubre.
- Anonimiza o sustituye datos personales: no copies bases reales a un ambiente sin los controles de producción.

En la réplica se ejecuta **el flujo completo**: `inventory.sh`, `baseline.sh save`, instalación, generar y activar cada sitio, pruebas funcionales, rollback, y se mide el tiempo y la RAM.

## Nivel 3 - Sitio sombra en producción (sin tráfico real)

`scripts/shadow-site.sh` levanta el pool de un sitio y un VirtualHost que escucha **solo en loopback** (`127.0.0.1:18080`), con el mismo docroot. Los usuarios siguen en el PHP anterior; tú pruebas el sitio con el PHP nuevo:

```bash
sudo scripts/shadow-site.sh up <slug> 83 <ServerName>
curl -s --resolve <ServerName>:18080:127.0.0.1 http://<ServerName>:18080/ | head
tail /var/log/php83-fpm/<slug>-error.log
sudo scripts/shadow-site.sh down <slug>
```

Qué detecta: errores 500, funciones eliminadas, extensiones faltantes, avisos de compatibilidad, permisos de archivos, tiempos. Qué **no** hace: reproducir `Alias`, `Rewrite` de vhost ni SSL, y **comparte base de datos y archivos con el sitio real** (solo peticiones de lectura o cuentas de prueba; nada que escriba, envíe correos o dispare integraciones). Con SELinux en `Enforcing` el puerto de la sombra debe estar etiquetado como `http_port_t`.

Es la prueba más barata para decidir la ola de cada sitio y ordenar el riesgo antes de la activación real.

## Nivel 4 - Piloto real, un sitio

El primer sitio activado de verdad, con línea base, `CHECK_HOST` y la persona responsable atenta. Es el único nivel que prueba el flujo funcional real del sitio.

## Línea base automática

```bash
sudo scripts/baseline.sh save /root/antes.tsv /        # antes del cambio
# ... cambio ...
sudo scripts/baseline.sh compare /root/antes.tsv       # después: marca REGRESION, CAMBIO, TAMANO
```

Mide **todos los vhosts** que `httpd -S` descubre (código, tiempo y bytes), por loopback. Úsalo antes y después de cada instalación, activación y rollback: es lo que detecta el efecto colateral sobre un sitio que no estabas mirando.

## Qué probar siempre en cualquier nivel

`PATH_INFO`, cabecera `Authorization`, `SCRIPT_FILENAME`, `DirectoryIndex`, sesiones, subida de archivos, página lenta legítima, corte por timeout, módulos cargados, y el rollback completo. Todos están en `scripts/lab-test.sh` como ejemplo reutilizable.

## Criterio de salida de cada nivel

Pasar al siguiente solo cuando el anterior terminó sin fallos **y se entiende cualquier aviso**. Un `FAIL` que "se ve inofensivo" se trata como un hallazgo hasta explicarlo.

## Límites del sitio sombra

- Solo escucha en loopback y no replica las restricciones de acceso del vhost original (autenticación, listas de IP, `Require`): cualquier proceso local, o una aplicación vulnerable a SSRF hacia `127.0.0.1`, podría alcanzar el contenido. Úsala en ventanas cortas y retírala con `shadow-site.sh down`.
- "Solo lecturas" significa endpoints revisados uno a uno: un `GET` también puede escribir sesiones, caché, disparar trabajos o integraciones. Con base de datos y archivos compartidos con el sitio real, un error afecta datos reales; si no puedes aislarlos, usa la réplica sin datos reales.

## Cobertura de la línea base

`baseline.sh` descubre los vhosts por `httpd -S` (nombre y puerto, sin `ServerAlias`), compara solo los objetivos guardados y consulta siempre por loopback con `--resolve`: no detecta vhosts agregados después ni distingue vhosts ligados a una dirección específica. Úsala como red de seguridad, no como inventario completo, y revisa a mano los sitios con alias, SSL especial o direcciones propias. Si un vhost ya daba 5xx, `sin diferencias` no significa sano: el script lo avisa por separado.

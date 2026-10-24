# 05 - SELinux

**Alcance de este documento:** SELinux Enforcing con systemd real verificado en Rocky Linux 9.8 y en CentOS 7.9 (instalación, sitio sombra, activación con reversión automática, rollback, reinicio del FPM tras `kill -9` y reinicio completo; resultados en `references/12-resultados-de-verificacion.md`). Los booleanos de la sección siguiente salen de esas pruebas. Para base de datos en otro servidor, CIFS/NFS y correo, la sección es una lista de comprobación que se valida en el piloto de cada sitio.

## Regla de oro

No cambies el modo de SELinux (`setenforce`, `/etc/selinux/config`) sin autorización explícita. Si el administrador decide **no tocar SELinux**, entonces:

- En servidores `Disabled` o `Permissive`: no hay nada que preparar.
- En servidores `Enforcing`: no actives sitios hasta acordar con el administrador cómo preparar contextos y puertos. Instalar de forma aditiva sí es posible (el instalador no activa nada), pero deja pendiente la preparación.

## Por qué importa

Con `Enforcing`, Apache (`httpd_t`) con la política por defecto solo puede conectarse a puertos etiquetados como `http_port_t` (y a algunos otros tipos que la política enumera); los puertos de los pools (por defecto 9400-9499) no lo están. Sin etiquetarlos, `proxy_fcgi` falla con `Permission denied` aunque FPM escuche bien. Además, los binarios y directorios nuevos bajo `/opt` y `/var/lib` nacen sin contexto adecuado.

## Preparación (con autorización)

```bash
sudo yum install -y policycoreutils-python           # trae semanage en CentOS 7
sudo semanage port -a -t http_port_t -p tcp 9400-9499
sudo semanage fcontext -a -t httpd_exec_t  "/opt/php83/sbin/php-fpm"
sudo semanage fcontext -a -t bin_t         "/opt/php83/bin(/.*)?"
sudo semanage fcontext -a -t lib_t         "/opt/deps(/.*)?"
sudo semanage fcontext -a -t httpd_log_t     "/var/log/php83-fpm(/.*)?"
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/lib/php83(/.*)?"
sudo restorecon -R /opt/php83 /opt/deps /var/log/php83-fpm /var/lib/php83
```

**Lo que la prueba mostró y los scripts ya hacen:**

- El directorio de logs del FPM debe ser `httpd_log_t`, no `var_log_t`: el FPM corre como `httpd_t` y con `var_log_t` no puede abrir `php-fpm.log` (el servicio no arranca, `AVC denied { open }`). Si instalaste con una versión anterior, corrige con `semanage fcontext -m -t httpd_log_t "/var/log/php83-fpm(/.*)?"` y `restorecon -R /var/log/php83-fpm`.
- Etiquetar los puertos como `http_port_t` **no basta**: `httpd_t` solo puede conectarse a ellos con el booleano `httpd_can_network_relay` (o el más amplio `httpd_can_network_connect`). Sin él `proxy_fcgi` da 503 (`AVC denied { name_connect }`). `activate-site.sh` y `shadow-site.sh` se niegan con un mensaje claro y `preflight.sh` lo avisa. Activarlo es un cambio de SELinux: `sudo setsebool -P httpd_can_network_relay on` solo con autorización (se deshace con `off`).
- El puerto del sitio sombra (por defecto 18080) tampoco es `http_port_t`: un `Listen` en un puerto que `httpd_t` no puede abrir **detiene Apache al recargar**. `shadow-site.sh` se niega; usa un puerto ya etiquetado (`semanage port -l | grep http_port_t`, por ejemplo `SHADOW_PORT=8008`) o etiquétalo con autorización.

`install-package.sh` ejecuta esto **solo si se lo pides con `PREPARE_SELINUX=1`** (es un cambio persistente de SELinux que necesita autorización; sin esa variable solo avisa) y solo si `semanage` existe y el modo es `Enforcing`; si no existe, avisa y `activate-site.sh` se niega a activar hasta que los puertos estén etiquetados.

## Booleanos y casos típicos (a validar en el piloto)

- Si los sitios consultan bases de datos (MySQL/MariaDB por TCP, también en 127.0.0.1): `httpd_can_network_connect_db`. **Probado en Rocky 9.8** con PDO MySQL y MariaDB local: sin el booleano PHP responde `SQLSTATE[HY000] [2002] Permission denied` (500 de la aplicación) y el AVC es `denied { name_connect } ... comm="php-fpm" dest=3306 ... mysqld_port_t`; con el booleano en `on` la consulta funciona, sin AVC nuevos. Hace falta además `httpd_can_network_relay` para el puerto del pool (ver arriba): son dos booleanos distintos. `activate-site.sh` con `CHECK_PATH=` apuntando a una página que consulte la base detecta el 500 y revierte solo; sin esa comprobación la activación "pasa" porque la página principal puede no tocar la base. Es un cambio de SELinux: solo con autorización (`setsebool -P httpd_can_network_connect_db on`; se deshace con `off`).
- Si Apache sirve montajes CIFS/NFS: `httpd_use_cifs` / `httpd_use_nfs`.
- Si los sitios envían correo o llaman a APIs externas: `httpd_can_network_connect` (solo si hace falta).
- Directorios de subida escribibles por el sitio: `httpd_sys_rw_content_t`.
- Pools con `open_basedir` o rutas fuera de `/var/www`: etiquetar lo que lean o escriban.
- JIT de opcache queda desactivado precisamente para no pedir `httpd_execmem`.

## Cómo descubrir lo que falta sin romper nada

1. Con autorización, pasa **temporalmente** el servidor a `Permissive` en la ventana del piloto (`setenforce 0`, no persistente: un reinicio lo revierte). Mientras dure, SELinux no protege el servidor completo y solo registra: mantenlo el mínimo de tiempo y vuelve con `setenforce 1`.
2. Lee los avisos: `ausearch --input-logs -m avc -ts recent` y `audit2why`. **Usa `--input-logs` cuando el comando corre sin terminal** (ssh no interactivo, scripts, cron): sin él `ausearch` lee la entrada estándar en vez de `/var/log/audit/audit.log` y responde `<no matches>` aunque haya denegaciones (visto en la prueba de base de datos: el log tenía los AVC y `ausearch` decía que no había ninguno). Como respaldo, `grep type=AVC /var/log/audit/audit.log`. No apliques `audit2allow` a ciegas: revisa cada regla.
3. Aplica solo las etiquetas y booleanos necesarios, vuelve a `Enforcing` y repite la prueba.

Si el administrador no autoriza el modo `Permissive`, usa `ausearch -m avc` en `Enforcing` tras cada activación y revierte ante el primer bloqueo que afecte al sitio.

## Verificación posterior

`ausearch --input-logs -m avc -ts recent` sin entradas nuevas relacionadas con `httpd_t`/`php`, y el sitio funcional. Antes de cambiar nada guarda el estado previo (`getsebool -a`, `semanage fcontext -l -C`, `semanage port -l -C`) y documenta lo aplicado: `off` o `-d` solo restauran el estado anterior si antes estaba apagado o no existía la regla.

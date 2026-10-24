# 02 - Compilar y empaquetar PHP parchado

Se compila una vez, en un laboratorio, y se distribuye como paquete con hashes. Compilar en producción multiplica el riesgo (herramientas de compilación instaladas, tiempo de CPU, sin repetibilidad).

## Laboratorio

CentOS 7.9 desechable: VM, contenedor con systemd o WSL. Debe parecerse al destino (misma glibc, mismo `x86_64`).

Los repositorios de CentOS 7 ya no están en los espejos habituales; apunta a `vault.centos.org`:

```ini
[base]
name=CentOS-7 base (vault)
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-7 updates (vault)
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-7 extras (vault)
baseurl=https://vault.centos.org/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[sclo-rh]
name=CentOS-7 SCLo rh (vault)
baseurl=https://vault.centos.org/7.9.2009/sclo/$basearch/rh/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
```

(el bloque anterior verifica la firma de todos los paquetes. La clave de `sclo-rh` la instala el paquete `centos-release-scl-rh` de `extras` (**Inferido:** confirma el nombre del archivo con `ls /etc/pki/rpm-gpg/` y compara su huella con la publicada por el proyecto CentOS SIG SCLo). No desactives `gpgcheck`, ni siquiera en un laboratorio: el compilador que obtienes de ahí produce los binarios que irán a producción). Luego `yum groupinstall "Development Tools"`, `devtoolset-9` (gcc moderno) y los `-devel` de lo que PHP necesite (`libpng`, `libjpeg-turbo`, `freetype`, `openldap`, `gmp`, `libxslt`, `bzip2`, `readline`, `oniguruma`, `libsodium` de EPEL, `unixODBC`). `oniguruma-devel` y `libsodium-devel` salen de EPEL (`yum install epel-release`); `cmake3` (EPEL) lo exige `build-deps.sh` para libzip. **libzip no se toma del sistema**: CentOS 7 trae 0.10.1 y PHP 8.x exige >= 0.11 (`configure: error: ... libzip >= 0.11 ... were not met`); EPEL 7 no tiene `libzip5-devel`. Por eso `build-deps.sh` la compila en `/opt/deps`.

## Dependencias propias en `/opt/deps`

CentOS 7 trae librerías demasiado viejas para PHP 8.x. En lugar de reemplazar las del sistema, se compilan en `/opt/deps` y PHP las encuentra por **rpath**, de modo que el resto del servidor no se entera. `build/build-deps.sh` compila zlib, OpenSSL, libxml2, ICU, curl, SQLite, unixODBC y libzip.

Versiones que funcionaron en la compilación original (las de PHP se eligen según la CVE, ver abajo):

| Componente | Versión probada | Motivo |
|---|---|---|
| OpenSSL | 3.5.x | PHP 8.4+ exige >= 1.1.1 |
| libxml2 | 2.9.14 | PHP 8 exige >= 2.9.4 |
| ICU | 64.2 | `intl`; versiones más nuevas no se probaron con el toolchain |
| zlib | 1.3.1 | base de curl/libxml2 |
| curl | 8.x | PHP 8.4+ exige libcurl >= 7.61 |
| SQLite | 3.4x-3.5x | opcional |
| unixODBC | 2.3.12 | `pdo_odbc`, drivers SQL Server |
| libzip | 1.7.3 | `zip`; PHP exige >= 0.11 y excluye 1.3.1 y 1.7.0; se compila con cmake3 sin cifrado AES, bzip2 ni lzma |

Cambiar una versión exige repetir la prueba de laboratorio completa. Las librerías pequeñas (oniguruma, libsodium) se pueden compilar también o **copiar del sistema del laboratorio a `/opt/deps/lib`** con `BUNDLE_LIBS` en `make-package.sh`, para que el paquete sea autocontenido.

## Qué versión de PHP compilar

La primera versión de cada rama que corrige la vulnerabilidad, según el aviso oficial o `ChangeLog` en php.net. **Anota la fuente y la fecha de consulta.** Compila una por rama que vayas a ofrecer (por ejemplo 8.2, 8.3, 8.4, 8.5) para poder bajar de versión un sitio sin recompilar. Si la rama de tu PHP actual (p. ej. 7.4) ya no recibe correcciones, no hay versión parchada de esa rama: hay que subir de rama o aislar.

`build/build-php.sh <versión>` compila hacia `/opt/phpMM` con `--with-fpm-user=apache`, opcache y el conjunto de extensiones típico. Ajusta la lista según el inventario con variables de entorno, sin editar el script: `CONFIGURE_OPTS="..."` reemplaza el conjunto de extensiones por defecto (la base prefix/FPM/usuario se mantiene; útil fuera del laboratorio EL7, donde no existe `/opt/deps`) y `EXTRA_CONFIGURE="..."` agrega opciones al final (por ejemplo `EXTRA_CONFIGURE="--with-pdo-pgsql"`). Ejemplo mínimo con base de datos MySQL/MariaDB: `CONFIGURE_OPTS="--with-openssl --with-zlib --enable-opcache --with-libxml --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd"`. Si recompilas sobre un `/opt/phpMM` ya instalado, respáldalo antes (`cp -a`) y corre `restorecon -R` después en SELinux Enforcing. (El usuario del servidor web puede ser otro; `WEB_USER` en los scripts de instalación debe coincidir).

Diferencias de configuración entre ramas:

- `pdo_odbc`: en 8.2 y 8.3 se indica `--with-pdo-odbc=unixODBC,/opt/deps`; desde 8.4 basta `unixODBC` con `PKG_CONFIG_PATH`.
- PHP 8.5 trae opcache integrado: no se carga como `zend_extension` (el instalador ya lo contempla).
- Extensiones que desaparecieron del núcleo o están eliminadas (`mcrypt`, `wddx`, y `imap`/`imagick` que son externas) no se compilan; si un sitio las necesita, es un hallazgo de compatibilidad.

## Extensiones externas (SQL Server, por ejemplo)

`sqlsrv`/`pdo_sqlsrv` (Microsoft) se compilan con `phpize` contra cada PHP y requieren el driver ODBC de Microsoft (`msodbcsql17/18`) **en el servidor destino**. En el laboratorio solo se puede probar que cargan; la conexión real se valida en el piloto del sitio que la usa.

```bash
/opt/php83/bin/phpize && ./configure --with-php-config=/opt/php83/bin/php-config && make && make install
echo "extension=sqlsrv" > /opt/php83/etc/php.d/20-sqlsrv.ini
```

## Empaquetar

```bash
BUNDLE_LIBS="libonig libsodium" ./make-package.sh /root/paq 83:8.3.36 84:8.4.27
```

Genera `php-deps-1.tar.gz`, un `php-X.Y.Z-el7-opt.tar.gz` por versión y `SHA256SUMS`, e imprime las librerías del sistema que el destino debe tener (compáralas con el `preflight.sh`). Guarda `SHA256SUMS` por un canal distinto al de los paquetes.

## Procedencia y mantenimiento (SBOM mínimo)

Registra en un archivo versionado: versión y hash de cada fuente, fecha de compilación, compilador, flags de `configure`, hash de cada paquete. Las fuentes se verifican con `build/sources.sha256`; los hashes salen de la web oficial de cada proyecto, no de un cálculo propio sin contraste. Quien despliega queda como responsable de vigilar las CVE de **PHP y de cada librería de `/opt/deps`**: define una frecuencia (mensual) y quién la ejecuta.

## Prueba de laboratorio

```bash
sudo LAB_CONFIRM=yes scripts/lab-test.sh /root/paq 83 84   # con SELinux Enforcing: PREPARE_SELINUX=1 SHADOW_PORT=8008 y el booleano de references/05
```

Instala, genera un sitio, lo activa, cambia de versión y revierte, comprobando módulos, `PATH_INFO`, cabecera `Authorization`, sesión, subida de 3 MB, página lenta, timeout y fallo controlado con un pool inválido. Debe terminar en `FAIL=0`. Ejecuta antes `scripts/lab-reset.sh` si repites.

## Notas operativas del build

- unixODBC se configura con `--sysconfdir=/etc` a propósito: así lee los `odbc.ini` y `odbcinst.ini` del sistema (DSN existentes). `make install` puede dejar archivos de configuración en `/etc` del laboratorio: compila en un sistema desechable.
- Las comprobaciones HTTP locales de los scripts (`baseline.sh`, `probe`) usan `curl -k` sobre loopback: sirven para verificar funcionamiento, no validan el certificado TLS; prueba el HTTPS real desde fuera.

Tiempos de referencia en CentOS 7.9 con `JOBS=16`: `build-deps.sh` unos 4 minutos, cada `build-php.sh` unos 3 minutos, `make-package.sh` unos 25 segundos. Resultados de la prueba de extremo a extremo: `references/12-resultados-de-verificacion.md`.

- Las fuentes se descargan con el `curl` del sistema, que debe ejecutarse **sin** `LD_LIBRARY_PATH` apuntando a `/opt/deps` (el script ya lo hace con `env -u`); de lo contrario carga el libcurl nuevo y falla por libssl.so.3.
- OpenSSL 3 instala en `/opt/deps/openssl/lib64`: ese directorio debe figurar en rpath y `LD_LIBRARY_PATH` (corregido en `build-deps.sh`).
- `ext/ldap` enlaza el OpenSSL 1.0.2 del sistema (`libssl.so.10`) en el mismo proceso que el OpenSSL 3 de `/opt/deps`; no se probó LDAPS real. Validar en el piloto del sitio que use LDAP con TLS.
- Hashes: `build/sources.sha256` contiene un SHA256 por cada fuente del build, con el método de autenticación anotado en su cabecera. PHP, libxml2 y OpenSSL: hash publicado por el proyecto. zlib, ICU y curl: firma GPG verificada. SQLite: SHA3-256 publicado por sqlite.org (por eso se usa su tarball `sqlite-autoconf`, no el de etiqueta de GitHub). unixODBC y libzip: el proyecto no publica hash ni firma, así que se apoyan en una distribución independiente (FreeBSD ports y Debian), con **confianza media**. Un build sin `ALLOW_UNPINNED` no deja `SOURCES-NOT-AUTHENTICATED.txt`.

## Autenticidad de las fuentes

Un hash calculado después de descargar solo prueba que hoy recibes el mismo archivo que ayer. Estado de las fuentes con las que se probó la skill (2026-10-24): seis bibliotecas con confianza alta (hash o firma del proyecto) y dos con confianza media (unixODBC y libzip, contrastadas con distribuciones). Si cambias una versión o agregas una fuente sin SHA256 publicado, antes de usar `ALLOW_UNPINNED=1`:

1. Si el proyecto firma sus versiones (curl publica `.asc`), verifica la firma con la clave del mantenedor obtenida por un canal distinto al de la descarga (fingerprint publicado en el sitio oficial y en otro lugar independiente) y deja registrado el fingerprint usado.
2. Si no hay firma, descarga el archivo desde dos redes distintas o dos espejos oficiales y compara los hashes calculados. Es una comprobación de consistencia de **menor confianza**: detecta alteraciones de transporte o diferencias entre espejos, pero no prueba el origen.
3. Registra el resultado y el hash en el SBOM; una vez verificado, puedes agregar la línea a `build/sources.sha256` para tu propia organización (no la subas al repositorio público sin contrastar).
4. Con `ALLOW_UNPINNED=1` el build **descarga y ejecuta** `configure` y `make` de código sin autenticar: hazlo solo en un laboratorio aislado, sin secretos ni acceso a producción, y de preferencia sin root.
5. Los scripts dejan `SOURCES-NOT-AUTHENTICATED.txt` en `/opt/deps` mientras haya fuentes sin autenticar, y `install-package.sh` y `make-package.sh` lo avisan. Sin firma verificada (punto 1), usa el paquete en producción solo con una excepción de riesgo aprobada y documentada.

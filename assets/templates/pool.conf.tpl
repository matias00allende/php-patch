; pool.conf - php-patch - sitio @SLUG@. activate-site.sh lo renderiza a /opt/phpMM/etc/php-fpm.d/@SLUG@.conf
[@SLUG@]
user = @WEB_USER@
group = @WEB_USER@
listen = 127.0.0.1:@PORT@
listen.allowed_clients = 127.0.0.1
listen.backlog = 511
; ondemand: sin trafico no consume memoria; con muchos sitios por servidor es lo que permite convivir
pm = ondemand
pm.max_children = @MAX_CHILDREN@
pm.process_idle_timeout = 30s
pm.max_requests = 500
request_terminate_timeout = @TERMINATE@s
request_slowlog_timeout = @SLOW@s
slowlog = /var/log/php@MM@-fpm/@SLUG@-slow.log
access.log = /var/log/php@MM@-fpm/@SLUG@-access.log
access.format = "%{%Y-%m-%dT%H:%M:%S%z}t %m %r %s %{mili}dms %{kilo}MKB"
catch_workers_output = yes
decorate_workers_output = no
; mod_php heredaba el entorno del proceso de Apache; aqui el pool hereda el del servicio php-fpm (no es identico). Si el sitio depende de variables concretas, pasa clear_env = yes y declaralas con env[...]
clear_env = no
; --- registro, sesiones y temporales PROPIOS del sitio (aislamiento entre sitios)
php_admin_value[error_log] = /var/log/php@MM@-fpm/@SLUG@-error.log
php_admin_flag[log_errors] = on
php_admin_flag[display_errors] = off
php_admin_value[session.save_path] = /var/lib/php@MM@/session/@SLUG@
php_admin_flag[session.upload_progress.enabled] = off
php_admin_value[upload_tmp_dir] = /var/lib/php@MM@/tmp/@SLUG@
php_admin_value[soap.wsdl_cache_dir] = /var/lib/php@MM@/wsdlcache
; con FPM se lee .user.ini (mod_php lo ignoraba): se desactiva para no cambiar el comportamiento actual
php_admin_value[user_ini.filename] =
; --- limites: partir de los valores que el sitio ya tenia (php.ini, .htaccess), no de valores teoricos
; memory_limit va como php_value (no admin) porque muchos CMS lo elevan con ini_set; con admin ese ini_set falla en silencio
php_value[memory_limit] = @MEMORY@
php_admin_value[post_max_size] = @UPLOAD@
php_admin_value[upload_max_filesize] = @UPLOAD@
php_value[max_execution_time] = 30
; max_input_time: en las pruebas php_value no tuvo efecto en el pool; php_admin_value si (verificar el valor efectivo)
php_admin_value[max_input_time] = 60
php_admin_value[max_input_vars] = 1000
; FASE 2 (activar tras una semana sin errores): confinar el sitio a su propio arbol
;php_admin_value[open_basedir] = @DOCROOT@/:/var/lib/php@MM@/session/@SLUG@/:/var/lib/php@MM@/tmp/@SLUG@/:/tmp/

; /opt/php@MM@/etc/php-fpm.conf - generado por install-package.sh (php-patch)
[global]
pid = /run/php@MM@-fpm/php-fpm.pid
error_log = /var/log/php@MM@-fpm/php-fpm.log
log_level = warning
emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s
daemonize = no
include = /opt/php@MM@/etc/php-fpm.d/*.conf

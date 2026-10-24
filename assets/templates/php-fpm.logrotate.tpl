/var/log/php@MM@-fpm/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/kill -USR1 $(cat /run/php@MM@-fpm/php-fpm.pid 2>/dev/null) 2>/dev/null || true
    endscript
}

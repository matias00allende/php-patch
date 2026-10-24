# /etc/systemd/system/php@MM@-fpm.service - generado por install-package.sh (php-patch)
[Unit]
Description=PHP @VER@ FastCGI Process Manager (/opt/php@MM@, php-patch)
After=network.target

[Service]
Type=simple
Environment=PHP_INI_SCAN_DIR=/opt/php@MM@/etc/php.d
ExecStartPre=/opt/php@MM@/sbin/php-fpm -t --fpm-config /opt/php@MM@/etc/php-fpm.conf -c /opt/php@MM@/etc/php.ini
ExecStart=/opt/php@MM@/sbin/php-fpm --nodaemonize --fpm-config /opt/php@MM@/etc/php-fpm.conf -c /opt/php@MM@/etc/php.ini
ExecReload=/bin/kill -USR2 $MAINPID
RuntimeDirectory=php@MM@-fpm
Restart=on-failure
RestartSec=5s
LimitNOFILE=16384
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target

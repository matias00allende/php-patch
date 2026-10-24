#!/bin/bash
# /usr/local/bin/php@MM@ - CLI de PHP @VER@ con su propio php.ini (no reemplaza a /usr/bin/php)
export PHP_INI_SCAN_DIR=/opt/php@MM@/etc/php.d
exec /opt/php@MM@/bin/php -c /opt/php@MM@/etc/php.ini "$@"

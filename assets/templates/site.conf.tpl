# @APA_ACTIVE@/@SLUG@.conf - php-patch - sitio @SLUG@ -> PHP-FPM 127.0.0.1:@PORT@
# Rollback: mover este archivo a @APA_OFF@/ y ejecutar graceful (o rollback-site.sh @SLUG@).
<Directory "@DOCROOT@">
    # mod_php exponia la cabecera Authorization; con FPM hay que pasarla a mano
    SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1
    <FilesMatch "\.(php|phar)$">
        SetHandler "proxy:fcgi://127.0.0.1:@PORT@"
    </FilesMatch>
</Directory>
<Proxy "fcgi://127.0.0.1:@PORT@">
    ProxySet timeout=@PROXY_TIMEOUT@
</Proxy>

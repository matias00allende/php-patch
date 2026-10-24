; /opt/php@MM@/etc/php.d/10-opcache.ini - generado por install-package.sh
@OPCACHE_LOAD@
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=30000
; si los desarrolladores editan en caliente se conserva la revalidacion por tiempo
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.save_comments=1
; sin JIT: evita httpd_execmem en SELinux y no aporta a cargas web tipicas de aplicaciones legadas
opcache.jit=disable
opcache.jit_buffer_size=0

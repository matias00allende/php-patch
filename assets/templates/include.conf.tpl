# @APA_INCLUDE@ - php-patch
# Unico cambio global en Apache. Carga un archivo por sitio desde active/.
# Activar un sitio = copiar su .conf a active/ + graceful.
# Rollback del sitio = mover el .conf a off/ + graceful (el sitio vuelve al PHP anterior).
# Si active/ esta vacio, este archivo no cambia nada.
IncludeOptional @APA_ACTIVE@/*.conf
# Sitios sombra (pruebas por loopback, ver shadow-site.sh). Inertes si shadow/ esta vacio.
IncludeOptional @APA_BASE@/shadow/*.conf

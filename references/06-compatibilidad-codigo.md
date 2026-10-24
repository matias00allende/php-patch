# 06 - Compatibilidad del código con PHP 8

Subir de PHP 7.x a 8.x es lo que más sorprende en un proyecto de este tipo. La skill no migra código; lo que hace es **medir el riesgo antes de activar** y **permitir elegir versión por sitio**.

## Pasos baratos antes de activar

1. **Lint con el binario nuevo** sobre una copia de solo lectura del código:

```bash
bash scripts/compat-scan.sh /var/www/html/sitio /usr/local/bin/php83     # el wrapper pasa -n/-c; si no, usar /opt/php83/bin/php
```

Detecta errores de sintaxis y fatales de compilación. Un lint limpio **no** prueba compatibilidad.

2. **Patrones eliminados o en desuso** (el mismo script los busca; son indicios, no fallas seguras: pueden estar en comentarios o protegidos por `function_exists`): `get_magic_quotes_gpc`, `create_function`, `each()`, `mysql_*`, `ereg*`, `split()`, `mcrypt_*`, `money_format`, `utf8_encode/decode`, `FILTER_SANITIZE_STRING`, `strftime`. Cada coincidencia merece revisión; las funciones eliminadas fallan en tiempo de ejecución, las deprecadas solo avisan.

3. **PHPCompatibility** (opcional, si se puede instalar herramientas en la máquina del operador, no en el servidor): `phpcs --standard=PHPCompatibility --runtime-set testVersion 8.3-` sobre la copia del código.

4. **Versión del framework/CMS** (`inventory.sh` la detecta): es el mejor predictor.

## Casos frecuentes (orientativo, valida cada sitio con `compat-scan.sh` y pruebas funcionales)

- **CodeIgniter 3.1.x** (3.1.9 a 3.1.13): se reportó funcionando en PHP 8.3 con avisos `Deprecated` (sin prueba reproducible incluida; trátalo como advertencia por validar) (por ejemplo parámetros opcionales antes de requeridos, propiedades dinámicas) que no bloquean. Hay ramas de la comunidad que adaptan el `system/` de CI3 a PHP 8.4: pruébalas en un sitio piloto, no las apliques en masa.
- **WordPress muy antiguo** (núcleo de 2018 o anterior): falla con 500 por funciones eliminadas (`get_magic_quotes_gpc`). Actualizar el núcleo, el tema y los plugins, retirarlo o aislarlo.
- **Aplicaciones con SOAP, LDAP, GD, intl**: esas extensiones compilan y cargan en 8.2, 8.3, 8.4 y 8.5 con el conjunto de `build-php.sh` (probado en CentOS 7). `sqlsrv`/`pdo_sqlsrv` son extensiones externas que `build-php.sh` **no** compila ni se probaron: valida el driver, TLS y la versión de ODBC con una consulta real en el piloto.
- **Sitios sin tráfico** o duplicados: retirarlos es más barato que migrarlos.

## Cambios de PHP 8.x que suelen morder (verificar en la guía oficial de migración)

Fuente de verdad: `https://www.php.net/manual/es/migration80.php` y las páginas `migration81` a `migration85` de cada versión. Resumen orientativo:

- **8.0:** comparaciones entre string y número más estrictas, `match`/`mixed` como palabras reservadas, funciones eliminadas, errores que antes eran avisos ahora lanzan `TypeError`/`ValueError`.
- **8.1:** pasar `null` a parámetros no anulables de funciones internas queda `Deprecated`; `FILTER_SANITIZE_STRING` deprecado; `$GLOBALS` más restringido.
- **8.2:** propiedades dinámicas deprecadas; `utf8_encode/decode` deprecadas.
- **8.4:** tipos implícitamente anulables deprecados. **8.x en general:** cambios en `E_STRICT`, en manejo de sesiones y en algunas constantes (revisa la guía oficial de migración de cada rama).
- **Cualquiera:** `Deprecated` hoy puede ser error en la próxima rama; conviene limpiar mientras se está en una rama estable.

## Cómo decidir la versión de cada sitio

1. Parte de la más reciente soportada que pase el lint y los patrones, dentro del alcance verificado (`assets/alcance-verificado.conf`).
2. Si falla con una versión, prueba la anterior (`change-version.sh <slug> <MM>`): la plataforma está hecha para eso.
3. Si no corre en ninguna 8.x: **no es un problema de la plataforma**, es deuda del sitio. Opciones: actualizar el CMS/framework, reescribir, retirar, o aislar con PHP-FPM antiguo + WAF + fecha de retiro (explícitamente vulnerable).
4. Anota la decisión y el motivo en la matriz de sitios.

## Pruebas funcionales mínimas por sitio

Login, una consulta de lectura, una escritura, una subida y descarga de archivo, un PDF/correo si existe, una llamada a servicio externo (SOAP/REST/LDAP) y una página lenta legítima. Lo hace el dueño del sistema o alguien con acceso funcional; el agente solo puede comprobar códigos HTTP y logs.

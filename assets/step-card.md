# Tarjeta de paso (modo acompañamiento)

Copiar y completar un paso por mensaje en las fases de escritura.

```
PASO <N> de <M> - <título corto>

Para qué:       <una frase>
Servidor:       <nombre> (comprobar con: hostname; whoami)
Riesgo:         ninguno (solo lectura) | bajo | medio | alto - <por qué>

Antes (debe ser cierto):
  <condición>  -> comprobar con: <comando>

Comando (copiar y pegar completo):
  <comando exacto>

Esperado:
  <cómo se ve la salida correcta, con un ejemplo corto>

Si no coincide: detenerse y pegar la salida (revisa antes y oculta credenciales, nombres internos y datos personales). No seguir.

Deshacer:
  <comando exacto> | no aplica (solo lectura)

Después (confirmar el efecto):
  <comando de verificación> -> debe mostrar <resultado>
```

## Ejemplo

```
PASO 4 de 9 - Activar el sitio piloto

Para qué:       Pasar el sitio "intranet" al PHP parchado, con reversión automática si da error.
Servidor:       <nombre-del-servidor> (comprobar con: hostname; whoami)
Riesgo:         medio - los usuarios del sitio deberán iniciar sesión otra vez.

Antes (debe ser cierto):
  La línea base del sitio fue guardada  -> ls -l /root/antes.tsv
  El PHP parchado está instalado        -> /usr/local/bin/php83 -v | head -1

Comando:
  sudo CHECK_HOST=intranet.example.org bash ~/pp/scripts/activate-site.sh intranet 83

Esperado:
  ... linea base intranet.example.org: HTTP 200 ... OK intranet -> php83 (puerto 94xx)

Si no coincide: detenerse y pegar solo la salida pertinente, sin credenciales ni datos personales. No seguir.

Deshacer:
  sudo bash ~/pp/scripts/rollback-site.sh intranet

Después:
  sudo bash ~/pp/scripts/baseline.sh compare /root/antes.tsv  -> RESULTADO: sin diferencias
```

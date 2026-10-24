#!/bin/bash
# change-version.sh <slug> <MM> - mueve un sitio ya activo a otra version de PHP-FPM (con reversion automatica).
source "$(dirname "$0")/lib.sh"
slug=${1:?slug}; mm=${2:?MM}
[ -n "$(site_mm "$slug")" ] || die "$slug no esta activo en FPM; usar activate-site.sh"
exec "$(dirname "$0")/activate-site.sh" "$slug" "$mm"

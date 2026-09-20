#!/bin/sh
# Applies public.css / public.js to AzuraCast's settings, given their paths.
#
# Not `azuracast_cli azuracast:settings:set <key> <value>`, which is the obvious way and was
# the way until public.js outgrew it: the value goes in as one argv entry, and Linux caps a
# single argument at 128K (MAX_ARG_STRLEN, 32 pages) no matter how large ARG_MAX is. public.js
# crossed that at ~131K and every set has failed with E2BIG since. Both callers had the CLI's
# stderr on /dev/null, so an edit looked deployed and simply was not.
#
# The settings table is one row with a column per setting, so the same thing is one UPDATE
# piped over stdin - no argv, hence no ceiling. The file goes in hex: it needs no SQL escaping
# (nothing in it can end the literal) and it hands MariaDB the exact bytes, so the UTF-8 in
# both files survives whatever the connection charset happens to be.
#
# Shared by the azuracast-settings unit (default.nix) and `make azuracast-deploy`, which is
# why it reads the password off the container rather than taking it from either.
set -e

CSS_FILE=$1
JS_FILE=$2

PASSWORD=$(podman inspect azuracast --format '{{range .Config.Env}}{{println .}}{{end}}' |
  sed -n 's/^MYSQL_PASSWORD=//p')

set_setting() {
  {
    printf "UPDATE settings SET %s = UNHEX('" "$1"
    od -An -v -tx1 <"$2" | tr -d ' \n'
    printf "');\n"
  } | podman exec -i azuracast mariadb -u azuracast -p"$PASSWORD" azuracast
}

set_setting public_custom_css "$CSS_FILE"
set_setting public_custom_js "$JS_FILE"

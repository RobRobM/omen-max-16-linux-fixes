#!/bin/sh
# Dry-run test of brightness/omen-ec-backlight: checks the 2..200 mapping, nothing is written.
d=$(cd "$(dirname "$0")/.." && pwd); t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bl" "$t/dmi"; echo F.20 > "$t/dmi/bios_version"; echo 192000 > "$t/bl/max_brightness"
printf 'ECPW_ADDR=0xFD400CF5\nECOE_ADDR=0xFD400CF4\nECOE_BIT=0\nBIOS_VERSION=F.20\n' > "$t/conf"
fail=0
run() { OMEN_EC_DRYRUN=1 OMEN_EC_CONF="$t/conf" OMEN_EC_BL="$t/bl" OMEN_EC_DMI="$t/dmi" OMEN_EC_FLAG="$t/flag" "$d/brightness/omen-ec-backlight" 2>&1; }
check() { echo "$1" > "$t/bl/brightness"; got=$(run); want="busybox devmem 0xFD400CF5 8 $2"
  if [ "$got" = "$want" ]; then echo "PASS brightness $1 -> $2"; else echo "FAIL brightness $1: got '$got' want '$want'"; fail=1; fi; }
check 0 2; check 1920 2; check 96000 100; check 192000 200; check 999999 200; check 19200 20
echo F.21 > "$t/dmi/bios_version"; got=$(run)
case "$got" in *re-run*) echo "PASS BIOS mismatch refuses";; *) echo "FAIL BIOS mismatch: $got"; fail=1;; esac
exit $fail

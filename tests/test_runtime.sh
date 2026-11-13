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

# --- keyboard/omen-ec-suspend.sleep (dry run) ---
printf 'ECPW_ADDR=0xFD400CF5\nECOE_ADDR=0xFD400CF4\nECOE_BIT=0\nPECF_ADDR=0xFD400657\nPECF_BIT=1\nBIOS_VERSION=F.20\n' > "$t/conf2"
echo F.20 > "$t/dmi/bios_version"; echo Y > "$t/param"
srun() { OMEN_EC_DRYRUN=1 OMEN_EC_DRYVALUE=$2 OMEN_EC_CONF="${4:-$t/conf2}" OMEN_EC_DMI="$t/dmi" OMEN_EC_PARAM="$t/param" sh "$d/keyboard/omen-ec-suspend.sleep" "$1" 2>&1; }
scheck() { got=$(srun "$1" "$2" x "$4"); if [ "$got" = "$3" ]; then echo "PASS suspend $1 value $2 -> '$3'"; else echo "FAIL suspend $1 $2: got '$got' want '$3'"; fail=1; fi; }
scheck pre 0x00 "busybox devmem 0xFD400657 8 2"
scheck pre 0x41 "busybox devmem 0xFD400657 8 67"
scheck post 0x43 "busybox devmem 0xFD400657 8 65"
scheck post 0xFF "busybox devmem 0xFD400657 8 253"
scheck resume 0x00 ""
echo N > "$t/param"; scheck pre 0x00 ""; echo Y > "$t/param"
echo F.21 > "$t/dmi/bios_version"; scheck pre 0x00 ""; echo F.20 > "$t/dmi/bios_version"
printf 'BIOS_VERSION=F.20\n' > "$t/conf3"; scheck pre 0x00 "" "$t/conf3"

# --- keyboard/omen-kbd-light.sleep (dry run, fake sysfs) ---
mkdir -p "$t/hr/hidraw5" "$t/hr/hidraw6" "$t/usb/3-9:1.3/0003:0D62:54BF.0005" "$t/usb/3-9:1.4/0003:0D62:54BF.0006"
ln -s "$t/usb/3-9:1.3/0003:0D62:54BF.0005" "$t/hr/hidraw5/device"; ln -s "$t/usb/3-9:1.4/0003:0D62:54BF.0006" "$t/hr/hidraw6/device"
krun() { OMEN_KBD_DRYRUN=1 OMEN_KBD_SYSFS="$t/hr" OMEN_KBD_PARAM="$t/param" python3 "$d/keyboard/omen-kbd-light.sleep" "$1" 2>&1; }
kcheck() { got=$(krun "$1"); if [ "$got" = "$2" ]; then echo "PASS kbd-light $1 -> '$2'"; else echo "FAIL kbd-light $1: got '$got' want '$2'"; fail=1; fi; }
echo Y > "$t/param"
kcheck pre "write /dev/hidraw5 0900010000"
kcheck post "write /dev/hidraw5 0900010001"
kcheck resume ""
echo N > "$t/param"; kcheck pre ""
exit $fail

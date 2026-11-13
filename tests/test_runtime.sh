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
rec=0405040100030101c8c80000000000000000000000000000000000000000000000000000   # colour cycle, brightness byte zeroed
krun() { OMEN_KBD_DRYRUN=1 OMEN_KBD_SYSFS="$t/hr" OMEN_KBD_PARAM="$t/param" OMEN_KBD_STATE="$t/kstate" OMEN_KBD_DRYREPLY="$2" python3 "$d/keyboard/omen-kbd-light.sleep" "$1" 2>&1 | tr '\n' '|'; }
kcheck() { if [ "$2" = "$3" ]; then echo "PASS kbd-light $1"; else echo "FAIL kbd-light $1: got '$2' want '$3'"; fail=1; fi; }
echo Y > "$t/param"; rm -f "$t/kstate"
got=$(krun pre 830024d004050401a0030101c8c8000000000000000000000000000000000000000000000000000000000000)
kcheck "pre saves effect, lights off" "$got" "write /dev/hidraw5 83000000|write /dev/hidraw5 0900010000|pre: effect 4 saved, lighting off via /dev/hidraw5|"
kcheck "pre state file" "$(cat "$t/kstate")" "$rec"
got=$(krun post "")
kcheck "post restores" "$got" "write /dev/hidraw5 0900010001|write /dev/hidraw5 03002400$rec|post: effect 4 restored via /dev/hidraw5|"
got=$(krun pre 830024d000050401c8030101c8c8000000000000000000000000000000000000000000000000000000000000)
kcheck "pre with lighting already off" "$got" "write /dev/hidraw5 83000000|pre: lighting already off or effect unreadable, nothing to do (/dev/hidraw5)|"
kcheck "no state left" "$([ -e "$t/kstate" ] && echo yes || echo no)" "no"
got=$(krun post ""); kcheck "post without state" "$got" "post: no saved effect, lighting left as it is|"
got=$(krun resume ""); kcheck "other phase ignored" "$got" ""
echo N > "$t/param"; got=$(krun pre 83); kcheck "inert without sleep_no_lps0" "$got" ""
exit $fail

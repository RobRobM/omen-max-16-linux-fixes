#!/bin/bash
# Install the EC backlight fix (brightness part only). Run as root: sudo ./install.sh [--yes]
# Idempotent. Does not edit the bootloader; it tells you which kernel parameters to add.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
CONF=/etc/omen-ec-backlight.conf
SBIN=/usr/local/sbin
RULE=/etc/udev/rules.d/70-omen-ec-backlight.rules
HOOK=/usr/lib/systemd/system-sleep/omen-ec-backlight
SUSPEND=/usr/lib/systemd/system-sleep/omen-ec-suspend

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo $0)." >&2; exit 1; }
assume_yes=0; [ "${1:-}" = "--yes" ] && assume_yes=1

BUSYBOX=/usr/bin/busybox; [ -x "$BUSYBOX" ] || BUSYBOX=$(command -v busybox || true)
[ -n "$BUSYBOX" ] || { echo "busybox not found (apt install busybox-static or busybox)." >&2; exit 1; }
"$BUSYBOX" --list 2>/dev/null | grep -qx devmem || { echo "$BUSYBOX has no devmem applet." >&2; exit 1; }
command -v iasl >/dev/null || { echo "iasl not found (apt install acpica-tools)." >&2; exit 1; }

echo "Running the detector on this machine's firmware..."
python3 "$here/brightness/omen-ec-backlight-detect" --write "$CONF"
# shellcheck disable=SC1090
. "$CONF"
echo
echo "Detected (from $CONF):"
echo "  board $BOARD_NAME, BIOS $BIOS_VERSION"
echo "  ECPW at $ECPW_ADDR, ECOE at $ECOE_ADDR bit $ECOE_BIT"
ecpw=$("$BUSYBOX" devmem "$ECPW_ADDR" 8 2>&1) || ecpw="unreadable ($ecpw)"
ecoe=$("$BUSYBOX" devmem "$ECOE_ADDR" 8 2>&1) || ecoe="unreadable ($ecoe)"
if [ -n "${PECF_ADDR:-}" ]; then
  echo "  PECF at $PECF_ADDR bit $PECF_BIT, current byte = $("$BUSYBOX" devmem "$PECF_ADDR" 8 2>&1 || true)"
else
  echo "  PECF not found: the suspend hook will stay inactive"
fi
echo "  current ECPW = $ecpw  (expect 0..200)"
echo "  current ECOE byte = $ecoe  (bit $ECOE_BIT must be 1)"
echo
echo "Will install:"
echo "  $SBIN/omen-ec-backlight        (runtime script)"
echo "  $SBIN/omen-ec-backlight-detect (detector)"
echo "  $RULE"
echo "  $HOOK"
echo "  $SUSPEND  (inert unless acpi_x86.sleep_no_lps0=1)"
if [ "$assume_yes" -ne 1 ]; then
  printf 'Continue? [y/N] '; read -r a
  case "$a" in y|Y|yes) ;; *) echo "Aborted; $CONF was written, uninstall.sh removes it."; exit 1;; esac
fi

install -D -m 755 "$here/brightness/omen-ec-backlight" "$SBIN/omen-ec-backlight"
install -D -m 755 "$here/brightness/omen-ec-backlight-detect" "$SBIN/omen-ec-backlight-detect"
install -D -m 644 "$here/brightness/70-omen-ec-backlight.rules" "$RULE"
install -D -m 755 "$here/brightness/omen-ec-backlight.sleep" "$HOOK"
install -D -m 755 "$here/keyboard/omen-ec-suspend.sleep" "$SUSPEND"
udevadm control --reload
udevadm trigger --action=change --subsystem-match=backlight --sysname-match=intel_backlight || true
echo "Installed, udev reloaded, change event sent."
echo
echo "Kernel parameters (add to GRUB_CMDLINE_LINUX_DEFAULT yourself, then update-grub and reboot):"
for p in acpi_backlight=native acpi_x86.sleep_no_lps0=1; do
  if grep -qw -- "$p" /proc/cmdline; then echo "  $p   present"; else echo "  $p   MISSING"; fi
done
echo "acpi_backlight=native is needed for this fix; acpi_x86.sleep_no_lps0=1 is only for the keyboard fix (see README)."

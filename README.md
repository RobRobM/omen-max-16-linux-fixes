# HP OMEN MAX 16 on Linux: brightness and keyboard fixes

Two workarounds for the HP OMEN MAX 16 (16-ah0xxx, board 8D41) on Linux. They are workarounds
for firmware behaviour; the proper fix belongs in the kernel and/or HP's firmware.

## What this fixes

**1. Screen brightness does nothing.** The brightness slider and the brightness keys move,
`/sys/class/backlight/*/brightness` changes, but the panel never gets dimmer. After boot or
resume it sits at about half brightness.

**2. Keyboard backlight is dead and F2/F3/F4 do the wrong thing.** The keyboard backlight is off,
and F2, F3 and F4 (brightness down, brightness up, keyboard backlight) all send the same key (F13,
which opens Settings on GNOME). It survives reboots; only a full power-off clears it, and it comes
back after the next suspend.

## Supported hardware

Tested: HP OMEN MAX 16-ah0xxx, board 8D41, BIOS F.20, kernel 7.0, Ubuntu 26.04, hybrid graphics
mode, Intel Arrow Lake + RTX 5080, Secure Boot off. Anything else is untested. The detector prints
a warning on other boards; read `docs/how-it-works.md` before trying it there.

## Fix 1: screen brightness

The embedded controller (EC) generates the panel's backlight PWM, and Linux never tells it the
level. `install.sh` installs a udev rule that, on every `intel_backlight` change, writes the
level (mapped to 2..200) into the EC's brightness register, plus a system-sleep hook that
re-applies it after resume.

Requirements: `busybox` with the `devmem` applet, `acpica-tools` (`iasl`), python3.

```
sudo apt install busybox-static acpica-tools     # package names on Debian/Ubuntu
sudo ./install.sh                                 # --yes skips the confirmation
```

Then add `acpi_backlight=native` to your kernel command line (for GRUB: edit
`GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, run `sudo update-grub`, reboot). The installer
does not touch your bootloader; it only reports whether the parameter is present.

The installer runs `brightness/omen-ec-backlight-detect`, which reads your own firmware and works
out the register addresses; nothing is hardcoded. It shows what it found and the current register
values and asks before installing. Config: `/etc/omen-ec-backlight.conf`.

**Verify:** `cat /sys/class/backlight/intel_backlight/{brightness,max_brightness}`, then change the
brightness with the slider: the panel should now follow. By hand, the current EC value is
`sudo busybox devmem <ECPW_ADDR> 8` (address from the config); it should track the slider between
2 and 200. Log lines: `journalctl -t omen-ec-backlight`.

**Undo:** `sudo ./uninstall.sh`, then remove `acpi_backlight=native` if you added it.

**After a BIOS update:** the script refuses to write when the BIOS version differs from the one in
the config (it logs a line). Re-run `sudo omen-ec-backlight-detect --write /etc/omen-ec-backlight.conf`
and check the output.

## Fix 2: keyboard backlight and F2/F3/F4

Cause: when the kernel enters s2idle it calls the ACPI LPS0 `_DSM` (modern standby). The HP
firmware then switches the keyboard's microcontroller (Darfon `0d62:54bf`, "HP Gaming Keyboard II",
per-key RGB) into a mode that expects Windows software. The state lives in MCU RAM.

Steps:

1. Add `acpi_x86.sleep_no_lps0=1` to the kernel command line (see above) and reboot.
2. Do one full power-off (shut down completely, not a reboot).
   Boot again: backlight and F2/F3/F4 work.
3. Run `sudo ./install.sh` (see Fix 1) to get the suspend hook that keeps the fans quiet. It needs
   the detector, which also locates `PECF`.
4. Optional, for colours: install [omen-rgb-linux](https://github.com/arfelious/omen-rgb-linux)
   with `uv tool install git+https://github.com/arfelious/omen-rgb-linux.git`.
   Brightness of the keyboard is the F4 key, not the tool.

For colours without root, install `keyboard/70-omen-keyboard-rgb.rules` into `/etc/udev/rules.d/`
(it grants your session access to the lighting interfaces 03 and 04 only, not the key-event
interfaces) and run `udevadm control --reload && udevadm trigger --subsystem-match=hidraw`.
The PyPI `hidapi` package's default `hid` module uses libusb and fails with "open failed" when you
only have hidraw access; its `hidraw` module works. `keyboard/omen-rgb-hidraw` swaps the module:
`omen-rgb-hidraw ...` runs the CLI, `omen-rgb-hidraw --gui` the GUI.

Costs and side effects of `sleep_no_lps0=1`:

- Per the original write-up: S0ix residency drops from about 99% to about 96%, and the keyboard
  backlight stays lit during suspend unless an effect such as "ghosting" is used.
- **Loud fans during suspend.** The kernel no longer makes the LPS0 call, so the EC is never told
  that the system sleeps. The fans spin up loudly during s2idle and the laptop looks like it is
  still on, although the SoC does reach S0ix (about 95% here). Fix: `keyboard/omen-ec-suspend.sleep`,
  a system-sleep hook that sets the EC's "entering sleep" flag (`PECF`, a 1-bit field the
  firmware's own LPS0 handler would set) on `pre` and clears it on `post`. `install.sh` installs it;
  it does nothing unless `sleep_no_lps0` reads `Y`, the config has the PECF address, and the BIOS
  version matches. Tested: two short suspends (33 s and 82 s, 96% and 98% of the time in hardware sleep),
  fans silent, keyboard backlight and F2/F3/F4 fine after resume; and one full night (about 6 h 50 min,
  on the charger), with no spontaneous wake-ups and keyboard backlight, colours and screen brightness fine after
  resume. On the charger the fans keep turning slowly during suspend (quietly); they stop as soon as the
  charger is unplugged. The hardware-sleep counter could not confirm the residency for the night: it
  read 3234 s of about 24 700 s, which looks like the counter wrapping, not like real wake time. NOT tested: the
  firmware's other flag `PLED` (alone or together with `PECF`), which the firmware's handler also
  touches but this hook leaves alone.

**Undo:** remove the kernel parameter and the rules file; `sudo ./uninstall.sh` removes the suspend hook.

## Not a bug: GPU power limit reads 80 W

Not something this repo changes, only an explanation, measured on this machine (board 8D41,
RTX 5080 Laptop, NVIDIA open driver 595.x, kernel 7.0). On the `balanced` platform profile the
firmware holds the GPU at roughly 80-85 W; that is intended, not a Linux fault.
`powerprofilesctl set performance` (the platform profile handled by the in-kernel `hp-wmi` driver,
which supports this board) raises "Current Power Limit" to 175 W, and about 175 W was measured under
load. `power.default_limit` in `nvidia-smi --query-gpu` always shows 80 W, because it is only the
default field, not the active limit; read "Current Power Limit" in `nvidia-smi -q -d POWER`. If the
GPU still stays near 80 W on `performance`, check for a locked GPU clock (something having run
`nvidia-smi --lock-gpu-clocks`, e.g. a leftover service); here that lock, not the firmware, held the
card back.

```
nvidia-smi -q -d POWER | grep -i "power limit"
sudo nvidia-smi --reset-gpu-clocks
```

## Safety notes

- The brightness script writes one byte to a memory-mapped EC register through `/dev/mem`, as root,
  on every brightness step. The address comes from your firmware's ACPI tables via the detector. It
  only writes if the BIOS version matches the config and the firmware's own "EC owns the backlight"
  flag (ECOE) reads 1. Values are clamped to 2..200, the range the firmware itself uses.
- `/dev/mem` must be able to reach that address. Secure Boot / kernel lockdown blocks `/dev/mem`;
  this was tested with Secure Boot off. With lockdown active the script just logs that it cannot
  read the register and does nothing.
- Re-run the detector after every BIOS update.
- No warranty (see LICENSE). Read `brightness/omen-ec-backlight`; it is short.

## What does not work, and why

- `acpi_backlight=nvidia_wmi_ec` (tested): the firmware's WMI backlight method ignores the level
  passed by the caller and copies a value from the Intel graphics OpRegion, which the Linux i915
  driver never writes. The sysfs value changes, the panel does not.
- `acpi_backlight=video` (not tested here): the firmware's `_BCM` only forwards the request to the
  Intel graphics driver, which leads back to the same registers as `intel_backlight`.
- `i915.enable_dpcd_backlight`: the panel's DPCD advertises PWM-pin brightness only, no AUX
  control, so there is nothing to enable.
- `nvidia_0` and `intel_backlight` on their own: they change their own registers, which do not
  reach the EC-generated PWM.

Details and how to check each claim by hand: `docs/how-it-works.md`.

## Tests

```
python3 -m unittest discover -s tests -v    # detector parser, synthetic firmware snippets
sh tests/test_runtime.sh                    # brightness mapping, dry run, no hardware access
```

## Credits

- [mirco-g01/omen-max-linux-rgb-keyboard-control](https://github.com/mirco-g01/omen-max-linux-rgb-keyboard-control),
  `docs/modern-standby-fn-keys.md`: the modern-standby cause and the `sleep_no_lps0` fix.
- [arfelious/omen-rgb-linux](https://github.com/arfelious/omen-rgb-linux): keyboard colour tool.

## Licence

MIT, see LICENSE.

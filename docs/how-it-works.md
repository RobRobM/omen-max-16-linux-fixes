# How the brightness fix was found

All of this was observed on board 8D41, BIOS F.20, kernel 7.0. Check each step on your own machine.

## 1. Symptom

`/sys/class/backlight/` offers `intel_backlight` and `nvidia_0` (or others depending on
`acpi_backlight=`). Writing to them changes the values, the panel does not react. After boot or
resume the panel sits at half brightness.

## 2. The panel only takes PWM

Read the panel's DPCD over the DP AUX channel (needs `i915` debugfs or `drm_dp_aux_dev`, e.g.
`sudo dd if=/dev/drm_dp_aux0 bs=1 skip=$((0x700)) count=8 | xxd`). Offsets 0x701 = 0x83 and
0x702 = 0x81 advertise brightness control through the PWM pin only, with no AUX brightness
capability. So AUX/DPCD backlight (`i915.enable_dpcd_backlight`) cannot work.

## 3. Who makes the PWM

Decompile the ACPI tables:

```
sudo cat /sys/firmware/acpi/tables/DSDT > /tmp/DSDT      # copy to a scratch dir first
cd /tmp && iasl -d DSDT                                 # writes DSDT.dsl
grep -n "ECPW\|ECOE" DSDT.dsl
```

The relevant pieces:

- `OperationRegion (EWRM, SystemMemory, 0xFD400C00, 0x0100)` inside `Scope (\_SB.PC00.LPCB)`, with a
  `Field` that contains `ECOE` (1 bit) at byte 0xF4 bit 0 and `ECPW` (8 bit) at byte 0xF5.
  `Offset (0xNN)` entries set the byte position; every named or unnamed `, N,` entry advances by
  N bits. That walk is what `omen-ec-backlight-detect` does.
- `ECOE` reads 1: the EC owns the backlight.
- The WMI method `\_SB.PC00.AWMI.WMAA` (GUID 603E9613-EF25-4338-A3D0-C46177516DB7, the one
  `nvidia_wmi_ec_backlight` binds to) contains `ECPW = ^^^GFX0.CBL1 ...` (scaled by 2). It ignores
  the level the caller passes. `CBL1` is a field in the Intel graphics OpRegion. On Windows the
  Intel driver stores the requested level there. Linux i915 never does, so the method copies a
  stale value and `acpi_backlight=nvidia_wmi_ec` is useless.
- ECPW range 0..200; the firmware never goes below 2. After boot/resume it is 100.

## 4. Proof

As root, with `/dev/mem` accessible (Secure Boot / lockdown off):

```
busybox devmem 0xFD400CF4 8       # bit 0 should be 1
busybox devmem 0xFD400CF5 8       # current duty, e.g. 100
busybox devmem 0xFD400CF5 8 40    # panel dims at once
busybox devmem 0xFD400CF5 8 200   # full brightness
```

(Use the addresses printed by the detector for your machine; the ones above are those of the tested
BIOS F.20.)

## 5. The workaround

With `acpi_backlight=native` the kernel exposes `intel_backlight` and desktops use it. The udev rule
fires on every `add|change` of that device and runs `omen-ec-backlight`, which maps
`brightness/max_brightness` to 2..200 (rounded) and writes it to ECPW. A system-sleep hook repeats
that on `post`, because the firmware resets ECPW on resume. The script checks first: config present,
BIOS version equal to the one the config was made for, ECOE bit set, sysfs present; otherwise it
logs once per boot and exits.

## 6. Keyboard

See the README and the linked write-up by mirco-g01. In short: the LPS0 `_DSM` called on s2idle
entry makes the firmware put the Darfon keyboard MCU into host-handled mode. `acpi_x86.sleep_no_lps0=1`
stops the kernel from calling it; one full power-off clears the MCU state that is already stuck.
The lighting interfaces are USB interfaces 03 (vendor usage page FF01) and 04 (HID LampArray).

## 7. Side effect: loud fans in suspend, and the PECF hook

Skipping the LPS0 call also skips what the firmware does with it. In the DSDT, `\_SB.PEPD._DSM`
(Intel UUID c4eb40a0-6cd2-11e2-bcfd-0800200c9a66) handles the LPS0 functions:

- function 5 (entry): `\_SB.PC00.LPCB.PLED = One`, `GUAM (One)`, `\_SB.PC00.LPCB.PECF = One`
- function 6 (exit): `PECF = Zero`
- function 4 (screen on): `PLED = Zero`

`PECF` and `PLED` are 1-bit fields in `OperationRegion (H2RM, SystemMemory, 0xFD400600, 0x0100)`,
at byte offset 0x57, bit 0 (PECF) and bit 1 (PLED) on BIOS F.20. Without the call the EC does not
know the system sleeps: fans spin up loudly during s2idle, the laptop seems to stay on, yet the SoC
reaches S0ix. `omen-ec-suspend.sleep` sets only PECF (read-modify-write of the byte) on `pre` and
clears it on `post`. The detector derives address and bit the same way as for ECPW
(`grep -n "PECF\|PLED" DSDT.dsl`). By hand: `busybox devmem <PECF_ADDR> 8` before and after a suspend.

Measured: a 33 s suspend with 31.6 s in hardware sleep (about 96%), silent fans, and the keyboard
backlight plus F2/F3/F4 still working after resume. Not tested: PLED alone or together with PECF,
and a full night of suspend. If the detector finds no usable PECF it still writes the brightness
config and warns that the hook stays inactive.

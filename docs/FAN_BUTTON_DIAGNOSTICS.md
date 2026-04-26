# Fan and Button Diagnostics

This guide helps validate PWM fan control and physical button hotplug support on
the Orange Pi CM5 Base ImmortalWrt image.

Run the command-line checks over SSH as `root` on the router:

```sh
ssh root@192.168.8.1
```

## Quick LuCI Checks

Open LuCI at `https://192.168.8.1/`.

- `System -> Peripherals -> PWM fan` should show current fan readings when the
  `pwmfan` hwmon device is present.
- `System -> Peripherals -> Diagnostics` can collect a read-only debug report
  that includes button, module, device tree, fan, IR, and log state.
- `System -> Buttons` provides a focused editor for hotplug button scripts.

If a page reports that no device or script was found, continue with the SSH
checks below.

## PWM Fan Checklist

The CM5 Base fan support needs three layers to line up:

- Device tree contains the `pwm-fan` node.
- Kernel package `kmod-hwmon-pwmfan` is installed and `pwm_fan` is loaded.
- A hwmon entry named `pwmfan` appears under `/sys/class/hwmon/`.

Check the installed packages:

```sh
apk info | grep -E 'kmod-hwmon-pwmfan|luci-app-peripherals'
```

Expected:

```text
kmod-hwmon-pwmfan
luci-app-peripherals
```

Check the module and autoload file:

```sh
lsmod | grep -E '^pwm_fan '
ls -l /etc/modules.d/60-hwmon-pwmfan
```

Expected:

```text
pwm_fan ...
/etc/modules.d/60-hwmon-pwmfan
```

If the module is not loaded, load it manually and re-check:

```sh
modprobe pwm_fan
lsmod | grep -E '^pwm_fan '
```

Find the fan hwmon device:

```sh
for d in /sys/class/hwmon/hwmon*; do
	name="$(cat "$d/name" 2>/dev/null)"
	printf '%s %s\n' "$d" "$name"
done
```

Expected:

```text
/sys/class/hwmon/hwmonX pwmfan
```

Inspect current readings. Replace `hwmonX` with the matching directory:

```sh
cd /sys/class/hwmon/hwmonX
ls -l
cat name
cat pwm1 2>/dev/null
cat pwm1_enable 2>/dev/null
cat fan1_input 2>/dev/null
```

Typical values:

- `name` is `pwmfan`.
- `pwm1` is a value from `0` to `255`.
- `pwm1_enable` is usually `0`, `1`, or `2`, depending on driver mode.
- `fan1_input` is RPM if a tachometer signal is wired and exposed; it may be
  missing or `0` on fan setups without tach feedback.

Manual fan test:

```sh
cd /sys/class/hwmon/hwmonX
echo 255 > pwm1
echo 2 > pwm1_enable
sleep 5
echo 128 > pwm1
sleep 5
```

The fan should speed up at `255` and slow down at `128`. To return control to
thermal/automatic mode, use LuCI `System -> Peripherals -> PWM fan` and select
automatic mode, or reboot.

If the `pwmfan` device exists but the fan never spins, test for inverted PWM
polarity:

```sh
cd /sys/class/hwmon/hwmonX
echo 0 > pwm1
echo 2 > pwm1_enable
sleep 5
echo 255 > pwm1
sleep 5
echo 128 > pwm1
```

If `0` turns the fan on and `255` turns it off, the hardware control line is
inverted and the DTS `pwms` polarity must be changed to
`PWM_POLARITY_INVERTED`.

In LuCI, these checks are available as `Full-speed test`, `Inverted full-speed
test`, and `Stop fan` under `System -> Peripherals -> Cooling fan`.

If neither `0` nor `255` turns the fan on, check the physical layer before
changing software:

```sh
dmesg | grep -Ei 'pwm|fan|thermal'
cat /sys/kernel/debug/pwm 2>/dev/null || echo "debugfs pwm unavailable"
```

Also verify that the fan is connected to the CM5 Base fan header with the
expected polarity and voltage. A two-wire fan should normally spin if supplied
with its rated voltage directly; no tachometer wire is needed for PWM control.

Check the device tree from the running router:

```sh
tr '\0' '\n' < /proc/device-tree/model
find /proc/device-tree -name compatible -print | xargs grep -aH 'pwm-fan' 2>/dev/null
```

If no `pwm-fan` compatible entry exists, the running image does not contain the
fan DTS change or the board did not boot the expected device tree.

## Button Checklist

Physical buttons need:

- Device tree `gpio-keys` entries with supported `linux,code` values.
- `kmod-gpio-button-hotplug` installed and `gpio_button_hotplug` loaded.
- Executable scripts in `/etc/rc.button/`.

Check installed packages:

```sh
apk info | grep -E 'kmod-gpio-button-hotplug|luci-app-buttons|luci-app-peripherals'
```

Expected:

```text
kmod-gpio-button-hotplug
luci-app-buttons
luci-app-peripherals
```

Check loaded modules:

```sh
lsmod | grep -E 'gpio_button_hotplug|gpio_keys'
```

Expected:

```text
gpio_button_hotplug ...
gpio_keys ...
```

If `gpio_button_hotplug` is missing:

```sh
modprobe gpio_button_hotplug
lsmod | grep gpio_button_hotplug
```

Check editable button scripts:

```sh
ls -la /etc/rc.button/
```

Expected at minimum:

```text
-rwxr-xr-x ... wps
```

Scripts must be executable and names must match:

```text
[A-Za-z0-9._-]+
```

Fix permissions if needed:

```sh
chmod 0755 /etc/rc.button/*
```

Watch hotplug events while pressing the physical button:

```sh
logread -f
```

The default CM5 `wps` script logs a message when it runs. If your current image
has an older script without logging, add a temporary diagnostic script:

```sh
cp /etc/rc.button/wps /etc/rc.button/wps.bak
cat > /etc/rc.button/wps <<'EOF'
#!/bin/sh
logger -t button-test "ACTION=$ACTION BUTTON=$BUTTON SEEN=$SEEN"
return 0
EOF
chmod 0755 /etc/rc.button/wps
```

Then run `logread -f` and press `USERKEY`. Restore the original script after
testing:

```sh
mv /etc/rc.button/wps.bak /etc/rc.button/wps
chmod 0755 /etc/rc.button/wps
```

In another SSH session, you can also monitor input devices:

```sh
cat /proc/bus/input/devices
```

Check whether the kernel input device and hotplug module are present:

```sh
lsmod | grep -E 'gpio_keys|gpio_button_hotplug'
cat /proc/bus/input/devices
dmesg | grep -Ei 'gpio-keys|gpio_button|input'
```

The Orange Pi CM5 Base `USERKEY` is expected to map to `KEY_WPS_BUTTON`, which
uses the `/etc/rc.button/wps` script.

To test the script path without pressing the button:

```sh
ACTION=pressed BUTTON=wps SEEN=0 /etc/rc.button/wps
echo $?
```

Expected return code:

```text
0
```

## Infrared Checklist

The Orange Pi CM5 Base has an onboard IR receiver, but it is wired through PWM
input capture rather than a normal GPIO RC input. With the current upstream
RK3588 kernel binding, the onboard receiver is not expected to create
`/sys/class/rc/rc*`.

In LuCI, use `System -> Peripherals -> Infrared`:

- `Onboard IR receiver` should describe the PWM input-capture implementation.
- `PWM/counter capture diagnostics` will show Linux counter devices if a future
  kernel and DTB expose the raw capture block.
- `External RC devices` lists `/sys/class/rc/rc*` devices from separate
  supported receivers.

Over SSH, collect the same state:

```sh
ls -la /sys/class/rc 2>/dev/null || true
ls -la /sys/bus/counter/devices 2>/dev/null || true
ir-keytable 2>&1 || true
cat /etc/rc_maps.cfg
dmesg | grep -Ei 'ir|rc-core|pwm|counter' | tail -n 100
```

Expected onboard-only result on current images:

```text
No /sys/class/rc/rc* device for the onboard receiver.
```

That is not a failure by itself. It only becomes a failure if you attach an
external supported IR receiver and still do not get an `rc*` device.

## Common Failure Meanings

`No pwmfan device was found`

The package may be installed, but the running kernel did not create a `pwmfan`
hwmon device. Check the DTS, `pwm_fan` module, and `/sys/class/hwmon/` output.

`No editable script names under /etc/rc.button/`

The directory is empty, script names are invalid, or scripts are not executable.
Check `/etc/rc.button/` and ensure `wps` exists with mode `0755`.

Button press does nothing

Check `gpio_button_hotplug`, `gpio_keys`, the device tree key code, and whether
the script matching the button name exists under `/etc/rc.button/`.

`No external RC devices were found`

This is expected for the onboard CM5 Base IR receiver on current images. The
onboard receiver uses PWM input capture and is reported separately in the
Peripherals IR diagnostics. Check this only as an error for an attached external
IR receiver or overlay that should create `/sys/class/rc/rc*`.

LuCI page exists but RPC calls fail

Restart `rpcd` and `uhttpd` after package updates:

```sh
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

Then reload LuCI in the browser.

## Build Image Validation

Before flashing a newly built image, verify the manifest contains the required
packages:

```sh
grep -E '^(kmod-hwmon-pwmfan|kmod-gpio-button-hotplug|luci-app-peripherals|luci-app-buttons) ' \
  bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-xunlong_orangepi-cm5-base.manifest
```

Expected packages:

```text
kmod-gpio-button-hotplug
kmod-hwmon-pwmfan
luci-app-buttons
luci-app-peripherals
```

If the manifest is correct but the running router is missing files or modules,
the router is likely booting an older flashed image or a different boot device.

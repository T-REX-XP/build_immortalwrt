# Building ImmortalWrt Images on macOS

Use `scripts/build-immortalwrt-macos.sh` to build a dedicated device image from
any ImmortalWrt source checkout.

```sh
cd "/Users/t-rex-xp/Documents/ build_immortalwrt"

./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base
```

The script builds a Docker image, copies the source tree into Linux storage
inside the container, runs:

```text
feeds update -> feeds install -> make defconfig -> make download -> make
```

and copies artifacts to:

```text
/Users/t-rex-xp/Documents/immortalwrt/bin/targets/rockchip/armv8/
```

Repeated builds are cached by default:

- `/dl` is your source download cache.
- `/work` is a Docker named volume that preserves `build_dir/`, `staging_dir/`,
  `tmp/`, and feeds between runs.
- `/ccache` is a Docker named volume used by `CONFIG_CCACHE=y`.
- `scripts/feeds.conf.cm5` adds the `awgopenwrt` feed for AmneziaWG packages.
  The third-party `fantastic-packages` feed is optional — see README.md.
- The Dockerfile uses BuildKit cache mounts for apt metadata and downloaded
  `.deb` files.
- `/usr/local/go` in the builder image is used as the external Go bootstrap,
  which is needed for Go packages such as `tailscale` on Apple Silicon.
- The generated OpenWrt config uses a 512 MiB rootfs partition by default. Override with
  `IMMORTALWRT_ROOTFS_PARTSIZE` if you need a different size in MiB.

## Recommended CM5 Command

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared luci-app-peripherals luci-app-oled kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg cm5-button-scripts" \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl"
```

## CM5 Image Assumptions

- `luci-ssl` is part of the device package list, so the flashed image should
  expose LuCI through the standard OpenWrt web server after first boot.
- The LAN interface uses `192.168.8.1`; DHCP clients should receive
  `192.168.8.x` addresses from the normal LAN pool.
- `luci-app-peripherals` provides `System -> Peripherals` for infrared
  receiver/keymap management, PWM fan control, I2C bus scan, and module diagnostics.
- Physical button hotplug scripts ship in **cm5-button-scripts** (`/etc/rc.button/wps`,
  `BTN_2`). Handlers chain `hotplug-call button` so **luci-app-oled** receives presses.
  OLED menu button mapping is in **Services -> OLED** (`menu_nav_button`,
  `menu_select_button`). Optional feed package `luci-app-buttons` is not in the CM5 image.
- `luci-app-oled` provides **Services -> OLED** for `oledd` menu mode, boot splash,
  I2C/RST, and service control on `/dev/i2c-7`.
- **Blocky**, **luci-app-security-guide**, and **Docker** are not in the default CM5
  `DEVICE_PACKAGES` profile — install from the `openwrt-packages` feed if needed.
- `docs/FAN_BUTTON_DIAGNOSTICS.md` contains the manual SSH and LuCI validation
  steps for PWM fan control and button hotplug support.
- The onboard CM5 Base IR receiver is wired through PWM input capture, not a
  normal GPIO RC receiver. The Peripherals IR page shows this as the default
  onboard implementation, reports PWM/counter capture diagnostics when
  available, and keeps `/etc/rc_maps.cfg` editing for external receivers that
  provide a supported `/sys/class/rc/rc*` device.
- The CM5 kernel DTS enables eMMC through `sdhci`, and U-Boot is patched to try
  eMMC before microSD. The generated image is suitable for flashing to either
  microSD or eMMC; remove the microSD card after flashing eMMC if you want the
  board to boot from eMMC.

## Cache Control

Use the defaults for normal rebuilds. To reset build state after large branch
changes or strange compile errors:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --reset-work-cache
```

Reset compiler cache too:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --reset-work-cache \
  --reset-ccache
```

Disable persistent work cache for a one-off clean build:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --no-work-cache \
  --no-ccache
```

## Debugging

To validate profile selection without compiling:

```sh
IMMORTALWRT_STOP_AFTER_CONFIG=1 \
./scripts/build-immortalwrt-macos.sh --source /Users/t-rex-xp/Documents/immortalwrt
```

To get a simpler build log:

```sh
IMMORTALWRT_MAKE_JOBS=1 \
./scripts/build-immortalwrt-macos.sh --source /Users/t-rex-xp/Documents/immortalwrt
```

The default log is written to:

```text
<out-dir>/immortalwrt-build.log
```

where `<out-dir>` defaults to the source tree's `bin/` directory.

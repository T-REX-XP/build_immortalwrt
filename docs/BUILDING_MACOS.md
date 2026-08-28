# Building ImmortalWrt Images on macOS

Use `scripts/build-immortalwrt-macos.sh` to build a dedicated device image from
any ImmortalWrt source checkout.

```sh
cd "/Users/t-rex-xp/Documents/build_immortalwrt"

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

**Custom feed:** if `../openwrt-packages/feeds` exists next to the source tree
(sibling layout under `Documents/`), the wrapper mounts it automatically as
`openwrt_packages`. Override with `--custom-feed /path/to/openwrt-packages/feeds`.

## Recommended CM5 command

First build or after `--reset-work-cache`:

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared luci-app-peripherals luci-app-oled luci-app-mcu-display cm5-button-scripts kmod-input-adc-keys kmod-button-hotplug kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg blocky luci-app-blocky" \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl"
```

Routine rebuild (warm `/work`, `/dl`, `/ccache`):

```sh
IMMORTALWRT_SKIP_DOWNLOAD=1 \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl" \
  --no-build-image
```

`build-inner.sh` always merges `cm5-button-scripts`, `kmod-input-adc-keys`,
`kmod-button-hotplug`, and `luci-app-mcu-display` into `IMMORTALWRT_EXPECT_PACKAGES`
even when you omit them from the env var.

## Repeated builds and caches

- `/dl` — source tarball cache (`--dl-dir`, default: source `dl/`).
- `/work` — Docker named volume: `build_dir/`, `staging_dir/`, `tmp/`, and
  (by default) feed checkouts between runs.
- `/ccache` — compiler cache (`CONFIG_CCACHE=y`, Go build cache under
  `/ccache/go-build`).
- `scripts/feeds.conf.cm5` — minimal feeds: ImmortalWrt `packages`, `luci`,
  AmneziaWG `awgopenwrt`, plus auto-linked `openwrt_packages`. Optional
  `fantastic-packages` — see [README.md](../README.md).
- Builder Dockerfile — BuildKit apt cache mounts; `/usr/local/go` bootstrap for
  Apple Silicon Go packages (`tailscale`, `cloudflared`, `blocky`, …).
- Default rootfs partition: **512 MiB** (`IMMORTALWRT_ROOTFS_PARTSIZE`).

See [cm5-build-speed-and-cache-report.md](cm5-build-speed-and-cache-report.md)
for timing estimates, when to reset caches, and log rotation.

## CM5 image assumptions

- **LuCI:** `luci-ssl` in `DEVICE_PACKAGES`; web UI on `192.168.8.1` after first boot.
- **Custom feed apps:** `luci-app-oled`, `luci-app-peripherals`, `luci-app-mcu-display`,
  `cm5-button-scripts` (requires sibling `openwrt-packages` or `--custom-feed`).
- **OLED:** **Services → OLED** — `oledd` on `/dev/i2c-7`, boot splash, button mapping.
- **MCU display:** **Services → MCU display** — ESP32 over debug UART (`ttyS2` default).
- **Peripherals:** **System → Peripherals** — PWM fan, I2C scan, onboard IR via PWM
  capture. `ir-keytable` (`v4l-utils`) is **not** in the image; install with
  `apk add v4l-utils` only if you add an external GPIO IR receiver.
- **Buttons:** `cm5-button-scripts` + **luci-app-oled** hotplug chain (`/etc/rc.button/wps`, …).
- **VPN / overlay:** WireGuard, AmneziaWG, Tailscale, Cloudflared.
- **DNS:** **blocky** + **luci-app-blocky** (from `openwrt_packages` feed).
- **Not in default image:** yggdrasil, luci-app-security-guide, Docker, SQM, travelmate,
  speedtest, SMB, DLNA, statistics — install from feeds when needed.
- **eMMC / microSD:** same image; U-Boot tries eMMC first. Remove microSD after
  flashing eMMC to boot from eMMC.
- **Validation:** [FAN_BUTTON_DIAGNOSTICS.md](FAN_BUTTON_DIAGNOSTICS.md) — fan, buttons, IR.

### CM5 packages explicitly disabled at build time

`build-inner.sh` turns these off in `.config`, prunes yggdrasil from feed trees on CM5,
and fails the build if forbidden packages appear in the manifest (guards stale Docker
work cache as well as keeping the image slim):

| Category | Packages |
|----------|----------|
| Containers / media | `docker*`, `aria2`, `transmission*`, `ksmbd*`, `minidlna`, `collectd`, `luci-app-statistics` |
| Optional feed apps | `luci-app-security-guide`, `speedtest-go`, `luci-app-speedtest`, `yggdrasil`, `luci-proto-yggdrasil` |
| Other | `travelmate`, `pbr`, `watchcat`, `fwknopd`, `privoxy`, `sqm-scripts`, … |

`v4l-utils` / `libevdev` are not disabled here — they are omitted because
`luci-app-peripherals` no longer depends on `v4l-utils` (see `openwrt-packages` feed).
Install `v4l-utils` on-router only when using an external GPIO IR receiver.

## Cache control

Use defaults for normal rebuilds. **Avoid `--reset-work-cache` on every run** — it
forces a multi-hour cold compile.

Reset work tree after branch/platform changes or `Missing kernel version/hash file`:

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

One-off clean build without persistent volumes:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --no-work-cache \
  --no-ccache
```

## Debugging

Validate profile selection without compiling:

```sh
IMMORTALWRT_STOP_AFTER_CONFIG=1 \
./scripts/build-immortalwrt-macos.sh --source /Users/t-rex-xp/Documents/immortalwrt
```

Simpler build log:

```sh
IMMORTALWRT_MAKE_JOBS=1 \
./scripts/build-immortalwrt-macos.sh --source /Users/t-rex-xp/Documents/immortalwrt
```

Default log (append mode):

```text
<out-dir>/immortalwrt-build.log
```

`<out-dir>` defaults to the source tree's `bin/` directory. Archive when large —
see the speed report.

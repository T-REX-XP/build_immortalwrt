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
- The generated OpenWrt config uses a 512 MiB rootfs partition by default. This
  leaves enough ext4 space for Docker and can be overridden with
  `IMMORTALWRT_ROOTFS_PARTSIZE`.

## Recommended CM5 Command

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared luci-app-peripherals luci-app-oled luci-app-buttons kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg cm5-button-scripts" \
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
- `blocky` installs `/etc/blocky/config.yml` at image build time. On **first boot
  only**, `/etc/uci-defaults/90-blocky-enable` enables and starts Blocky when
  `/etc/init.d/blocky` exists and the YAML is non-empty, then applies **`dnsmasq`
  → Blocky** (`blocky-dnsmasq-sync enable`) so DHCP clients use filtering without extra setup.
- Blocky listens on DNS port `5353` by default; HTTP/API (and Prometheus metrics)
  use port `4000`. After first boot you can change forwarding via LuCI **Services → Blocky DNS → Configuration → Router DNS integration** or `/usr/sbin/blocky-dnsmasq-sync`. See the repo **README.md** Blocky section for troubleshooting (“IP ping works, DNS does not”).
- Prometheus metrics are enabled at `/metrics` on the same HTTP/API listener so
  the LuCI Blocky dashboard can show overview counters after first boot.
- `luci-app-security-guide` provides a static `Network -> Security Guide` page
  with external links for DNS leak, IP, browser leak, ad-block, IPv6, TLS, and
  firewall exposure checks.
- `luci-app-peripherals` provides the `System -> Peripherals` UI for infrared
  receiver/keymap management, PWM fan control, and module diagnostics. Its
  debug report still includes button state for troubleshooting.
- `luci-app-buttons` provides a focused `System -> Buttons` UI for managing
  hotplug scripts under `/etc/rc.button/`, similar in placement to the standard
  LED configuration page.
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

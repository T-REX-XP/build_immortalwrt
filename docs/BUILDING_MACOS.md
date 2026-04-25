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
- `scripts/feeds.conf.cm5` adds the third-party `awgopenwrt` feed for
  AmneziaWG packages.
- The Dockerfile uses BuildKit cache mounts for apt metadata and downloaded
  `.deb` files.
- `/usr/local/go` in the builder image is used as the external Go bootstrap,
  which is needed for Go packages such as `tailscale` on Apple Silicon.
- The generated OpenWrt config uses a 512 MiB rootfs partition by default. This
  leaves enough ext4 space for Docker and can be overridden with
  `IMMORTALWRT_ROOTFS_PARTSIZE`.

## Recommended CM5 Command

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared adblock luci-app-adblock blocky luci-app-blocky luci-app-security-guide luci-app-peripherals luci-app-buttons speedtest-go luci-app-speedtest transmission-daemon luci-app-transmission docker dockerd luci-app-docker luci-app-dockerman kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg" \
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
- `blocky` installs `/etc/blocky/config.yml` at image build time. The first boot
  script `/etc/uci-defaults/90-blocky-enable` only enables and starts the
  service when `/etc/init.d/blocky` is executable and the config file is
  present and non-empty.
- Blocky listens on DNS port `5353` by default, while its HTTP/API endpoint uses
  port `4000`. This lets Blocky start without fighting `dnsmasq` for port `53`;
  clients will only use Blocky automatically if DNS forwarding is configured
  separately, such as forwarding `dnsmasq` to `127.0.0.1#5353`.
- Prometheus metrics are enabled at `/metrics` on the same HTTP/API listener so
  the LuCI Blocky dashboard can show overview counters after first boot.
- `luci-app-security-guide` provides static `Network -> Security Guide` and
  `Status -> Security Guide` pages with external links for DNS leak, IP,
  browser leak, ad-block, IPv6, TLS, and firewall exposure checks.
- `luci-app-peripherals` provides the `System -> Peripherals` UI for button
  scripts, infrared receiver/keymap management, PWM fan control, and module
  diagnostics.
- `luci-app-buttons` provides a focused `System -> Buttons` UI for managing
  hotplug scripts under `/etc/rc.button/`, similar in placement to the standard
  LED configuration page.
- `docs/FAN_BUTTON_DIAGNOSTICS.md` contains the manual SSH and LuCI validation
  steps for PWM fan control and button hotplug support.
- `speedtest-go` and `luci-app-speedtest` provide router-side internet speed
  testing from `Network -> Speed Test` and `Status -> Speed Test`.
- The onboard CM5 Base IR receiver is not expected to create a
  `/sys/class/rc/rc*` device with the current upstream kernel. The hardware needs
  PWM input-capture support that is not available in the current PWM DT binding
  and driver, so the Peripherals IR page is mainly useful for future support or
  external receivers that provide a supported RC device.
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

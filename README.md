# macOS ImmortalWrt Builder

This repository contains a Docker-based build wrapper for macOS. It accepts an
ImmortalWrt source tree from anywhere on disk, copies it into a Linux filesystem
inside the container, selects one target device profile, builds, and copies the
firmware artifacts back to the host.

The default profile is the Orange Pi CM5 Base device:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base
```

Artifacts are copied to:

```text
/Users/t-rex-xp/Documents/immortalwrt/bin/targets/rockchip/armv8/
```

## Why Docker on macOS

ImmortalWrt/OpenWrt needs GNU tools and a case-sensitive filesystem. The host
script uses Docker Desktop to build on Linux storage (`/work/immortalwrt`) while
keeping your source tree on macOS. This avoids the usual macOS failures around
Apple `make`, BSD coreutils, and case-insensitive folders.

## Common Options

Use another source tree:

```sh
./scripts/build-immortalwrt-macos.sh --source /path/to/immortalwrt
```

Build another profile:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --target rockchip \
  --subtarget armv8 \
  --device xunlong_orangepi-cm5-base
```

Use persistent caches outside the source tree:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --dl-dir "$HOME/.cache/immortalwrt-dl" \
  --out-dir "$HOME/immortalwrt-images"
```

By default, repeated builds also use Docker named volumes for the Linux work
tree and compiler cache:

```text
/work    -> preserves build_dir/, staging_dir/, tmp/, feeds/
/ccache  -> compiler cache, enabled with CONFIG_CCACHE=y
```

Reset those caches when changing branches heavily or after suspicious build
state:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --reset-work-cache \
  --reset-ccache
```

Stop after `make defconfig`:

```sh
IMMORTALWRT_STOP_AFTER_CONFIG=1 \
./scripts/build-immortalwrt-macos.sh --source /path/to/immortalwrt
```

Build with one job for easier logs:

```sh
IMMORTALWRT_MAKE_JOBS=1 \
./scripts/build-immortalwrt-macos.sh --source /path/to/immortalwrt
```

Use the source tree's full `feeds.conf.default` instead of the minimal CM5 feed
list:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --all-feeds
```

## Files

- `scripts/build-immortalwrt-macos.sh`: host entry point.
- `scripts/Dockerfile`: Ubuntu build environment for Docker Desktop.
- `scripts/build-inner.sh`: container-side build workflow.
- `scripts/feeds.conf.cm5`: minimal package + LuCI feeds for the CM5 build.
- `scripts/verify-kernel-modules.sh`: checks that the built kernel and staged
  module directory use the same version.
- `docs/BUILDING_MACOS.md`: extra usage notes and debugging commands.

## Notes

- The source tree is mounted read-only and copied into `/work/immortalwrt`; build
  products go to the `--out-dir`.
- The download cache is mounted at `/dl` and linked as `dl/` inside the copied
  tree, so repeated builds reuse source tarballs.
- `scripts/feeds.conf.cm5` includes the extra `awgopenwrt` feed for AmneziaWG
  packages in addition to ImmortalWrt `packages` and `luci`.
- The default `/work` Docker volume is much faster than rebuilding from a fresh
  container because OpenWrt's `build_dir`, `staging_dir`, `tmp`, and feeds clones
  survive between runs.
- The builder Dockerfile uses BuildKit cache mounts for apt package metadata and
  downloaded `.deb` files, so rebuilding the builder image is quicker too.
- The builder image includes `/usr/local/go` and the generated OpenWrt config
  points `CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT` at it. This avoids building
  `golang-bootstrap`, which is not supported on Linux arm64 Docker hosts.
- The generated config sets `CONFIG_TARGET_ROOTFS_PARTSIZE=512` by default so
  the Docker-enabled CM5 image has enough ext4 rootfs space. Override it with
  `IMMORTALWRT_ROOTFS_PARTSIZE` if you need a different size in MiB.
- Set `IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared adblock luci-app-adblock blocky luci-app-blocky luci-app-security-guide luci-app-peripherals transmission-daemon luci-app-transmission docker dockerd luci-app-docker luci-app-dockerman kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg"` if you want
  the build to fail when those packages are missing from the final manifest.

## Image Assumptions

- The CM5 image includes `luci-ssl`, so LuCI and `uhttpd` are expected to be
  available after first boot.
- The default LAN address is `192.168.8.1`; DHCP clients on LAN should receive
  `192.168.8.x` addresses from the normal OpenWrt LAN DHCP pool.
- The `blocky` package installs `/etc/blocky/config.yml` into the image. The
  first-boot script at `/etc/uci-defaults/90-blocky-enable` only enables and
  starts Blocky when `/etc/init.d/blocky` exists and that config file is
  non-empty.
- The default Blocky config listens for DNS on port `5353` and HTTP/API on port
  `4000`. This avoids a DNS port conflict with `dnsmasq`, but LAN clients will
  not automatically use Blocky unless DNS forwarding is configured separately,
  for example by forwarding `dnsmasq` to `127.0.0.1#5353`.
- The default Blocky config enables Prometheus metrics at `/metrics` on the
  same HTTP/API listener so `luci-app-blocky` can show overview counters without
  requiring a separate metrics service.
- The image includes `luci-app-security-guide`, a static LuCI page under
  `Network -> Security Guide` with external links for DNS leak, IP, WebRTC,
  ad-block, IPv6, TLS, and firewall exposure checks.
- The image includes `luci-app-peripherals` under `System -> Peripherals` for
  button script editing, infrared receiver/keymap management, PWM fan control,
  and module diagnostics.
- The kernel DTS enables the CM5 eMMC controller (`sdhci`) and the U-Boot build
  is patched to try eMMC before microSD. The same generated image can be written
  to either a microSD card or the CM5 eMMC; remove the microSD card after
  flashing eMMC if you want to boot from eMMC.

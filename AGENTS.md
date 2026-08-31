# Agent guide — build_immortalwrt

Docker-based ImmortalWrt build wrapper for **macOS**. Accepts an ImmortalWrt source tree from anywhere on disk, builds inside Linux storage in Docker, and copies firmware artifacts back to the host.

Default target: **Orange Pi CM5 Base** (`xunlong_orangepi-cm5-base`, `rockchip/armv8`).

## Repository layout

```text
scripts/
  build-immortalwrt-macos.sh   # Host entry point (run this)
  build-inner.sh               # Container-side workflow
  Dockerfile                   # Ubuntu builder for Docker Desktop
  feeds.conf.cm5               # Minimal CM5 feeds (packages, luci, awgopenwrt)
  verify-kernel-modules.sh     # Post-build kernel/module version check
docs/
  BUILDING_MACOS.md            # Usage and debugging
  FAN_BUTTON_DIAGNOSTICS.md    # PWM fan and button validation
```

## Default build

```sh
cd "/Users/t-rex-xp/Documents/ build_immortalwrt"

./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base
```

Artifacts:

```text
<source>/bin/targets/rockchip/armv8/
```

Example: `immortalwrt-rockchip-armv8-xunlong_orangepi-cm5-base-ext4-sysupgrade.img.gz`

## Why Docker on macOS

ImmortalWrt needs GNU tools and a case-sensitive filesystem. The script:

1. Mounts the source tree **read-only** at `/src`
2. **rsync** copies into `/work/immortalwrt` (Linux filesystem)
3. Runs feeds → defconfig → download → make inside the container
4. Copies `bin/` artifacts to `--out-dir` (default: source `bin/`)

Avoids Apple `make`, BSD coreutils, and case-insensitive macOS folder issues.

## Development rules

1. **Edit build logic** in `scripts/build-inner.sh` or `build-immortalwrt-macos.sh` — not ad-hoc host `make` in the source tree on macOS.
2. **Source tree** (`immortalwrt/`) holds device profiles, DTS patches, base-files — edit there for image content.
3. **Custom packages** live in sibling `openwrt-packages/feeds` — auto-mounted when present, or pass `--custom-feed`.
4. **Cache resets** — use `--reset-work-cache` after branch switches, platform changes, or `Missing kernel version/hash file` errors.
5. **Apple Silicon** — default `linux/arm64` Docker platform; do not switch to `linux/amd64` without `--reset-work-cache`.
6. **Commits** — only when the user explicitly asks.

## Persistent caches (default)

| Mount | Purpose |
|-------|---------|
| `/dl` | Source tarball download cache (`--dl-dir`) |
| `/work` | Docker volume: `build_dir/`, `staging_dir/`, `tmp/`, feeds |
| `/ccache` | Compiler cache (`CONFIG_CCACHE=y`) |

Reset when build state is suspicious:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --reset-work-cache \
  --reset-ccache
```

## Key environment variables

| Variable | Purpose |
|----------|---------|
| `IMMORTALWRT_MAKE_JOBS` | Parallel make jobs (use `1` for readable logs) |
| `IMMORTALWRT_STOP_AFTER_CONFIG` | Stop after `make defconfig` (profile validation) |
| `IMMORTALWRT_EXPECT_PACKAGES` | Fail build if packages missing from manifest |
| `IMMORTALWRT_ROOTFS_PARTSIZE` | Rootfs partition MiB (default `512` for Docker CM5) |
| `IMMORTALWRT_DOCKER_PLATFORM` | `linux/arm64` (default on Apple Silicon) or `linux/amd64` |
| `IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE` | Set via `--allow-feed-failure` |

## Feeds

Default: `scripts/feeds.conf.cm5` — ImmortalWrt `packages`, `luci`, AmneziaWG `awgopenwrt`.

- **`--all-feeds`** — use source tree's full `feeds.conf.default`
- **`--custom-feed DIR`** — append `src-link openwrt_packages` (must contain `packages/` and `luci/`)
- Auto-detects sibling `../openwrt-packages/feeds` next to the source tree

**fantastic-packages** is **not** enabled by default (faster builds, fewer upstream failures).

## CM5 image assumptions

- LAN: `192.168.8.1/24`, DHCP pool `192.168.8.x`
- `luci-ssl`, peripherals, **luci-app-oled** (oledd menu), **cm5-button-scripts**, **blocky** / **luci-app-blocky**, AmneziaWG in profile (no Docker, travelmate, luci-app-buttons, speedtest, SMB, DLNA, statistics, SQM, PBR, watchcat, fwknopd, privoxy)
- eMMC + microSD: same image; U-Boot tries eMMC first
- Go bootstrap: `/usr/local/go` in builder image (avoids `golang-bootstrap` on arm64)

## Related repositories

| Repo | Role |
|------|------|
| `immortalwrt/` | Source tree, device profile, kernel DTS, base-files |
| `openwrt-packages/` | Custom feed (blocky, luci-app-*, cm5-button-scripts) |
| `immortal_opi_cm5/` | DTS export patches, docker compose for dev |

## Project skills

| Skill | When to use |
|-------|-------------|
| `immortalwrt-macos-build` | Running builds, caches, Docker platform, debugging |
| `cm5-device-image` | CM5 profile, expected packages, eMMC, fan/button diagnostics |
| `immortalwrt-feeds-setup` | feeds.conf.cm5, custom-feed, fantastic-packages, all-feeds |
| `blocky-dns-cm5` | Blocky ports, dnsmasq integration, Wi-Fi DNS troubleshooting |
| `openwrt-mcp-ssh` | Post-flash / live CM5 checks via MCP or SSH (skill in `openwrt-packages/`) |

Cross-repo: **mcu-display-cm5** in `openwrt-packages/.cursor/skills/` (orig C mcudd, LuCI sidecar, ESP32 UART). **esp32-cm5-router-fw** in `esp32-smartdisplay-demo`. Peripherals I2C/fan: **oled-peripherals-cm5**.

## References

- [README.md](README.md)
- [docs/BUILDING_MACOS.md](docs/BUILDING_MACOS.md)
- [docs/FAN_BUTTON_DIAGNOSTICS.md](docs/FAN_BUTTON_DIAGNOSTICS.md)
- [openwrt-packages AGENTS.md](../openwrt-packages/AGENTS.md) — custom feed development

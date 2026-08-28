# CM5 ImmortalWrt macOS build — log analysis & speed report

**Generated:** 2026-08-28  
**Last revised:** 2026-08-28 (Meson/`libevdev` fix via `luci-app-peripherals` feed only)  
**Device:** `xunlong_orangepi-cm5-base` (`rockchip/armv8`)  
**Builder:** `scripts/build-immortalwrt-macos.sh` (Docker on Apple Silicon, `linux/arm64`)

## Status

| Item | State |
|------|--------|
| Aug 28 build with `--reset-work-cache` | **Failed** on stale `libevdev` / Meson mismatch |
| Fix in tree | `luci-app-peripherals` no longer pulls `v4l-utils` (drops `libevdev` build chain) |
| Next step | Rebuild **without** `--reset-work-cache`; use `--no-build-image` + `IMMORTALWRT_SKIP_DOWNLOAD=1` if caches are warm |
| Last successful CM5 image on disk | **2026-07-24** (`immortalwrt-rockchip-armv8-xunlong_orangepi-cm5-base-ext4-sysupgrade.img.gz`, 38 MB) |

Logs analyzed:

| Log | Size | Notes |
|-----|------|-------|
| `immortalwrt/build-cm5-20260828-113531.log` | ~4.5 MB | Failed run (see above) |
| `immortalwrt/bin/immortalwrt-build.log` | ~524 MB | Append-only mixed history — rotate periodically |

---

## Executive summary

**Do not use `--reset-work-cache` for routine rebuilds.** Reserve it for branch/platform
switches, stale feed/kernel hash errors, or switching Docker platform
(`linux/arm64` ↔ `linux/amd64`).

| Build type | Typical wall time (CM5, M-series Mac) | Network |
|------------|----------------------------------------|---------|
| Incremental (warm `/work` + `/dl` + `/ccache`) | **15–45 min** | Minimal |
| Partial cold (work reset, warm `/dl`) | **1–2 h** | Moderate |
| Full cold (`--reset-work-cache --reset-ccache`, empty `/dl`) | **2–4+ h** | Heavy (multi-GB) |

---

## Failure analysis (2026-08-28, historical)

### Command

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --custom-feed /Users/t-rex-xp/Documents/openwrt-packages/feeds \
  --device xunlong_orangepi-cm5-base \
  --reset-work-cache
```

(`--custom-feed` is optional when `../openwrt-packages/feeds` exists next to the source tree.)

### Root cause

Stale Meson build directory for `libevdev` after host `tools/meson` upgraded (1.6.1 → 1.11.2).
Package was selected because `luci-app-peripherals` depended on `v4l-utils` → `libevdev` /
`libudev-zero`.

### Fix (in tree)

**`luci-app-peripherals`** — removed `+v4l-utils` from `LUCI_DEPENDS`. That was the only
CM5 path into `v4l-utils` → `libevdev` / `libudev-zero`. The LuCI app already handles
missing `ir-keytable`.

External GPIO IR: `apk add v4l-utils` from the standard ImmortalWrt feed when needed.

No `build-inner.sh` change is required for this — the existing CM5 disable list only covers
optional stacks (Docker, blocky, …) that `make defconfig` might otherwise enable from cache.

### When a full reset *is* appropriate

| Symptom | Action |
|---------|--------|
| `Missing kernel version/hash file` | `--reset-work-cache` |
| Stale feeds after adding/removing feed | `--reset-work-cache` |
| Switched `linux/arm64` ↔ `linux/amd64` | `--reset-work-cache` once |
| Strange host-tool / parallel make corruption | `--reset-work-cache --reset-ccache` |
| Single package build failure after upgrade | Delete `build_dir/target-*/<pkg>-*` in `/work` only |
| CM5 `libevdev` / `v4l-utils` | **Not selected** — fixed in `luci-app-peripherals` feed |

---

## CM5 packages disabled in `build-inner.sh`

Explicit `./scripts/config --disable PACKAGE_*` after `make defconfig`:

```text
docker dockerd docker-compose luci-app-docker luci-app-dockerman
travelmate luci-app-travelmate
aria2 webui-aria2 luci-app-aria2
transmission transmission-daemon transmission-cli transmission-remote
transmission-web-control luci-app-transmission
luci-app-security-guide
pbr luci-app-pbr
watchcat luci-app-watchcat
fwknopd luci-app-fwknopd
privoxy luci-app-privoxy
speedtest-go luci-app-speedtest
ksmbd-server luci-app-ksmbd
minidlna luci-app-minidlna
collectd luci-app-statistics
sqm-scripts luci-app-sqm
```

---

## Cache layers (macOS wrapper)

```text
Host macOS                Docker container (/work/immortalwrt)
─────────────────         ─────────────────────────────────────
immortalwrt/ (ro /src) → rsync → /work/immortalwrt
immortalwrt/dl/        → mount → /dl          (source tarballs, ~3.9 GB)
Docker volume work     → /work               (build_dir, staging_dir, tmp, feeds*)
Docker volume ccache   → /ccache             (CONFIG_CCACHE=y, default max 20G)
Builder image apt/go   → BuildKit cache      (apt lists + Go bootstrap tarball)
```

\* `IMMORTALWRT_CACHE_FEEDS=1` (default): `feeds/` and `package/feeds/` are excluded
from rsync so feed git trees persist in `/work`. Source changes still sync; indices
refresh via `./scripts/feeds update`.

| Layer | Persists | Saves |
|-------|----------|-------|
| `/dl` (`--dl-dir`) | Yes (host) | Kernel, GCC, LuCI, Go module tarballs |
| `/work` | Yes unless `--reset-work-cache` | Toolchain, `build_dir/`, `staging_dir/` |
| `/ccache` | Yes unless `--reset-ccache` | C/C++ objects; Go via `/ccache/go-build` |
| `--no-build-image` | Builder image on disk | Skips Ubuntu apt + Go bootstrap download |
| BuildKit apt mounts | Image layers | Faster Dockerfile rebuilds |

### Cost of `--reset-work-cache` (observed 2026-08-28)

1. Docker image build (Go bootstrap download)
2. Full `feeds update -a`
3. `make download` for entire profile
4. Host tools + toolchain from scratch
5. Kernel compile (~85–155 s wall)
6. Failed after ~113 package `time:` entries — never reached image assembly

---

## Slowest steps (from logs)

| Step | Wall time | Notes |
|------|-----------|-------|
| `target/linux/compile` | **85–155 s** | Kernel 6.18 + CM5 DTS |
| `tools/cmake/compile` | ~95 s | Host tool; cold only |
| `tools/elfutils/compile` | ~58 s | Host tool; cold only |
| Go daemons | varies | `tailscale`, `cloudflared`, `yggdrasil` — use Go build cache |

---

## Network traffic reduction

### Already in place

- Persistent `/dl` on host (~**3.9 GB** today)
- Minimal `feeds.conf.cm5` (no `fantastic-packages` by default)
- Cached feed clones in `/work`
- CM5 `.config` disables unpublished apk repos (`awgopenwrt`, `openwrt_packages`); runtime fix in `97-cm5-apk-feeds`

### Recommended practices

1. **Dedicated download cache**

   ```sh
   --dl-dir "$HOME/.cache/immortalwrt-dl"
   ```

2. **Skip redundant downloads** (warm `/work`, no new packages in profile)

   ```sh
   IMMORTALWRT_SKIP_DOWNLOAD=1 ./scripts/build-immortalwrt-macos.sh ...
   ```

3. **Skip Docker image rebuild**

   ```sh
   ./scripts/build-immortalwrt-macos.sh --no-build-image ...
   ```

4. **Avoid `--reset-work-cache`** unless necessary.

5. **Single-package iteration** (after one full profile build, inside container):

   ```sh
   make package/feeds/openwrt_packages/luci-app-oled/compile V=s
   make package/feeds/openwrt_packages/luci-app-oled/install V=s
   ```

6. **Feeds scope** — `build-inner.sh` runs `./scripts/feeds update -i openwrt_packages` for custom feed only; full `update -a` still runs once per build unless `IMMORTALWRT_SKIP_FEEDS_UPDATE=1`.

---

## Parallelism and logging

| Variable | Default | Recommendation |
|----------|---------|----------------|
| `IMMORTALWRT_MAKE_JOBS` | `nproc` | `1` only when debugging |
| `IMMORTALWRT_PREP_MAKE_JOBS` | `nproc` | Rarely needs tuning |
| `V=s` | on | Keep for post-mortems |

Rotate the append-only log when it grows large:

```sh
mv immortalwrt/bin/immortalwrt-build.log \
   "immortalwrt/bin/immortalwrt-build-$(date +%Y%m%d-%H%M%S).log"
```

---

## Suggested wrapper improvements (future)

Not implemented yet:

1. **`--clean-package PKG`** — `rm -rf build_dir/target-*/$PKG-*` before `make`.
2. **Log rotation** — truncate `/out/immortalwrt-build.log` above a size threshold.
3. **Auto `IMMORTALWRT_SKIP_DOWNLOAD=1`** when work cache warm and profile unchanged.
4. **Build timing footer** — top-N slow `time:` lines at end of run.

---

## Quick reference — CM5 rebuild

```sh
cd "/Users/t-rex-xp/Documents/ build_immortalwrt"

# Routine rebuild (recommended)
IMMORTALWRT_SKIP_DOWNLOAD=1 \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl" \
  --no-build-image

# Profile check only
IMMORTALWRT_STOP_AFTER_CONFIG=1 \
  ./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base
```

Expected artifact:

```text
immortalwrt/bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-xunlong_orangepi-cm5-base-ext4-sysupgrade.img.gz
```

---

## Related docs

- [BUILDING_MACOS.md](BUILDING_MACOS.md) — wrapper usage, CM5 assumptions, cache flags
- [../README.md](../README.md) — environment variables, Blocky, Wi-Fi, fantastic-packages
- [FAN_BUTTON_DIAGNOSTICS.md](FAN_BUTTON_DIAGNOSTICS.md) — on-device fan/button checks
- [../../openwrt-packages/docs/ci-github-actions-optimization.md](../../openwrt-packages/docs/ci-github-actions-optimization.md) — GitHub Actions SDK CI (separate from macOS Docker builds)

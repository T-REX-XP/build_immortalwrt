---
name: immortalwrt-macos-build
description: >-
  Build ImmortalWrt firmware on macOS using build-immortalwrt-macos.sh and Docker.
  Use when running CM5 builds, resetting work/ccache volumes, fixing Docker/Rosetta
  errors, setting IMMORTALWRT_* env vars, or debugging build-inner.sh workflow.
---

# ImmortalWrt macOS build (build_immortalwrt)

## Entry point

```sh
cd "/Users/t-rex-xp/Documents/ build_immortalwrt"

./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base
```

## Container workflow (`build-inner.sh`)

```text
rsync source → /work/immortalwrt
feeds update → feeds install → make defconfig → make download → make
copy bin/ → host --out-dir
```

Source is mounted read-only at `/src`. Build products never write back to macOS source except via copied `bin/`.

## Common flags

| Flag | Effect |
|------|--------|
| `--dl-dir DIR` | Persistent download cache (default: source `dl/`) |
| `--out-dir DIR` | Artifact output (default: source `bin/`) |
| `--reset-work-cache` | Delete Docker `/work` volume (fixes stale kernel hash, bad feeds cache) |
| `--reset-ccache` | Delete compiler cache volume |
| `--no-work-cache` | Ephemeral `/work` (clean one-off build) |
| `--no-build-image` | Reuse existing builder Docker image |
| `--allow-feed-failure` | Continue if `feeds update` fails (needs warmed work volume) |
| `--all-feeds` | Use source `feeds.conf.default` instead of `feeds.conf.cm5` |

## Environment variables

```sh
# Readable logs
IMMORTALWRT_MAKE_JOBS=1 ./scripts/build-immortalwrt-macos.sh --source ...

# Validate profile only (no compile)
IMMORTALWRT_STOP_AFTER_CONFIG=1 ./scripts/build-immortalwrt-macos.sh --source ...

# Fail if packages missing from manifest
IMMORTALWRT_EXPECT_PACKAGES="luci-app-oled luci-app-peripherals cm5-button-scripts ..." \
  ./scripts/build-immortalwrt-macos.sh --source ...

# Rootfs size (MiB, default 512 for Docker CM5)
IMMORTALWRT_ROOTFS_PARTSIZE=768 ./scripts/build-immortalwrt-macos.sh --source ...
```

## Apple Silicon / Docker

Default on `Darwin/arm64`: `IMMORTALWRT_DOCKER_PLATFORM=linux/arm64`

**Rosetta error** (`failed to open elf at /lib64/ld-linux-x86-64.so.2`):
- Do not use amd64 images on Apple Silicon unless intentional
- If switching platform: `--reset-work-cache` once

## Cache troubleshooting

| Symptom | Fix |
|---------|-----|
| `Missing kernel version/hash file` | `--reset-work-cache` |
| Stale feeds after adding feed | `--reset-work-cache` |
| Strange compile after branch switch | `--reset-work-cache --reset-ccache` |
| `tools/missing-macros` errors | Auto-repaired in build-inner; else reset work cache |

## Build log

Default: `<out-dir>/immortalwrt-build.log`

## Do not

- Run `make` directly on macOS host against the source tree for firmware builds
- Delete source tree `build_dir/` expecting Docker work volume to sync — they are separate
- Commit without user request

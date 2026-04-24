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
- The default `/work` Docker volume is much faster than rebuilding from a fresh
  container because OpenWrt's `build_dir`, `staging_dir`, `tmp`, and feeds clones
  survive between runs.
- The builder Dockerfile uses BuildKit cache mounts for apt package metadata and
  downloaded `.deb` files, so rebuilding the builder image is quicker too.
- Set `IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan"` if you want
  the build to fail when those packages are missing from the final manifest.

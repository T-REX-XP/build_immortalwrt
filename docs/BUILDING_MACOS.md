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
- The Dockerfile uses BuildKit cache mounts for apt metadata and downloaded
  `.deb` files.
- `/usr/local/go` in the builder image is used as the external Go bootstrap,
  which is needed for Go packages such as `tailscale` on Apple Silicon.

## Recommended CM5 Command

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared" \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl"
```

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

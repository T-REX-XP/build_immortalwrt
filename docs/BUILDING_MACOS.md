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

## Recommended CM5 Command

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan" \
./scripts/build-immortalwrt-macos.sh \
  --source /Users/t-rex-xp/Documents/immortalwrt \
  --device xunlong_orangepi-cm5-base \
  --dl-dir "$HOME/.cache/immortalwrt-dl"
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

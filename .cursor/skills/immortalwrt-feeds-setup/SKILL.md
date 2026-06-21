---
name: immortalwrt-feeds-setup
description: >-
  Configure ImmortalWrt feeds for CM5 macOS builds. Use when editing feeds.conf.cm5,
  mounting openwrt-packages via --custom-feed, enabling fantastic-packages, or using
  --all-feeds vs minimal feed list.
---

# ImmortalWrt feeds setup (build_immortalwrt)

## Default: minimal CM5 feeds

File: `scripts/feeds.conf.cm5`

```text
src-git packages https://github.com/immortalwrt/packages.git
src-git luci https://github.com/immortalwrt/luci.git
src-git awgopenwrt https://github.com/this-username-has-been-taken/amneziawg-openwrt.git
```

Used unless `--all-feeds` is passed.

## Custom feed (openwrt-packages)

Auto-mount: sibling directory next to source tree:

```text
immortalwrt/
openwrt-packages/feeds/    ← auto-detected
 build_immortalwrt/
```

Manual:

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --custom-feed /path/to/openwrt-packages/feeds
```

Container appends:

```text
src-link openwrt_packages /custom-feed
```

**Must** contain both `packages/` and `luci/` subdirectories.

## Full upstream feeds

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --all-feeds
```

Uses source tree `feeds.conf.default` — slower, more packages.

## fantastic-packages (optional, off by default)

**Not** in `feeds.conf.cm5` — avoids slow builds and upstream git failures.

To enable for firmware builds:

1. Add to `feeds.conf.cm5`:

   ```text
   src-git --root=feeds fantastic_packages https://github.com/fantastic-packages/packages.git;master
   ```

2. Add to `DEVICE_PACKAGES` in `armv8.mk`:

   ```text
   fantastic-keyring fantastic-packages-feeds
   ```

3. Rebuild with `--reset-work-cache` if work volume cached old feeds.

On running router:

```sh
opkg install fantastic-keyring fantastic-packages-feeds
opkg update
```

Treat as trusted third-party source only when intended.

## Feed failure handling

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --allow-feed-failure
```

Requires warmed Docker work volume with feeds already cloned.

## Custom feeds.conf file

```sh
./scripts/build-immortalwrt-macos.sh \
  --source /path/to/immortalwrt \
  --feeds-conf /path/to/my-feeds.conf
```

## After feed changes

Always consider `--reset-work-cache` when:
- Adding/removing feed lines
- Switching `--all-feeds` ↔ minimal
- Upstream feed URLs change

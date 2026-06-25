---
name: cm5-device-image
description: >-
  Orange Pi CM5 Base ImmortalWrt image profile, expected packages, LAN defaults,
  eMMC boot, PWM fan, OLED display, and button diagnostics. Use when editing armv8.mk DEVICE_PACKAGES,
  base-files, or validating flashed CM5 images via SSH/LuCI.
---

# CM5 device image (build_immortalwrt)

## Device profile

| Setting | Value |
|---------|-------|
| Device | `xunlong_orangepi-cm5-base` |
| Target | `rockchip` / `armv8` |
| LAN | `192.168.8.1/24`, DHCP `192.168.8.x` |
| LuCI | `luci-ssl` (HTTPS after first boot) |

Profile lives in **immortalwrt** source: `target/linux/rockchip/image/armv8.mk`, base-files under `target/linux/rockchip/armv8/base-files/`.

## Expected packages (manifest check)

Set before build to fail on missing packages:

```sh
IMMORTALWRT_EXPECT_PACKAGES="kmod-r8125 kmod-hwmon-pwmfan luci-ssl tailscale cloudflared luci-app-tailscale-community luci-app-cloudflared blocky luci-app-blocky luci-app-security-guide luci-app-peripherals luci-app-oled luci-app-buttons speedtest-go luci-app-speedtest docker dockerd luci-app-docker luci-app-dockerman kmod-wireguard wireguard-tools luci-proto-wireguard rpcd-mod-wireguard kmod-amneziawg amneziawg-tools luci-proto-amneziawg cm5-button-scripts"
```

## Image features (from README)

- **Blocky** — `/etc/blocky/config.yml`; first-boot `90-blocky-enable`; Prometheus on port 4000
- **luci-app-security-guide** — Network → Security Guide
- **luci-app-peripherals** — IR, PWM fan, I2C diagnostics (not OLED config)
- **luci-app-oled** — SH1106 menu (`oledd`), boot splash, button nav; CM5 HAT uses `/dev/i2c-7`
- **luci-app-buttons** — hotplug scripts under `/etc/rc.button/`
- **speedtest-go** + **luci-app-speedtest** — Network → Speed Test
- **Docker** — rootfs default 512 MiB (`IMMORTALWRT_ROOTFS_PARTSIZE`)

## Boot media

Kernel DTS enables eMMC (`sdhci`). U-Boot tries eMMC before microSD. Same `.img.gz` for both; remove microSD after flashing eMMC to boot from eMMC.

## PWM fan validation

See `docs/FAN_BUTTON_DIAGNOSTICS.md`.

Quick checks on router:

```sh
apk info | grep -E 'kmod-hwmon-pwmfan|luci-app-peripherals'
lsmod | grep '^pwm_fan '
# CM5 Base: PWM13 / pwm13m1_pins (not legacy PWM3)
```

LuCI: **System → Peripherals → PWM fan**

## Button validation

LuCI: **System → Buttons** (edits `/etc/rc.button/`)

Package: `cm5-button-scripts` from openwrt-packages feed.

## OLED display (Waveshare 1.3" HAT)

LuCI: **Services → OLED** (config + service control)

| Item | CM5 default |
|------|-------------|
| I2C | `/dev/i2c-7`, address `0x3c` |
| Daemon | `oledd` when `menu_mode=1` |
| Diagnostics only | **System → Peripherals → OLED** (i2cdetect) |

Requires **luci-app-oled r26+** on router for stable menu (ubus crash fixed in r26). Flash from feed build or sysupgrade.

Skill: `oled-peripherals-cm5` in openwrt-packages.

## Post-build verify

```sh
scripts/verify-kernel-modules.sh <path-to-staging-or-image-artifacts>
```

Checks built kernel and staged module directory use the same version.

## Related source edits

- DTS/buttons/fan: `immortalwrt` patches + `immortal_opi_cm5/dts-src/`
- Network migrate: `99-opi-cm5-network-migrate` uci-defaults

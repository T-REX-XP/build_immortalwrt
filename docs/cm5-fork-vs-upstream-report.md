# CM5 Fork vs Upstream ImmortalWrt — Maintenance Report

**Generated:** 2026-06-25  
**Fork:** `T-REX-XP/immortalwrt` branch `master`  
**Upstream:** [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) `master`  
**Merge-base:** `fd28cb248` (fork is **71 commits ahead**, **0 behind** upstream)

Upstream [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) has **no Orange Pi CM5 Base support** — no `xunlong_orangepi-cm5-base` device, no CM5 DTS, no CM5 base-files. All fork changes are **additive** CM5 bring-up on top of current upstream `master`.

---

## Executive summary

| Metric | Value |
|--------|-------|
| Files changed vs upstream | **42** (+2,729 / −4 lines) |
| Commits ahead of upstream | **71** (≈50 non-merge feature commits; rest are iterative fixes) |
| Kernel DTS patches (CM5) | **10** (`994-01` … `9999`) |
| Runtime base-files (CM5-specific) | **15** scripts / uci-defaults / hotplug |
| Vendored LuCI in fork tree | **None** (blocky/speedtest/security-guide were added then removed — correct split to `openwrt-packages` feed) |
| Default profile | `xunlong_orangepi-cm5-base` only in fork `target.mk` |

**Verdict:** The fork is **justified and mostly focused**. ~85% of the diff is kernel DTS + CM5 `base-files`. Maintenance pain comes from **iterative LED/network migrations**, **triple USB Wi-Fi bring-up paths**, and **large optional docs** — not from upstream divergence.

**Goal for maintenance:** Keep **immortalwrt** = kernel + DTS + minimal board layout; keep **openwrt-packages** = daemons, LuCI, button scripts; avoid re-vendoring feed packages into the main tree.

---

## 1. What upstream has (unchanged by fork)

- Standard ImmortalWrt `rockchip/armv8` targets (Orange Pi 5, 5 Plus, R1 Plus, Radxa, FriendlyARM, …)
- Generic `01_leds` / `02_network` for those boards
- No FPC I2C7, no CM5 carrier DTS, no eMMC-first SPL tweak for CM5 module

---

## 2. Fork features (keep)

### 2.1 Device profile & image

| Item | Path | Purpose |
|------|------|---------|
| CM5 device | `target/linux/rockchip/image/armv8.mk` | `Device/xunlong_orangepi-cm5-base`, DTS, bootscript, `DEVICE_PACKAGES` |
| Default profile | `target/linux/rockchip/armv8/target.mk` | `DEFAULT_PROFILE:=xunlong_orangepi-cm5-base` |
| Boot script | `image/orangepi-cm5-base.bootscript` | `usb-storage.quirks=0e8d:2870:i` for MT7612U installer mode |
| Kernel config | `armv8/config-6.18` | `CONFIG_SENSORS_PWM_FAN=y` |

**Current `DEVICE_PACKAGES` (slimmed):** platform (`kmod-r8125`, `kmod-hwmon-pwmfan`, buttons), custom feed apps (`luci-app-oled`, `luci-app-peripherals`, `cm5-button-scripts`), LuCI core, USB Wi-Fi stack, VPN/tunnel (WireGuard, AmneziaWG, Tailscale, Cloudflared), services (nlbwmon, ttyd).

**Already removed from image (good):** docker, travelmate, blocky, luci-app-blocky, luci-app-security-guide, speedtest-go, luci-app-speedtest, ksmbd, minidlna, collectd/statistics, SQM, pbr, watchcat, fwknopd, privoxy.

### 2.2 Kernel & DTS patches

| Patch | Purpose | Keep? |
|-------|---------|-------|
| `994-01` | Add `rk3588s-orangepi-cm5-base.dtb` to Makefile | **Yes** |
| `994-02` | Shared `rk3588s-orangepi-cm5.dtsi` | **Yes** |
| `994-03` | Full carrier DTS (GbE, RTL8125 PCIe, LEDs, keys) | **Yes** |
| `995` | PWM fan + thermal cooling maps | **Yes** — validate PWM pin vs schematic |
| `996` | VBUS 5V startup delay (USB Wi-Fi stability) | **Yes** |
| `997` | USERKEY + MaskROM `adc-keys` | **Yes** |
| `998` | Enable FPC `i2c7` (OLED HAT) | **Yes** |
| `9980` | WAN/LAN0 LED `PWM_POLARITY_INVERTED` | **Yes** — fixes LEDs on when link down |
| `999` | `waveshare-oled-rst` gpio-leds on **GPIO1_B4** | **Yes** |
| `9999` | FPC I2C pull-ups + RST pinctrl | **Yes** |

### 2.3 U-Boot

| Patch | Purpose | Keep? |
|-------|---------|-------|
| `117-rockchip-rk3588s-orangepi-5-spl-boot-emmc-before-sd.patch` | SPL tries eMMC before microSD | **Yes** for CM5 modules with onboard eMMC |

### 2.4 Runtime network & LEDs

| File | Purpose | Keep? |
|------|---------|-------|
| `board.d/02_network` | WAN=`eth0`, LAN=`eth1`+`eth2` on `br-lan` `192.168.8.1`, PCIe paths, MAC from eMMC | **Yes** |
| `board.d/01_leds` | STATUS / WAN / LAN1 / LAN2 netdev LEDs | **Yes** |
| `board.d/03_wireless_cm5` | US regdom | **Yes** |
| `uci-defaults/99-opi-cm5-network-migrate` | Fix stale br-lan after sysupgrade | **Yes** — has `logger` |

### 2.5 USB Wi-Fi (MT76x2u)

| File | Purpose | Keep? |
|------|---------|-------|
| `package/utils/usbmode/data/0e8d-2870` | MediaTek installer → runtime mode | **Yes** |
| `usbmodeswitch-cm5-run` | Boot + hotplug modeswitch retries (1 min boot loop) | **Yes** |
| `hotplug.d/usb/55-usbmodeswitch-cm5` | USB add → modeswitch | **Yes** |
| `uci-defaults/91-usbmodeswitch-cm5-firstboot` | Background boot-loop | **Yes** |
| `lib/cm5-base-wifi.sh` (231 lines) | 5 GHz AP autoconfig, credentials, fallback | **Yes** — largest runtime module |
| `hotplug.d/ieee80211/30-cm5-usb-wifi-ap` | Wiphy add → autoconfig | **Yes** |
| `init.d/reload-sdio-wifi` (CM5 block) | Boot retry for USB Wi-Fi | **Review** — misnamed; overlaps hotplug |
| `modules.d/51-mt76x2u-ap` | `disable_usb_sg=1` | **Yes** |
| `usr/libexec/cm5-wifi-benchmark` | Manual diagnostics | **Optional** |
| `hotplug.d/net/40-net-smp-affinity` (+CM5) | xHCI IRQ affinity | **Yes** |

### 2.6 Other package tree changes

| File | Purpose | Keep? |
|------|---------|-------|
| `package/kernel/linux/modules/ir.mk` | `kmod-ir-gpio-cir` for `luci-app-peripherals` | **Yes** until upstream adds equivalent |
| `package/utils/usbmode/Makefile` | `PKG_RELEASE:=2` | **Yes** |

---

## 3. Fixes applied over time (changelog-style)

| Area | Problem | Fix |
|------|---------|-----|
| **Board support** | No CM5 in ImmortalWrt | Full DTS series `994` + device profile |
| **Boot** | microSD preferred over eMMC | U-Boot SPL patch `117` |
| **Network** | Generic layout used `eth0` as LAN | `02_network` + `99-opi-cm5-network-migrate` → `eth0` WAN, `eth1`/`eth2` LAN `192.168.8.1` |
| **LAN LEDs** | PWM polarity wrong → LED on when unplugged | `9980` DTS + `96-cm5-leds` UCI + `01_leds` link mode |
| **USB Wi-Fi** | MT7612U stuck in installer mode | `usbmode` data `0e8d-2870`, `usbmodeswitch-cm5-run`, bootscript quirk |
| **USB Wi-Fi AP** | No 5 GHz AP defaults | `cm5-base-wifi.sh` + ieee80211 hotplug |
| **Fan** | No active cooling in DT | `995` pwm-fan + `kmod-hwmon-pwmfan` |
| **Buttons** | No userspace handlers | Moved to feed `cm5-button-scripts`; **removed** fork fallback `95-cm5-buttons` |
| **OLED FPC** | No `i2c7` on expansion connector | `998` + `9999` I2C pull-ups |
| **OLED RST** | DTS used GPIO4_B4 (wrong net) | **999** / **9999** → **GPIO1_B4**; feed `cm5-waveshare-rst.sh` **removed** (r30) — kernel sysfs only |
| **APK feeds** | 404 on `awgopenwrt` / `openwrt_packages` repos | `97-cm5-apk-feeds` strips URLs (packages baked in image) |
| **Image bloat** | Docker, blocky, SMB, DLNA, SQM, … | Progressive `DEVICE_PACKAGES` trim + `build-inner.sh` explicit disables |
| **Vendored LuCI** | blocky/speedtest/security-guide copied into fork | **Removed** (`bee20e8`) — belongs in `openwrt-packages` only |
| **Orphan recipe** | `fantastic-packages-feeds` build warnings | **Removed** from tree |

---

## 4. What lives outside this repo (correct split)

| Concern | Repository |
|---------|------------|
| `luci-app-oled`, `oledd`, OLED UCI (r34 dashboard) | `openwrt-packages` |
| `luci-app-peripherals` (r19 I2C tab), `cm5-button-scripts` (r3 hotplug chain) | `openwrt-packages` |
| macOS Docker build, feed wiring, `IMMORTALWRT_EXPECT_PACKAGES` | `build_immortalwrt` |
| Wiring harness notes | `openwrt-packages/docs/cm5-waveshare-oled-hat-wiring.md` |

**Do not re-vendor** feed packages into `immortalwrt/package/`.

---

## 5. Complexity hotspots & maintenance recommendations

### P1 — Address soon

| Item | Issue | Action |
|------|-------|--------|
| **Wi-Fi triple path** | `94-cm5-second-wifi-config` + `30-cm5-usb-wifi-ap` + `reload-sdio-wifi` all configure wireless | Document single order of operations; consider **one** boot retry (hotplug + init OR uci-defaults, not all three) |
| **LED migrations** | `96-cm5-leds` stamp `v5` + `01_leds` overlap | After one stable release, **freeze** `01_leds` for greenfield and plan to drop `96-cm5-leds` for new flashes only |
| **Commit history** | 71 commits, many iterative DEVICE_PACKAGES / DTS edits | **Squash** CM5 series into logical commits before any upstream PR attempt (optional for private fork) |

### P2 — Next pass

| Item | Issue | Action |
|------|-------|--------|
| **`reload-sdio-wifi`** | Name implies SDIO; CM5 uses USB Wi-Fi | Rename comment or extract `cm5-usb-wifi-retry` init snippet |
| **`97-cm5-apk-feeds`** | Silent sed | Add `logger -t cm5-apk` when lines removed |
| **Fan PWM** | Patch comment vs `pwm7` in DT | Validate against carrier schematic (PWM13 M1 vs pwm7) |
| **`kmod-rtl8812au-ct`** | Alt dongle driver | Drop from `DEVICE_PACKAGES` if only MT76x2u is supported |
| **`docs/cm5-mt76x2u-hotspot-optimization.md`** (396 lines) | Lives in `build_immortalwrt/docs/` | Keep there; link from README |

### P3 — Optional / long-term

| Item | Action |
|------|--------|
| **`.cursor/skills/`, `AGENTS.md`** | Dev metadata — fine; not shipped in image |
| **`cm5-base-wifi.sh`** | Could move to feed package if fork should stay DTS-only |
| **Upstreaming** | Submit CM5 DTS + minimal `board.d` to [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) when stable; keep CM5-specific packages in feed |
| **Rebase cadence** | Fork is 0 behind upstream today — rebase onto upstream `master` monthly to avoid drift |

---

## 6. Files changed vs upstream (inventory)

```
A  .cursor/skills/cm5-base-files/SKILL.md
A  .cursor/skills/immortalwrt-build-system/SKILL.md
A  .cursor/skills/rockchip-cm5-target/SKILL.md
A  .cursor/skills/rockchip-kernel-dts/SKILL.md
M  .gitignore                          (+*.log)
A  AGENTS.md
A  docs/cm5-mt76x2u-hotspot-optimization.md
M  package/boot/uboot-rockchip/Makefile
A  package/boot/uboot-rockchip/patches/117-...-spl-boot-emmc-before-sd.patch
A  package/kernel/linux/modules/ir.mk
M  package/utils/usbmode/Makefile
A  package/utils/usbmode/data/0e8d-2870
M  target/linux/rockchip/armv8/base-files/etc/board.d/01_leds
M  target/linux/rockchip/armv8/base-files/etc/board.d/02_network
A  target/linux/rockchip/armv8/base-files/etc/board.d/03_wireless_cm5
A  target/linux/rockchip/armv8/base-files/etc/hotplug.d/ieee80211/30-cm5-usb-wifi-ap
M  target/linux/rockchip/armv8/base-files/etc/hotplug.d/net/40-net-smp-affinity
A  target/linux/rockchip/armv8/base-files/etc/hotplug.d/usb/55-usbmodeswitch-cm5
M  target/linux/rockchip/armv8/base-files/etc/init.d/reload-sdio-wifi
A  target/linux/rockchip/armv8/base-files/etc/modules.d/51-mt76x2u-ap
A  target/linux/rockchip/armv8/base-files/etc/uci-defaults/91-usbmodeswitch-cm5-firstboot
A  target/linux/rockchip/armv8/base-files/etc/uci-defaults/94-cm5-second-wifi-config
A  target/linux/rockchip/armv8/base-files/etc/uci-defaults/96-cm5-leds
A  target/linux/rockchip/armv8/base-files/etc/uci-defaults/97-cm5-apk-feeds
A  target/linux/rockchip/armv8/base-files/etc/uci-defaults/99-opi-cm5-network-migrate
A  target/linux/rockchip/armv8/base-files/lib/cm5-base-wifi.sh
A  target/linux/rockchip/armv8/base-files/usr/libexec/cm5-wifi-benchmark
A  target/linux/rockchip/armv8/base-files/usr/sbin/usbmodeswitch-cm5-run
M  target/linux/rockchip/armv8/config-6.18
M  target/linux/rockchip/armv8/target.mk
M  target/linux/rockchip/image/armv8.mk
A  target/linux/rockchip/image/orangepi-cm5-base.bootscript
A  target/linux/rockchip/patches-6.18/994-01-... through 9999-...
```

**Not in diff (removed during fork evolution):** `95-cm5-buttons`, `package/system/fantastic-packages-feeds`, vendored `blocky` / `luci-app-*` copies.

---

## 7. Suggested maintenance workflow

1. **Rebase** onto [upstream master](https://github.com/immortalwrt/immortalwrt) regularly (`git fetch upstream && git rebase upstream/master`).
2. **Edit CM5 DTS** only in `patches-6.18/994–9999`; export from `immortal_opi_cm5/dts-src` when possible.
3. **Edit daemons/LuCI** only in `openwrt-packages`; reference names in `DEVICE_PACKAGES` only.
4. **Build** via `build_immortalwrt` Docker wrapper — not native macOS `make`.
5. **Validate** with `IMMORTALWRT_EXPECT_PACKAGES` manifest check after profile changes.
6. **Review this doc** after major profile or DTS changes.

---

## 8. Quick reference — CM5 runtime layout

| Silkscreen | Interface | LED sysfs |
|------------|-----------|-----------|
| WAN | `eth0` | `green:wan` |
| LAN1 | `eth1` | `green:lan-0` |
| LAN2 | `eth2` | `green:lan-1` |

| Bus | Device | Notes |
|-----|--------|-------|
| `/dev/i2c-7` | OLED HAT @ `0x3c` | FPC pads 11/12 |
| `/sys/class/leds/waveshare-oled-rst` | RST GPIO1_B4 | DTS patch 999 |

---

## Appendix — regenerate this report

```sh
cd /path/to/immortalwrt
git fetch upstream master
git log --oneline upstream/master..master
git diff --stat upstream/master...master
```

Upstream: https://github.com/immortalwrt/immortalwrt

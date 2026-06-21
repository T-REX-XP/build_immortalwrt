---
name: blocky-dns-cm5
description: >-
  Blocky DNS on CM5 ImmortalWrt images — ports, dnsmasq forwarding, LuCI integration,
  and Wi-Fi client DNS troubleshooting. Use when debugging "ping IP works but not hostname",
  blocky crash loops, or 90-blocky-enable / blocky-dnsmasq-sync behavior.
---

# Blocky DNS on CM5 (build_immortalwrt)

## Image defaults

- Config baked in: `/etc/blocky/config.yml`
- First boot: `/etc/uci-defaults/90-blocky-enable` enables Blocky when init + non-empty YAML exist
- **DNS port:** `5353` (avoids conflict with dnsmasq on **53**)
- **HTTP/API + Prometheus:** port `4000` (`/metrics` for luci-app-blocky dashboard)

## Router DNS integration

LuCI: **Services → Blocky DNS → Configuration → Router DNS integration**

Sets dnsmasq upstream to Blocky (`127.0.0.1#5353`). All DHCP clients get filtering without per-device DNS changes.

CLI equivalent:

```sh
/usr/sbin/blocky-dnsmasq-sync enable   # forward dnsmasq → Blocky
/usr/sbin/blocky-dnsmasq-sync disable  # remove upstream entry
/usr/sbin/blocky-dnsmasq-sync status
```

First boot runs sync automatically after enabling Blocky.

## LuCI operations

- **Controls → Refresh lists** — reload remote blocklists via Blocky HTTP API
- Edit upstreams/denylists in YAML; save and restart Blocky
- Dashboard metrics require Prometheus enabled in config (default in CM5 image)

## Troubleshooting: IP ping OK, hostname fails

Symptoms: `ping 8.8.8.8` works, `ping example.com` does not.

1. **Dnsmasq → Blocky chain**
   - If Router DNS integration enabled but Blocky stopped/crashing, dnsmasq cannot resolve
   - Check: `service blocky running`, LuCI Status → Processes

2. **WAN DNS**
   - Broken upstream: `nslookup example.com 127.0.0.1` vs `cat /tmp/resolv.conf.d/resolv.conf.auto`

3. **AP / dumb-AP**
   - Clients need DNS option 6 (usually AP LAN IP)
   - AP without DHCP/DNS may leave clients with no resolver

Reference: [OpenWrt dnsmasq DNS docs](https://openwrt.org/docs/guide-user/base-system/dhcp.dns)

## Config corruption (post-flash)

If Blocky crash-loops with YAML errors after upgrade (conffile preserved):

```sh
/etc/init.d/blocky stop
# Restore clean template from package or reinstall blocky
opkg reinstall blocky
/etc/init.d/blocky start
```

Package fixes live in **openwrt-packages** (`blocky-lists-sync`, `blocky-config-apply`).

## Package source

- Recipe: `openwrt-packages/feeds/packages/blocky`
- LuCI: `openwrt-packages/feeds/luci/luci-app-blocky`
- Mounted via `--custom-feed` or sibling auto-detect during macOS build

#!/usr/bin/env bash
# Runs inside the Docker builder.
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export FORCE_UNSAFE_CONFIGURE="${FORCE_UNSAFE_CONFIGURE:-1}"

SOURCE="/src"
WORK_ROOT="/work"
IWRT="$WORK_ROOT/immortalwrt"
TARGET="${IMMORTALWRT_TARGET:-rockchip}"
SUBTARGET="${IMMORTALWRT_SUBTARGET:-armv8}"
DEVICE="${IMMORTALWRT_DEVICE:-xunlong_orangepi-cm5-base}"
TARGET_DIR="bin/targets/$TARGET/$SUBTARGET"
USE_CCACHE="${IMMORTALWRT_USE_CCACHE:-1}"
CACHE_FEEDS="${IMMORTALWRT_CACHE_FEEDS:-1}"

BUILD_LOG="${IMMORTALWRT_BUILD_LOG:-immortalwrt-build.log}"
if [[ "$BUILD_LOG" != /* ]]; then
	BUILD_LOG="/out/$BUILD_LOG"
fi
mkdir -p "$(dirname "$BUILD_LOG")"
exec > >(tee -a "$BUILD_LOG") 2>&1
trap '' PIPE

echo "=== ImmortalWrt build log: $BUILD_LOG ==="
echo "=== Target device: $TARGET/$SUBTARGET/$DEVICE ==="
echo "=== Work cache: ${WORK_ROOT} (preserves build_dir/staging_dir/tmp across runs when mounted) ==="

mkdir -p "$WORK_ROOT"

echo "=== Copying source tree to Linux filesystem ==="
rsync_args=(
	-a
	--delete
	--exclude /staging_dir/ \
	--exclude /build_dir/ \
	--exclude /tmp/ \
	--exclude /dl/ \
	--exclude /bin/ \
	--exclude /.config \
	--exclude /.config.old
)

if [[ "$CACHE_FEEDS" == "1" ]]; then
	rsync_args+=(--exclude /feeds/ --exclude /package/feeds/)
fi

rsync "${rsync_args[@]}" "$SOURCE"/ "$IWRT"/

# Older wrapper versions excluded every directory named "bin", which left
# tools/missing-macros/src/bin out of the copied tree and cached a broken
# prepared host build. Repair that cache automatically on the next run.
if [[ -d tools/missing-macros/src/bin && -d build_dir/host/missing-macros && ! -d build_dir/host/missing-macros/bin ]]; then
	echo "Repairing cached tools/missing-macros build (missing src/bin from older rsync exclude)."
	rm -rf build_dir/host/missing-macros
	rm -f staging_dir/host/stamp/.missing-macros_installed
fi

cd "$IWRT"

rm -rf dl
ln -s /dl dl

if [[ "$USE_CCACHE" == "1" ]]; then
	mkdir -p /ccache
	export CCACHE_DIR=/ccache
	export CCACHE_COMPILERCHECK=content
	ccache -M "${IMMORTALWRT_CCACHE_MAXSIZE:-20G}" >/dev/null || true
	echo "Using ccache: $CCACHE_DIR ($(ccache -s | sed -n '1p'))"
fi

echo "=== Host prerequisites for feeds (staging_dir/host/bin) ==="
JOBS_PREP="${IMMORTALWRT_PREP_MAKE_JOBS:-$(nproc)}"
make -j"$JOBS_PREP" prepare-mk OPENWRT_BUILD=
[[ -x staging_dir/host/bin/mkhash ]] || {
	echo "ERROR: staging_dir/host/bin/mkhash missing after prepare-mk." >&2
	exit 1
}

echo "=== Preparing feeds ==="
if [[ -n "${IMMORTALWRT_FEEDS_CONF:-}" && -f "${IMMORTALWRT_FEEDS_CONF}" ]]; then
	cp "$IMMORTALWRT_FEEDS_CONF" feeds.conf
	echo "Using custom feeds.conf: $IMMORTALWRT_FEEDS_CONF"
else
	[[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf
	echo "Using feeds.conf from source tree/default."
fi

if [[ -n "${IMMORTALWRT_CUSTOM_FEED:-}" ]]; then
	if [[ ! -d "${IMMORTALWRT_CUSTOM_FEED}/packages" || ! -d "${IMMORTALWRT_CUSTOM_FEED}/luci" ]]; then
		echo "ERROR: IMMORTALWRT_CUSTOM_FEED must point at a directory containing packages/ and luci/ (openwrt-packages/feeds)." >&2
		exit 1
	fi
	echo "src-link openwrt_packages ${IMMORTALWRT_CUSTOM_FEED}" >> feeds.conf
	echo "Custom feed openwrt_packages -> ${IMMORTALWRT_CUSTOM_FEED}"
fi

if [[ -d feeds/packages/.git ]]; then
	git -C feeds/packages checkout -- lang/python/python3/files/python3-package-email.mk 2>/dev/null || true
fi

if [[ "${IMMORTALWRT_SKIP_FEEDS_UPDATE:-0}" == "1" ]]; then
	echo "Skipping ./scripts/feeds update -a (IMMORTALWRT_SKIP_FEEDS_UPDATE=1)."
elif ./scripts/feeds update -a; then
	:
elif [[ "${IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE:-0}" == "1" ]]; then
	echo "WARNING: ./scripts/feeds update -a failed (network/DNS/offline?). Continuing with existing feeds/ checkouts." >&2
	echo "WARNING: Requires a warmed Docker work volume; cold/offline builds may fail later at feeds install." >&2
else
	echo "ERROR: ./scripts/feeds update -a failed. Fix GitHub access or pass IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE=1 / --allow-feed-failure when using cached feeds." >&2
	exit 1
fi

if [[ -n "${IMMORTALWRT_CUSTOM_FEED:-}" ]]; then
	echo "Refreshing openwrt_packages feed index from ${IMMORTALWRT_CUSTOM_FEED}"
	if ! ./scripts/feeds update -i openwrt_packages; then
		echo "ERROR: ./scripts/feeds update -i openwrt_packages failed." >&2
		exit 1
	fi
fi

if [[ "${IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG:-1}" == "1" ]]; then
	for f in \
		feeds/packages/lang/python/python3/files/python3-package-email.mk \
		package/feeds/packages/lang/python/python3/files/python3-package-email.mk
	do
		[[ -f "$f" && ! -L "$f" ]] || continue
		awk '
			/^define Package\/python3-email$/ { p = 1 }
			p && /^[[:space:]]*DEPENDS:=/ { sub(/DEPENDS:=.*/, "DEPENDS:=+python3-light") }
			p && /^endef$/ { p = 0 }
			{ print }
		' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
	done
	echo "Applied python3-email Kconfig patch (set IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG=0 to skip)."
fi

if [[ "${IMMORTALWRT_PRUNE_BROKEN_FEED_PACKAGES:-0}" == "1" ]]; then
	for d in \
		net/fail2ban \
		net/onionshare-cli \
		lang/python/Flask \
		lang/python/python-flask-babel \
		lang/python/python-flask-httpauth \
		lang/python/python-flask-login \
		lang/python/python-flask-seasurf \
		lang/python/python-flask-session \
		lang/python/python-flask-socketio \
		lang/python/python-engineio \
		lang/python/python-socketio \
		lang/python/python-pytest \
		lang/python/python-pytest-forked \
		lang/python/python-pytest-xdist \
		utils/setools \
		utils/selinux-python
	do
		if [[ -d "feeds/packages/$d" ]]; then
			rm -rf "feeds/packages/$d"
			echo "Pruned packages feed: feeds/packages/$d"
		fi
	done
	if ! ./scripts/feeds update -i packages; then
		if [[ "${IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE:-0}" != "1" ]]; then
			exit 1
		fi
		echo "WARNING: ./scripts/feeds update -i packages failed; continuing." >&2
	fi
fi

rm -rf package/feeds
./scripts/feeds install -a
if [[ -n "${IMMORTALWRT_CUSTOM_FEED:-}" ]] && [[ -d "${IMMORTALWRT_CUSTOM_FEED}/luci/luci-app-mcu-display" ]]; then
	rm -f package/feeds/luci/luci-app-mcu-display
	mkdir -p package/feeds/openwrt_packages
	ln -sfn ../../../feeds/openwrt_packages/luci/luci-app-mcu-display package/feeds/openwrt_packages/luci-app-mcu-display
fi

# CM5: drop yggdrasil from the build tree (ImmortalWrt packages feed + openwrt_packages copy).
# Not in DEVICE_PACKAGES; stale /work cache must not compile or ship it.
if [[ "$DEVICE" == "xunlong_orangepi-cm5-base" ]]; then
	for _pkg in yggdrasil luci-proto-yggdrasil; do
		rm -f "package/feeds/packages/${_pkg}" \
			"package/feeds/openwrt_packages/${_pkg}" \
			"package/feeds/luci/${_pkg}"
	done
	for _feed_dir in feeds/packages/net/yggdrasil; do
		if [[ -d "$_feed_dir" && -w "$_feed_dir" ]]; then
			rm -rf "$_feed_dir"
			echo "Pruned feed tree (not in CM5 image): $_feed_dir"
		fi
	done
	# openwrt_packages yggdrasil lives on the host-mounted custom feed (often read-only);
	# unlinking package/feeds/openwrt_packages/yggdrasil above is sufficient.
	while IFS= read -r -d '' _ygg_build; do
		echo "Removing cached yggdrasil build tree: $_ygg_build"
		rm -rf "$_ygg_build"
	done < <(find build_dir/target-* -maxdepth 1 -name 'yggdrasil-*' -print0 2>/dev/null || true)
fi

echo "=== Selecting target profile ==="
cat > .config <<CFG
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y
CONFIG_TARGET_ROOTFS_PARTSIZE=${IMMORTALWRT_ROOTFS_PARTSIZE:-512}
# CONFIG_TARGET_MULTI_PROFILE is not set
CFG

if [[ "$USE_CCACHE" == "1" ]]; then
	cat >> .config <<'CFG'
CONFIG_CCACHE=y
CFG
fi

if [[ -x /usr/local/go/bin/go ]]; then
	cat >> .config <<'CFG'
# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set
CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="/usr/local/go"
CONFIG_GOLANG_BUILD_CACHE_DIR="/ccache/go-build"
CFG
fi

# Third-party feeds (awgopenwrt, openwrt_packages) are compile-time only.
# They are not published on downloads.immortalwrt.org; disable per-feed apk repos
# to avoid "unexpected end of file" on apk update (404 HTML served as packages.adb).
# Runtime: target/.../uci-defaults/97-cm5-apk-feeds strips all snapshot repos on CM5.
cat >> .config <<'CFG'
# CONFIG_FEED_awgopenwrt is not set
# CONFIG_FEED_openwrt_packages is not set
CFG

make defconfig

# CM5 profile: keep bittorrent / container stacks out of the image (not in DEVICE_PACKAGES;
# explicit disable guards against stale .config in the Docker work cache).
_cm5_forbidden_packages="yggdrasil luci-proto-yggdrasil"
if [[ "$DEVICE" == "xunlong_orangepi-cm5-base" ]]; then
	for _pkg in \
		docker dockerd docker-compose luci-app-docker luci-app-dockerman \
		travelmate luci-app-travelmate \
		aria2 webui-aria2 luci-app-aria2 \
		transmission transmission-daemon transmission-cli transmission-remote \
		transmission-web-control luci-app-transmission \
		luci-app-security-guide \
		${_cm5_forbidden_packages} \
		pbr luci-app-pbr \
		watchcat luci-app-watchcat \
		fwknopd luci-app-fwknopd \
		privoxy luci-app-privoxy \
		speedtest-go luci-app-speedtest \
		ksmbd-server luci-app-ksmbd \
		minidlna luci-app-minidlna \
		collectd luci-app-statistics \
		sqm-scripts luci-app-sqm
	do
		./scripts/config --disable "PACKAGE_${_pkg}" 2>/dev/null || true
		./scripts/config --disable "DEFAULT_${_pkg}" 2>/dev/null || true
	done
	make defconfig
fi

profile_config="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
if ! grep -Fxq "$profile_config" .config; then
	echo "defconfig did not select expected device profile: $profile_config" >&2
	echo "Selected profiles:" >&2
	grep "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_.*=y" .config >&2 || true
	exit 1
fi

if [[ "${IMMORTALWRT_STOP_AFTER_CONFIG:-0}" == "1" ]]; then
	echo "=== Stopping before download/build (IMMORTALWRT_STOP_AFTER_CONFIG=1) ==="
	cp .config /out/.config."$TARGET"."$SUBTARGET"."$DEVICE"
	exit 0
fi

JOBS="${IMMORTALWRT_MAKE_JOBS:-$(nproc)}"

echo "=== Downloading sources ==="
if [[ "${IMMORTALWRT_SKIP_DOWNLOAD:-0}" == "1" ]]; then
	echo "Skipping make download (IMMORTALWRT_SKIP_DOWNLOAD=1)."
elif ! make -j"$JOBS" download; then
	echo "ERROR: make download failed (network, mirror, or disk). Fix and retry; do not ignore this step." >&2
	exit 1
fi

if [[ "${IMMORTALWRT_SKIP_TARGET_BIN_CLEAN:-0}" != "1" ]]; then
	rm -rf "$TARGET_DIR"
fi

# Host tools/meson upgrades leave stale target Meson trees in /work (e.g. libevdev via
# usbutils → libudev-zero). OpenWrt may skip reconfigure and run ninja install against
# openwrt-build/ configured with an older Meson → hard failure at install time.
_meson_stamp="staging_dir/host/stamp/.meson_installed"
if [[ -f "$_meson_stamp" ]]; then
	while IFS= read -r -d '' _core; do
		_ob="$(dirname "$(dirname "$_core")")"
		_pkg="$(dirname "$_ob")"
		if [[ "$_meson_stamp" -nt "$_core" ]]; then
			echo "Removing stale Meson package tree: $_pkg (host meson newer than configure)"
			rm -rf "$_pkg"
		fi
	done < <(find build_dir/target-* -path '*/openwrt-build/meson-private/coredata.dat' -print0 2>/dev/null || true)
fi

# Serialise Go host toolchain before parallel package compile. Otherwise blocky,
# cloudflared, tailscale, … can start while hostpkg go-1.27 is still building → "go: command not found".
if grep -qE '^CONFIG_(DEFAULT_)?(blocky|cloudflared|tailscale)=y' .config 2>/dev/null || \
   grep -qE '^CONFIG_PACKAGE_(blocky|cloudflared|tailscale)=y' .config 2>/dev/null; then
	echo "=== Preparing Go host toolchain (sequential) ==="
	make -j1 V=s \
		package/feeds/packages/golang/host/compile \
		package/feeds/packages/golang1.27/host/compile
fi

echo "=== Building (jobs: $JOBS) ==="
make -j"$JOBS" V=s

echo "=== Copying artifacts to /out ==="
mkdir -p /out
rsync -a bin/ /out/
cp .config /out/.config."$TARGET"."$SUBTARGET"."$DEVICE"

# CM5 Base profile packages (merged into IMMORTALWRT_EXPECT_PACKAGES when unset or partial).
_cm5_profile_expect="cm5-button-scripts kmod-input-adc-keys kmod-button-hotplug luci-app-mcu-display blocky luci-app-blocky openssh-sftp-server picocom screen socat"
if [[ -z "${IMMORTALWRT_EXPECT_PACKAGES:-}" ]]; then
	IMMORTALWRT_EXPECT_PACKAGES="$_cm5_profile_expect"
else
	for _pkg in $_cm5_profile_expect; do
		case " ${IMMORTALWRT_EXPECT_PACKAGES} " in
		*" $_pkg "*) ;;
		*) IMMORTALWRT_EXPECT_PACKAGES="$IMMORTALWRT_EXPECT_PACKAGES $_pkg" ;;
		esac
	done
fi
export IMMORTALWRT_EXPECT_PACKAGES

manifest="$(ls "$TARGET_DIR"/*-"$DEVICE".manifest 2>/dev/null | head -1 || true)"
if [[ -n "$manifest" && "$DEVICE" == "xunlong_orangepi-cm5-base" ]]; then
	for pkg in ${_cm5_forbidden_packages}; do
		if grep -q "^${pkg} " "$manifest"; then
			echo "Forbidden package present in CM5 manifest: $pkg ($manifest)" >&2
			exit 1
		fi
	done
fi
if [[ -n "$manifest" && -n "${IMMORTALWRT_EXPECT_PACKAGES:-}" ]]; then
	for pkg in ${IMMORTALWRT_EXPECT_PACKAGES//,/ }; do
		if ! grep -q "^${pkg} " "$manifest"; then
			echo "Expected package missing from manifest: $pkg ($manifest)" >&2
			exit 1
		fi
	done
fi

bash /scripts/verify-kernel-modules.sh "$IWRT"

echo "=== Done. Images are under /out/targets/$TARGET/$SUBTARGET ==="

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

echo "=== Preparing feeds ==="
if [[ -n "${IMMORTALWRT_FEEDS_CONF:-}" && -f "${IMMORTALWRT_FEEDS_CONF}" ]]; then
	cp "$IMMORTALWRT_FEEDS_CONF" feeds.conf
	echo "Using custom feeds.conf: $IMMORTALWRT_FEEDS_CONF"
else
	[[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf
	echo "Using feeds.conf from source tree/default."
fi

if [[ -d feeds/packages/.git ]]; then
	git -C feeds/packages checkout -- lang/python/python3/files/python3-package-email.mk 2>/dev/null || true
fi

./scripts/feeds update -a

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
	./scripts/feeds update -i packages
fi

rm -rf package/feeds
./scripts/feeds install -a

echo "=== Selecting target profile ==="
cat > .config <<CFG
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y
# CONFIG_TARGET_MULTI_PROFILE is not set
CFG

if [[ "$USE_CCACHE" == "1" ]]; then
	cat >> .config <<'CFG'
CONFIG_CCACHE=y
CFG
fi

make defconfig

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
make -j"$JOBS" download 2>/dev/null || true

if [[ "${IMMORTALWRT_SKIP_TARGET_BIN_CLEAN:-0}" != "1" ]]; then
	rm -rf "$TARGET_DIR"
fi

echo "=== Building (jobs: $JOBS) ==="
make -j"$JOBS" V=s

echo "=== Copying artifacts to /out ==="
mkdir -p /out
rsync -a bin/ /out/
cp .config /out/.config."$TARGET"."$SUBTARGET"."$DEVICE"

manifest="$(ls "$TARGET_DIR"/*-"$DEVICE".manifest 2>/dev/null | head -1 || true)"
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

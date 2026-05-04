#!/usr/bin/env bash
# macOS-friendly ImmortalWrt builder.
#
# Builds inside Docker on a Linux filesystem while using a caller-provided
# ImmortalWrt source tree as input.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE="${IMMORTALWRT_SOURCE:-}"
DEVICE="${IMMORTALWRT_DEVICE:-xunlong_orangepi-cm5-base}"
TARGET="${IMMORTALWRT_TARGET:-rockchip}"
SUBTARGET="${IMMORTALWRT_SUBTARGET:-armv8}"
IMAGE="${IMMORTALWRT_BUILDER_IMAGE:-immortalwrt-macos-builder:22.04}"
DL_DIR="${IMMORTALWRT_DL_DIR:-}"
OUT_DIR="${IMMORTALWRT_OUT_DIR:-}"
FEEDS_CONF="${IMMORTALWRT_FEEDS_CONF:-$SCRIPT_DIR/feeds.conf.cm5}"
WORK_VOLUME="${IMMORTALWRT_WORK_VOLUME:-}"
CCACHE_VOLUME="${IMMORTALWRT_CCACHE_VOLUME:-}"
USE_WORK_CACHE="${IMMORTALWRT_USE_WORK_CACHE:-1}"
USE_CCACHE="${IMMORTALWRT_USE_CCACHE:-1}"
RESET_WORK_CACHE=0
RESET_CCACHE=0
BUILD_IMAGE=1
DOCKER_BUILD_ARGS=()
CUSTOM_FEED_HOST=""
#
# Apple Silicon + Docker Desktop: amd64 containers use Rosetta / QEMU for x86-64 Linux,
# which often breaks during feeds/Make with:
#   rosetta error: failed to open elf at /lib64/ld-linux-x86-64.so.2
# Default to linux/arm64 here unless IMMORTALWRT_DOCKER_PLATFORM is already set.
DOCKER_PLATFORM_ARGS=()
if [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]; then
	if [[ -z "${IMMORTALWRT_DOCKER_PLATFORM+x}" ]]; then
		export IMMORTALWRT_DOCKER_PLATFORM=linux/arm64
	fi
fi
if [[ -n "${IMMORTALWRT_DOCKER_PLATFORM:-}" ]]; then
	DOCKER_PLATFORM_ARGS=(--platform "$IMMORTALWRT_DOCKER_PLATFORM")
	echo "Docker platform: $IMMORTALWRT_DOCKER_PLATFORM (empty IMMORTALWRT_DOCKER_PLATFORM before launch for Docker default; use linux/amd64 only if required)."
fi

usage() {
	cat <<'USAGE'
Usage:
  build-immortalwrt-macos.sh --source /path/to/immortalwrt [options]

Required:
  --source DIR          ImmortalWrt source tree to build.

Options:
  --device NAME         Target device profile (default: xunlong_orangepi-cm5-base).
  --target NAME         Target (default: rockchip).
  --subtarget NAME      Subtarget (default: armv8).
  --dl-dir DIR          Download cache (default: SOURCE/dl).
  --out-dir DIR         Artifact output dir (default: SOURCE/bin).
  --feeds-conf FILE     feeds.conf to use (default: scripts/feeds.conf.cm5).
  --all-feeds           Use the source tree's feeds.conf/feeds.conf.default.
  --work-volume NAME    Docker volume for /work cache (default: derived from source/device).
  --ccache-volume NAME  Docker volume for compiler cache (default: derived from source/device).
  --no-work-cache       Use an ephemeral /work directory.
  --no-ccache           Disable CONFIG_CCACHE and the ccache volume.
  --reset-work-cache    Remove the selected /work cache volume before building.
  --reset-ccache        Remove the selected ccache volume before building.
  --image NAME          Docker builder image tag.
  --no-build-image      Reuse an existing builder image.
  --docker-build-arg X  Extra argument passed to docker build.
  --allow-feed-failure  Continue if feeds update fails (needs warmed Docker work volume).
  --custom-feed DIR     Host path to openwrt-packages/feeds (mounted at /custom-feed in container).
                        If omitted, a sibling DIR/openwrt-packages/feeds next to immortalwrt is used when present.
  -h, --help            Show this help.

Docker / Apple Silicon:
  IMMORTALWRT_DOCKER_PLATFORM defaults to linux/arm64 on Darwin/arm64 (avoid Rosetta on amd64 images).

Useful environment variables passed through to the container:
  IMMORTALWRT_MAKE_JOBS
  IMMORTALWRT_STOP_AFTER_CONFIG
  IMMORTALWRT_SKIP_TARGET_BIN_CLEAN
  IMMORTALWRT_BUILD_LOG
  IMMORTALWRT_EXPECT_PACKAGES
  IMMORTALWRT_ROOTFS_PARTSIZE
  IMMORTALWRT_USE_WORK_CACHE
  IMMORTALWRT_USE_CCACHE
  IMMORTALWRT_WORK_VOLUME
  IMMORTALWRT_CCACHE_VOLUME
  IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG
  IMMORTALWRT_PRUNE_BROKEN_FEED_PACKAGES
  IMMORTALWRT_SKIP_FEEDS_UPDATE
  IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE
  IMMORTALWRT_SKIP_DOWNLOAD
  IMMORTALWRT_CUSTOM_FEED            (normally auto or set by --custom-feed; container path /custom-feed)
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--source)
			SOURCE="${2:-}"
			shift 2
			;;
		--device)
			DEVICE="${2:-}"
			shift 2
			;;
		--target)
			TARGET="${2:-}"
			shift 2
			;;
		--subtarget)
			SUBTARGET="${2:-}"
			shift 2
			;;
		--dl-dir)
			DL_DIR="${2:-}"
			shift 2
			;;
		--out-dir)
			OUT_DIR="${2:-}"
			shift 2
			;;
		--feeds-conf)
			FEEDS_CONF="${2:-}"
			shift 2
			;;
		--all-feeds)
			FEEDS_CONF=""
			shift
			;;
		--work-volume)
			WORK_VOLUME="${2:-}"
			shift 2
			;;
		--ccache-volume)
			CCACHE_VOLUME="${2:-}"
			shift 2
			;;
		--no-work-cache)
			USE_WORK_CACHE=0
			shift
			;;
		--no-ccache)
			USE_CCACHE=0
			shift
			;;
		--reset-work-cache)
			RESET_WORK_CACHE=1
			shift
			;;
		--reset-ccache)
			RESET_CCACHE=1
			shift
			;;
		--image)
			IMAGE="${2:-}"
			shift 2
			;;
		--no-build-image)
			BUILD_IMAGE=0
			shift
			;;
		--docker-build-arg)
			DOCKER_BUILD_ARGS+=("$2")
			shift 2
			;;
		--allow-feed-failure)
			IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE=1
			shift
			;;
		--custom-feed)
			CUSTOM_FEED_HOST="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [[ -z "$SOURCE" ]]; then
	echo "Missing --source /path/to/immortalwrt" >&2
	usage >&2
	exit 2
fi

SOURCE="$(cd "$SOURCE" && pwd)"
if [[ ! -d "$SOURCE/scripts" || ! -f "$SOURCE/rules.mk" ]]; then
	echo "Expected an ImmortalWrt/OpenWrt source tree at: $SOURCE" >&2
	exit 1
fi

# CM5 profile DEVICE_PACKAGES expects blocky + luci-app-blocky from feed openwrt_packages.
# Without --custom-feed those packages never appear in manifests. If the sibling
# checkout …/openwrt-packages/feeds exists (layouts like Documents/{immortalwrt,openwrt-packages}), use it.
if [[ -z "$CUSTOM_FEED_HOST" ]]; then
	AUTO_CF="$(dirname "$SOURCE")/openwrt-packages/feeds"
	if [[ -d "$AUTO_CF/packages" && -d "$AUTO_CF/luci" ]]; then
		CUSTOM_FEED_HOST="$(cd "$AUTO_CF" && pwd)"
		echo "Auto-selected custom feed: $CUSTOM_FEED_HOST"
	fi
fi

if [[ -n "$CUSTOM_FEED_HOST" ]]; then
	CUSTOM_FEED_HOST="$(cd "$CUSTOM_FEED_HOST" && pwd)"
	if [[ ! -d "$CUSTOM_FEED_HOST/packages" || ! -d "$CUSTOM_FEED_HOST/luci" ]]; then
		echo "--custom-feed must be the feeds root with packages/ and luci/ (e.g. …/openwrt-packages/feeds)." >&2
		exit 1
	fi
fi

if [[ -n "$FEEDS_CONF" ]]; then
	FEEDS_CONF="$(cd "$(dirname "$FEEDS_CONF")" && pwd)/$(basename "$FEEDS_CONF")"
	if [[ ! -f "$FEEDS_CONF" ]]; then
		echo "feeds.conf not found: $FEEDS_CONF" >&2
		exit 1
	fi
fi

DL_DIR="${DL_DIR:-$SOURCE/dl}"
OUT_DIR="${OUT_DIR:-$SOURCE/bin}"
mkdir -p "$DL_DIR" "$OUT_DIR"
DL_DIR="$(cd "$DL_DIR" && pwd)"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if ! docker version >/dev/null 2>&1; then
	echo "Docker is required. Install/start Docker Desktop for macOS." >&2
	exit 1
fi

if [[ "$BUILD_IMAGE" == "1" ]]; then
	docker_build_cmd=(docker build)
	if [[ ${#DOCKER_PLATFORM_ARGS[@]} -gt 0 ]]; then
		docker_build_cmd+=("${DOCKER_PLATFORM_ARGS[@]}")
	fi
	if [[ ${#DOCKER_BUILD_ARGS[@]} -gt 0 ]]; then
		docker_build_cmd+=("${DOCKER_BUILD_ARGS[@]}")
	fi
	docker_build_cmd+=(-t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR")
	"${docker_build_cmd[@]}"
fi

cache_key="$(printf '%s\n%s\n%s\n%s\n' "$SOURCE" "$TARGET" "$SUBTARGET" "$DEVICE" | shasum -a 256 | awk '{print substr($1,1,16)}')"
WORK_VOLUME="${WORK_VOLUME:-immortalwrt-work-$cache_key}"
CCACHE_VOLUME="${CCACHE_VOLUME:-immortalwrt-ccache-$cache_key}"

if [[ "$USE_WORK_CACHE" == "1" && "$RESET_WORK_CACHE" == "1" ]]; then
	docker volume rm "$WORK_VOLUME" >/dev/null 2>&1 || true
fi

if [[ "$USE_CCACHE" == "1" && "$RESET_CCACHE" == "1" ]]; then
	docker volume rm "$CCACHE_VOLUME" >/dev/null 2>&1 || true
fi

docker_args=(
	--rm
	-e "IMMORTALWRT_DEVICE=$DEVICE"
	-e "IMMORTALWRT_TARGET=$TARGET"
	-e "IMMORTALWRT_SUBTARGET=$SUBTARGET"
	-e "IMMORTALWRT_USE_CCACHE=$USE_CCACHE"
	-e "FORCE_UNSAFE_CONFIGURE=1"
	-e "DEBIAN_FRONTEND=noninteractive"
	-v "$SOURCE:/src:ro"
	-v "$DL_DIR:/dl"
	-v "$OUT_DIR:/out"
	-v "$SCRIPT_DIR:/scripts:ro"
)

if [[ "$USE_WORK_CACHE" == "1" ]]; then
	docker_args+=(-v "$WORK_VOLUME:/work")
fi

if [[ "$USE_CCACHE" == "1" ]]; then
	docker_args+=(-v "$CCACHE_VOLUME:/ccache")
fi

if [[ -n "$FEEDS_CONF" ]]; then
	docker_args+=(-v "$FEEDS_CONF:/feeds.conf.custom:ro" -e "IMMORTALWRT_FEEDS_CONF=/feeds.conf.custom")
fi

if [[ -n "$CUSTOM_FEED_HOST" ]]; then
	docker_args+=(-v "$CUSTOM_FEED_HOST:/custom-feed:ro" -e "IMMORTALWRT_CUSTOM_FEED=/custom-feed")
fi

for var in \
	IMMORTALWRT_MAKE_JOBS \
	IMMORTALWRT_STOP_AFTER_CONFIG \
	IMMORTALWRT_SKIP_TARGET_BIN_CLEAN \
	IMMORTALWRT_BUILD_LOG \
	IMMORTALWRT_EXPECT_PACKAGES \
	IMMORTALWRT_ROOTFS_PARTSIZE \
	IMMORTALWRT_CACHE_FEEDS \
	IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG \
	IMMORTALWRT_PRUNE_BROKEN_FEED_PACKAGES \
	IMMORTALWRT_SKIP_FEEDS_UPDATE \
	IMMORTALWRT_FEEDS_UPDATE_ALLOW_FAILURE \
	IMMORTALWRT_SKIP_DOWNLOAD
do
	if [[ -n "${!var:-}" ]]; then
		docker_args+=(-e "$var=${!var}")
	fi
done

echo "Source:  $SOURCE"
echo "Device:  $TARGET/$SUBTARGET/$DEVICE"
echo "DL dir:  $DL_DIR"
echo "Out dir: $OUT_DIR"
if [[ "$USE_WORK_CACHE" == "1" ]]; then
	echo "Work cache volume:   $WORK_VOLUME"
else
	echo "Work cache volume:   disabled"
fi
if [[ "$USE_CCACHE" == "1" ]]; then
	echo "Compiler cache volume: $CCACHE_VOLUME"
else
	echo "Compiler cache volume: disabled"
fi
if [[ -n "$CUSTOM_FEED_HOST" ]]; then
	echo "Custom feed (openwrt_packages): $CUSTOM_FEED_HOST -> /custom-feed"
fi

exec docker run "${DOCKER_PLATFORM_ARGS[@]}" "${docker_args[@]}" "$IMAGE" /bin/bash /scripts/build-inner.sh

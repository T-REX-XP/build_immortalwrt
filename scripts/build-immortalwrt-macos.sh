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
BUILD_IMAGE=1
DOCKER_BUILD_ARGS=()

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
  --image NAME          Docker builder image tag.
  --no-build-image      Reuse an existing builder image.
  --docker-build-arg X  Extra argument passed to docker build.
  -h, --help            Show this help.

Useful environment variables passed through to the container:
  IMMORTALWRT_MAKE_JOBS
  IMMORTALWRT_STOP_AFTER_CONFIG
  IMMORTALWRT_SKIP_TARGET_BIN_CLEAN
  IMMORTALWRT_BUILD_LOG
  IMMORTALWRT_EXPECT_PACKAGES
  IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG
  IMMORTALWRT_PRUNE_BROKEN_FEED_PACKAGES
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
	if [[ ${#DOCKER_BUILD_ARGS[@]} -gt 0 ]]; then
		docker_build_cmd+=("${DOCKER_BUILD_ARGS[@]}")
	fi
	docker_build_cmd+=(-t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR")
	"${docker_build_cmd[@]}"
fi

docker_args=(
	--rm
	-e "IMMORTALWRT_DEVICE=$DEVICE"
	-e "IMMORTALWRT_TARGET=$TARGET"
	-e "IMMORTALWRT_SUBTARGET=$SUBTARGET"
	-e "FORCE_UNSAFE_CONFIGURE=1"
	-e "DEBIAN_FRONTEND=noninteractive"
	-v "$SOURCE:/src:ro"
	-v "$DL_DIR:/dl"
	-v "$OUT_DIR:/out"
	-v "$SCRIPT_DIR:/scripts:ro"
)

if [[ -n "$FEEDS_CONF" ]]; then
	docker_args+=(-v "$FEEDS_CONF:/feeds.conf.custom:ro" -e "IMMORTALWRT_FEEDS_CONF=/feeds.conf.custom")
fi

for var in \
	IMMORTALWRT_MAKE_JOBS \
	IMMORTALWRT_STOP_AFTER_CONFIG \
	IMMORTALWRT_SKIP_TARGET_BIN_CLEAN \
	IMMORTALWRT_BUILD_LOG \
	IMMORTALWRT_EXPECT_PACKAGES \
	IMMORTALWRT_PATCH_PYTHON3_EMAIL_KCONFIG \
	IMMORTALWRT_PRUNE_BROKEN_FEED_PACKAGES
do
	if [[ -n "${!var:-}" ]]; then
		docker_args+=(-e "$var=${!var}")
	fi
done

echo "Source:  $SOURCE"
echo "Device:  $TARGET/$SUBTARGET/$DEVICE"
echo "DL dir:  $DL_DIR"
echo "Out dir: $OUT_DIR"

exec docker run "${docker_args[@]}" "$IMAGE" /bin/bash /scripts/build-inner.sh

#!/usr/bin/env bash
# Fail the build if the staged rootfs module tree does not match UTS_RELEASE.
set -euo pipefail

IWRT="${1:-/work/immortalwrt}"
if [[ ! -d "$IWRT/staging_dir" || ! -d "$IWRT/build_dir" ]]; then
	echo "verify-kernel-modules: missing staging_dir or build_dir under $IWRT" >&2
	exit 1
fi

shopt -s nullglob

uts_files=("$IWRT"/build_dir/target-*/linux-rockchip_armv8/linux-*/include/generated/utsrelease.h)
if [[ ${#uts_files[@]} -eq 0 ]]; then
	uts_files=("$IWRT"/build_dir/target-*/linux-rockchip*/linux-*/include/generated/utsrelease.h)
fi
if [[ ${#uts_files[@]} -eq 0 ]]; then
	echo "verify-kernel-modules: no linux-rockchip*/.../utsrelease.h under $IWRT/build_dir" >&2
	exit 1
fi

uts_h="${uts_files[0]}"
if [[ ${#uts_files[@]} -gt 1 ]]; then
	echo "verify-kernel-modules: warning: multiple linux trees, using $uts_h" >&2
fi

uts=$(sed -n 's/^#define UTS_RELEASE "\(.*\)".*/\1/p' "$uts_h" | head -1)
if [[ -z "$uts" ]]; then
	echo "verify-kernel-modules: could not parse UTS_RELEASE from $uts_h" >&2
	exit 1
fi

mod_lib=""
while IFS= read -r d; do
	[[ -d "$d" ]] || continue
	mod_lib="$d"
	break
done < <(find "$IWRT/build_dir" -path '*/root.orig-rockchip/lib/modules' -type d 2>/dev/null | sort -u)

if [[ -z "$mod_lib" ]]; then
	while IFS= read -r d; do
		[[ -d "$d" ]] || continue
		mod_lib="$d"
		break
	done < <(find "$IWRT/build_dir" -path '*/root.orig-*/lib/modules' -type d 2>/dev/null | sort -u)
fi

if [[ -z "$mod_lib" ]]; then
	mod_lib_dirs=("$IWRT"/staging_dir/target-*/root/lib/modules)
	if [[ ${#mod_lib_dirs[@]} -gt 0 && -d "${mod_lib_dirs[0]}" ]]; then
		mod_lib="${mod_lib_dirs[0]}"
	fi
fi

if [[ -z "$mod_lib" || ! -d "$mod_lib" ]]; then
	echo "verify-kernel-modules: no lib/modules under build_dir/.../root.orig-*/ or staging_dir/.../root/" >&2
	exit 1
fi

staged=("$mod_lib"/*)
if [[ ${#staged[@]} -eq 0 || ! -d "${staged[0]}" ]]; then
	echo "verify-kernel-modules: no version directory under $mod_lib" >&2
	exit 1
fi

modver=$(basename "${staged[0]}")
if [[ ${#staged[@]} -gt 1 ]]; then
	echo "verify-kernel-modules: multiple module trees under $mod_lib; expected exactly one." >&2
	ls -la "$mod_lib" >&2
	exit 1
fi

if [[ "$modver" != "$uts" ]]; then
	echo "verify-kernel-modules: MISMATCH: kernel UTS_RELEASE=$uts but staged /lib/modules/$modver" >&2
	exit 1
fi

modroot="$mod_lib/$modver"
if [[ -f "$modroot/modules.dep" ]]; then
	:
elif [[ -f "$modroot/modules.dep.bb" ]]; then
	echo "verify-kernel-modules: note: using busybox modules.dep.bb (no modules.dep)"
elif ko=( "$modroot"/*.ko ) && [[ ${#ko[@]} -gt 0 ]]; then
	echo "verify-kernel-modules: note: .ko modules present; modules.dep may be generated on first boot"
elif [[ -f "$modroot/modules.builtin" ]]; then
	echo "verify-kernel-modules: note: only modules.builtin (no loadable .ko in tree root)"
else
	echo "verify-kernel-modules: empty module tree under $modroot" >&2
	exit 1
fi

echo "verify-kernel-modules: OK: kernel and staged /lib/modules version both $uts"

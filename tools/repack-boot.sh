#!/usr/bin/env bash
# Puts a freshly built kernel into the stock boot.img, keeping the ramdisk, cmdline,
# header version and kernel compression of the original.
#
#   tools/repack-boot.sh <stock-boot.img> <Image> <out-boot.img>
#
# Uses AOSP's unpack_bootimg/mkbootimg (cloned into ./mkbootimg on first run, or
# MKBOOTIMG_DIR). The DTB is not touched: on this board it lives in its own partition.
set -euo pipefail

stock=$(realpath "${1:?usage: repack-boot.sh <stock-boot.img> <Image> <out-boot.img>}")
image=$(realpath "${2:?missing Image}")
out=$(realpath -m "${3:?missing output path}")
root=$(cd "$(dirname "$0")/.." && pwd)
mkb=${MKBOOTIMG_DIR:-$root/mkbootimg}

[ -d "$mkb" ] || git clone -q --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg "$mkb"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Prints the exact mkbootimg arguments (shell-quoted) that rebuild the stock image.
args=$(python3 "$mkb/unpack_bootimg.py" --boot_img "$stock" --out "$work" --format=mkbootimg)

case $(head -c4 "$work/kernel" | od -An -tx1 | tr -d ' \n') in
  1f8b*)    gzip -9nc "$image" > "$work/kernel" ;;
  02214c18) lz4 -l -12 -c "$image" > "$work/kernel" ;;
  *)        cp "$image" "$work/kernel" ;;
esac

eval "python3 \"$mkb/mkbootimg.py\" $args --output \"$out\""
python3 "$mkb/unpack_bootimg.py" --boot_img "$out" --out "$work/check" | grep -E "header version|kernel_size|command line"

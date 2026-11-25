#!/usr/bin/env bash
# Puts a freshly built kernel into the stock boot.img, keeping the ramdisk, cmdline,
# header version and kernel compression of the original.
#
#   tools/repack-boot.sh <stock-boot.img> <Image> <out-boot.img>
#
# Uses AOSP's unpack_bootimg/mkbootimg and avbtool (cloned into ./mkbootimg and ./avb on
# first run, or MKBOOTIMG_DIR / AVB_DIR). The DTB is not touched: on this board it lives
# in vendor_boot.
#
# vbmeta chains "boot" to the AVB footer inside the boot partition, so an image without
# a footer is invalid metadata, which an unlocked bootloader still refuses. When the
# stock image has a footer, the output gets a new one with the same partition size, name
# and props, signed with the AOSP test key: a foreign key is an error unlocked devices
# allow (the same thing Magisk relies on).
set -euo pipefail

stock=$(realpath "${1:?usage: repack-boot.sh <stock-boot.img> <Image> <out-boot.img>}")
image=$(realpath "${2:?missing Image}")
out=$(realpath -m "${3:?missing output path}")
root=$(cd "$(dirname "$0")/.." && pwd)
mkb=${MKBOOTIMG_DIR:-$root/mkbootimg}
avb=${AVB_DIR:-$root/avb}

[ -d "$mkb" ] || git clone -q --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg "$mkb"
[ -d "$avb" ] || git clone -q --depth 1 https://android.googlesource.com/platform/external/avb "$avb"

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

if info=$(python3 "$avb/avbtool.py" info_image --image "$stock" 2>/dev/null); then
  name=$(sed -n 's/^ *Partition Name: *//p' <<< "$info" | head -1)
  props=()
  while IFS= read -r prop; do props+=(--prop "$prop"); done \
    < <(sed -n "s/^ *Prop: \(.*\) -> '\(.*\)'$/\1:\2/p" <<< "$info")
  python3 "$avb/avbtool.py" add_hash_footer --image "$out" \
    --partition_size "$(stat -c%s "$stock")" --partition_name "$name" \
    --algorithm SHA256_RSA4096 --key "$avb/test/data/testkey_rsa4096.pem" "${props[@]}"
fi

python3 "$mkb/unpack_bootimg.py" --boot_img "$out" --out "$work/check" | grep -E "header version|kernel_size|command line"
python3 "$avb/avbtool.py" info_image --image "$out" 2>/dev/null | grep -E "Image size|Partition Name|Prop" || true

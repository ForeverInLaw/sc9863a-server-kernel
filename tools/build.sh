#!/usr/bin/env bash
# Builds one kernel variant and checks whether the stock vendor modules would load on it.
#
#   tools/build.sh <variant>     # variant = configs/<variant>.fragment
#
# The config is the phone's running config + configs/common.fragment + the variant fragment.
# Expects the Aether source in ./kernel and clang r416183b in ./clang (override with
# KERNEL_DIR / CLANG_DIR). Output goes to out/<variant>/: build.log, abi.txt, report.md,
# Module.symvers, arch/arm64/boot/Image. Re-running reuses the tree, so builds are incremental.
set -euo pipefail

variant=${1:?usage: tools/build.sh <variant>}
root=$(cd "$(dirname "$0")/.." && pwd)
kernel=${KERNEL_DIR:-$root/kernel}
out=$root/out/$variant
fragment=$root/configs/$variant.fragment
export PATH="${CLANG_DIR:-$root/clang}/bin:$PATH"

kmake() {
  make -C "$kernel" O="$out" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    KCFLAGS=-D__ANDROID_COMMON_KERNEL__ "$@"
}

# Source fixes; skipped when already applied so the tree can be reused.
for patch in "$root"/patches/*.patch; do
  git -C "$kernel" apply --reverse --check "$patch" 2>/dev/null || git -C "$kernel" apply "$patch"
done

mkdir -p "$out"
cp "$root/device/stock/config/running.config" "$out/.config"
"$kernel/scripts/kconfig/merge_config.sh" -m -O "$out" "$out/.config" "$root/configs/common.fragment" "$fragment" > /dev/null
kmake olddefconfig > /dev/null

{
  echo "### $variant"
  echo "Options that did not stick:"
  cat "$root/configs/common.fragment" "$fragment" | { grep -E '^(CONFIG_|# CONFIG_.* is not set$)' || true; } | while IFS= read -r opt; do
    grep -qx "$opt" "$out/.config" || echo "- \`$opt\`"
  done
} > "$out/report.md"

if ! kmake -j"${JOBS:-$(nproc)}" Image modules > "$out/build.log" 2>&1; then
  grep -nE 'error:|Error [0-9]' "$out/build.log" | head -20
  exit 1
fi

python3 "$root/tools/modcrc.py" check "$out/Module.symvers" "$root/device/stock/config/module_crcs.tsv" > "$out/abi.txt" || true
{ echo; echo '```'; cat "$out/abi.txt"; echo '```'; } >> "$out/report.md"
cat "$out/report.md"

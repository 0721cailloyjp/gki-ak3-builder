#!/usr/bin/env bash
# build-lkm.sh —— 以 LKM（可加载内核模块）方式编译 kernelsu.ko
#
# 与 built-in 模式（CONFIG_KSU=y 编进 Image）的区别：
#   * 不修改内核树，不需要刷 boot 分区 → 风险极低，可随时卸载
#   * 产物是 kernelsu.ko，由 Manager(ksud) 在运行时加载
#   * 同时产出 aarch64 与 x86_64 两个架构（供模拟器 / 虚拟机 / 桌面 Android 使用）
#
# 原理：上游 <solution>/kernel/ 目录自带树外编译入口（Makefile），
#   KDIR=<内核构建目录> make 即可。Kbuild 里的 KSU_VERSION 推导逻辑
#   （30000 + git rev-list --count HEAD）在树外编译时同样生效，
#   因此【仍然必须完整克隆】源码仓库，浅克隆会让版本号退化成 16。
#
# 用法:
#   build-lkm.sh <kmi> <kernel_src_dir> <ksu_src_dir> <out_dir>
# 例:
#   build-lkm.sh android15-6.6 ./gki ./ksu-src ./out
#
# 退出码: 0 成功 / 1 失败

set -uo pipefail

KMI="${1:?用法: build-lkm.sh <kmi> <kernel_src_dir> <ksu_src_dir> <out_dir>}"
KDIR_SRC="$(realpath "${2:?缺少 kernel_src_dir}")"
KSU_SRC="$(realpath "${3:?缺少 ksu_src_dir}")"
OUT_DIR="$(realpath -m "${4:?缺少 out_dir}")"

KV="${KMI##*-}"     # 6.6 / 6.12 / 6.18

echo "======================================================"
echo " LKM 构建"
echo "   KMI        : $KMI  (kernel $KV)"
echo "   内核源码   : $KDIR_SRC"
echo "   KSU 源码   : $KSU_SRC"
echo "   输出目录   : $OUT_DIR"
echo "======================================================"

# ---------------------------------------------------------------
# 0) 前置检查：KSU 源码必须带完整 .git，否则 KSU_VERSION 退化
# ---------------------------------------------------------------
if [ ! -d "$KSU_SRC/kernel" ]; then
  echo "::error::$KSU_SRC/kernel 不存在 —— 该方案不支持 LKM 模式？"
  exit 1
fi
if [ ! -d "$KSU_SRC/.git" ]; then
  echo "::warning::ksu-src 没有 .git，KSU_VERSION 会退化成 16（管理器可能报'需要更新内核'）"
else
  echo "==> KSU commit 数: $(cd "$KSU_SRC" && git rev-list --count HEAD 2>/dev/null || echo '?')"
fi

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------
# 1) 准备 arm64 构建目录（KDIR）：就地用内核源码树
# ---------------------------------------------------------------
# 上游 ddk-lkm.yml 是从容器里预置的 /opt/ddk/kdir-<arch>/<kmi> 取 KDIR，
# 我们这里改用「现场从内核源码树生成」，不依赖预置镜像。
KDIR_ARM="$KDIR_SRC"
echo "==> [arm64] 使用内核源码树作为 KDIR: $KDIR_ARM"

pushd "$KDIR_ARM" >/dev/null

echo "==> [arm64] gki_defconfig"
make ARCH=arm64 LLVM=1 gki_defconfig

# GKI 默认开 LTO，编外部模块时不需要且会拖慢/易 OOM → 关掉
scripts/config --file .config -d LTO_CLANG -e LTO_NONE \
  -d LTO_CLANG_THIN -d LTO_CLANG_FULL -d THINLTO || true

# 6.12 / 6.18 需要 CFI 整数归一化，否则模块加载时会因 CFI 校验失败
if [ "$KV" = "6.12" ] || [ "$KV" = "6.18" ]; then
  echo "==> [arm64] 启用 CONFIG_CFI_ICALL_NORMALIZE_INTEGERS（$KV 必需）"
  scripts/config --file .config -e CONFIG_CFI_ICALL_NORMALIZE_INTEGERS || true
fi

echo "==> [arm64] modules_prepare"
make ARCH=arm64 LLVM=1 modules_prepare

echo "==> [arm64] 生成 SELinux 头（Kbuild 需要）"
make ARCH=arm64 LLVM=1 security/selinux/built-in.a || true

popd >/dev/null

# ---------------------------------------------------------------
# 2) 编译 arm64 kernelsu.ko
# ---------------------------------------------------------------
echo "==> [arm64] 编译 kernelsu.ko"
cd "$KSU_SRC/kernel"
make clean >/dev/null 2>&1 || true
if ! KDIR="$KDIR_ARM" CONFIG_KSU=m CC=clang make -j"$(nproc)"; then
  echo "::error::[arm64] kernelsu.ko 编译失败"
  exit 1
fi

KO_ARM="$(find "$KSU_SRC/kernel" -maxdepth 1 -name 'kernelsu.ko' | head -1)"
if [ -z "$KO_ARM" ]; then
  echo "::error::[arm64] 没找到 kernelsu.ko"
  ls -la "$KSU_SRC/kernel"
  exit 1
fi

mkdir -p "$OUT_DIR/aarch64"
cp "$KO_ARM" "$OUT_DIR/aarch64/${KMI}_kernelsu.ko"
echo "==> [arm64] 原始大小: $(du -h "$OUT_DIR/aarch64/${KMI}_kernelsu.ko" | cut -f1)"
llvm-strip -d "$OUT_DIR/aarch64/${KMI}_kernelsu.ko"
echo "==> [arm64] strip 后: $(du -h "$OUT_DIR/aarch64/${KMI}_kernelsu.ko" | cut -f1)"

# ---------------------------------------------------------------
# 3) 准备 x86_64 构建目录
# ---------------------------------------------------------------
# 用独立的 O= 输出目录，避免与 arm64 的 .config / 中间产物冲突。
KDIR_X64="$(dirname "$KDIR_SRC")/kdir-x64-${KMI}"
mkdir -p "$KDIR_X64"
echo "==> [x86_64] 构建目录: $KDIR_X64"

pushd "$KDIR_SRC" >/dev/null

# ddk-min / 部分内核源码的 modpost 在交叉编译外部模块时会报错，
# 这四处编辑是幂等的（对已修过的源码重复执行无害）。
echo "==> [x86_64] 应用 modpost 兼容补丁（幂等）"
MODPOST=scripts/mod/modpost.c
if [ -f "$MODPOST" ]; then
  sed -i -E 's/^([[:space:]]*)check_exports\(mod\);/\1\/\/ check_exports(mod);/' "$MODPOST" || true
  sed -i -E 's/^([[:space:]]*)s->module = exp->module;/\1\/\/ s->module = exp->module;/' "$MODPOST" || true
  sed -i 's/^static void check_exports(/static void __attribute__((unused)) check_exports(/' "$MODPOST" || true
  sed -i 's/__version_ext_names\\") =\\n/__version_ext_names\\") = \\"\\"\\n/' "$MODPOST" || true
else
  echo "::warning::找不到 $MODPOST，跳过 modpost 补丁"
fi

echo "==> [x86_64] gki_defconfig"
unset ARCH CROSS_COMPILE
export ARCH=x86_64
make O="$KDIR_X64" LLVM=1 gki_defconfig

scripts/config --file "$KDIR_X64/.config" -d LTO_CLANG -e LTO_NONE \
  -d LTO_CLANG_THIN -d LTO_CLANG_FULL -d THINLTO || true

if [ "$KV" = "6.12" ] || [ "$KV" = "6.18" ]; then
  echo "==> [x86_64] 启用 CONFIG_CFI_ICALL_NORMALIZE_INTEGERS（$KV 必需）"
  scripts/config --file "$KDIR_X64/.config" -e CONFIG_CFI_ICALL_NORMALIZE_INTEGERS || true
fi

echo "==> [x86_64] modules_prepare"
make O="$KDIR_X64" LLVM=1 modules_prepare

echo "==> [x86_64] 生成 SELinux 头（Kbuild 需要）"
make O="$KDIR_X64" LLVM=1 security/selinux/built-in.a || true

popd >/dev/null

# ---------------------------------------------------------------
# 4) 编译 x86_64 kernelsu.ko
# ---------------------------------------------------------------
echo "==> [x86_64] 编译 kernelsu.ko"
cd "$KSU_SRC/kernel"
make clean >/dev/null 2>&1 || true

MDIR="$(realpath .)"
EXTRA="CONFIG_KSU=m CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y"
if [ "$KV" = "6.18" ]; then
  # 6.18 用 MO= 而非 src=：Kbuild 注释「6.18 exports the external module
  # source as srcroot when M/MO are used」，旧写法在 6.18 上会找不到源。
  echo "==> [x86_64] 6.18 特判：使用 MO=\$MDIR"
  MAKE_ARGS=(-C "$KDIR_X64" M="$MDIR" MO="$MDIR" modules $EXTRA)
else
  MAKE_ARGS=(-C "$KDIR_X64" M="$MDIR" src="$MDIR" modules $EXTRA)
fi

if ! make "${MAKE_ARGS[@]}" -j"$(nproc)"; then
  echo "::error::[x86_64] kernelsu.ko 编译失败"
  exit 1
fi

KO_X64="$(find "$KSU_SRC/kernel" -maxdepth 1 -name 'kernelsu.ko' | head -1)"
if [ -z "$KO_X64" ]; then
  echo "::error::[x86_64] 没找到 kernelsu.ko"
  exit 1
fi

mkdir -p "$OUT_DIR/x86_64"
cp "$KO_X64" "$OUT_DIR/x86_64/${KMI}_kernelsu.ko"
echo "==> [x86_64] 原始大小: $(du -h "$OUT_DIR/x86_64/${KMI}_kernelsu.ko" | cut -f1)"
llvm-strip -d "$OUT_DIR/x86_64/${KMI}_kernelsu.ko"
echo "==> [x86_64] strip 后: $(du -h "$OUT_DIR/x86_64/${KMI}_kernelsu.ko" | cut -f1)"

# ---------------------------------------------------------------
# 5) 汇总
# ---------------------------------------------------------------
echo "======================================================"
echo " LKM 构建完成"
find "$OUT_DIR" -name '*_kernelsu.ko' -exec ls -la {} \;
echo "======================================================"

# 断言：两个架构都必须产出
for ARCH_DIR in aarch64 x86_64; do
  [ -s "$OUT_DIR/$ARCH_DIR/${KMI}_kernelsu.ko" ] \
    || { echo "::error::$ARCH_DIR/${KMI}_kernelsu.ko 不存在或为空"; exit 1; }
done
echo "OK: 两个架构的 kernelsu.ko 均已产出"

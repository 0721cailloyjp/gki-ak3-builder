# MoeSU (FolkSU) GKI Kernel Build

自动化构建 **MoeSU**（原 **FolkSU**，KernelSU fork）的 GKI 内核 + AnyKernel3 刷机包 + 配套 root 管理器。

> **改名说明**：项目原地址 `LyraVoid/FolkSU` 已于 2026-10 改名为 **`LyraVoid/MoeSU`**（同一仓库，旧地址仍会 301 重定向）。
> 本仓库沿用 `FolkSU` 作为产物前缀，便于和社区既有命名保持一致。

## 这是什么

把 MoeSU 的内核以 **built-in 模式**（`CONFIG_KSU=y`）集成进 Google GKI 内核源码，
编译出完整 `Image`，再用 [AnyKernel3](https://github.com/WildKernels/AnyKernel3) 的 **gki-2.0**
分支打成刷机 zip；同时自动抓取官方最新的 **Manager APK** 一并发布。

与官方 **LKM 模式**（只出 `kernelsu.ko`）不同，本流程产出的是**完整 GKI 内核**，直接刷入 `boot` 分区。

## 支持的 KMI

≥ **5.10** 的全部 GKI 主线：

| KMI | kernel | Android | AOSP 分支 |
|---|---|---|---|
| `android12-5.10` | 5.10 | 12 | `android12-5.10-lts` |
| `android13-5.10` | 5.10 | 13 | `android13-5.10-lts` |
| `android13-5.15` | 5.15 | 13 | `android13-5.15-lts` |
| `android14-5.15` | 5.15 | 14 | `android14-5.15-lts` |
| `android14-6.1` | 6.1 | 14 | `android14-6.1-lts` |
| `android15-6.6` | 6.6 | 15 | `android15-6.6-lts` |
| `android16-6.12` | 6.12 | 16 | `android16-6.12-lts` |

分支表见 [`config/kmi-matrix.json`](config/kmi-matrix.json)。

## 怎么用

1. 进 **Actions** → **Build FolkSU GKI Kernel + AnyKernel3** → **Run workflow**
2. 选 **KMI**（例如 `android15-6.6`）
3. 按需开 **SUSFS**
4. 跑完在 **Releases** 下载：
   - `FolkSU-<KMI>-GKI-AnyKernel3.zip` — 内核刷机包
   - `FolkSU-Manager-<版本>.apk` — 配套管理器
5. 先刷内核 zip，再装 Manager APK

### 输入项

| 输入 | 说明 |
|---|---|
| `kmi` | 目标 KMI，必填 |
| `kernel_branch` | AOSP 分支，留空 = `<kmi>-lts`；也可填 `android15-6.6-2026-10` |
| `folksu_ref` | MoeSU 内核源码引用，默认 `master` |
| `enable_susfs` | 集成 SUSFS 内核补丁 |
| `skip_on_patch_failure` | 补丁失败时跳过（不中断构建） |
| `make_release` | 成功后创建 Release |
| `release_tag` | 自定义 tag，留空自动生成 |

## 构建链路

```
AOSP kernel/common @ <kmi>-lts
        │
        ├─ MoeSU 仓库（完整克隆，保留 .git）
        │     └─ kernel/  → common/drivers/folksu-src/kernel
        │                     （软链为 common/drivers/kernelsu）
        │
        ├─ susfs4ksu @ gki-<av>-<kv> (可选)
        │
        ├─ make gki_defconfig + CONFIG_KSU=y (+ 关 LTO)
        │
        ├─ make Image
        │
        ├─ WildKernels/AnyKernel3@gki-2.0  → 生成 anykernel.sh → zip
        │
        └─ MoeSU Build Manager workflow → 抓最新 Manager APK
```

## 三个关键实现细节

### 1. 必须完整克隆 MoeSU（不能 `--depth=1`）

`kernel/Kbuild` 里的版本号推导是：

```make
KSU_VERSION = 30000 + $(git rev-list --count HEAD)
```

浅克隆会让 commit 计数退化成 `1` → `KSU_VERSION=30001`，与真实值不符，
管理器会提示"**需要更新内核**"。实测当前 master 为 **2792** 个提交 → `KSU_VERSION=32792`，
与官方 Manager APK 文件名里的 `_32792` 完全吻合。

### 2. 必须把 `.git` 一起放进内核树

`kernel/Kbuild` 用 `git rev-parse --show-toplevel` 判断"是否处于内核仓库之外的独立仓库"：

```make
GIT_ROOT        := $(shell cd $(MDIR) && git rev-parse --show-toplevel)
KERNEL_GIT_ROOT := $(shell cd $(srctree) && git rev-parse --show-toplevel)
ifneq ($(GIT_ROOT),$(KERNEL_GIT_ROOT))   # 只有不同才会设版本号
```

如果只 `cp -a kernel/`（丢掉 `.git`），`GIT_ROOT` 会向上命中 `gki/.git`，
与 `KERNEL_GIT_ROOT` 相同 → **跳过推导 → `KSU_VERSION=16`**。
所以 workflow 把**整个 MoeSU 仓库**（含 `.git`）复制进 `drivers/folksu-src/`，
再软链 `kernelsu -> folksu-src/kernel`。

> 这也是不直接跑官方 `kernel/setup.sh` 的原因：它会 `git clone tiann/KernelSU`
> 并执行 `git stash/checkout/pull`，对已克隆的本地源码不可靠，而且 MoeSU 的
> `kernel/` 本身就是自包含的完整内核侧源码树，不需要再去拉上游。

### 3. 内核靠签名认管理器，不靠包名 —— 所以必须**不**定义 `KSU_MANAGER_PACKAGE`

`kernel/manager/apk_sign.c` 的判断逻辑：

```c
bool is_manager_apk(char *path)
{
#ifdef KSU_MANAGER_PACKAGE
    // 若定义了这个宏：先比对包名，不等则直接 false
    if (strncmp(pkg, KSU_MANAGER_PACKAGE, sizeof(KSU_MANAGER_PACKAGE)))
        return false;
#endif
    // 再比对签名
    return match_apk_signature(path, &match) && match.trusted;
}
```

**包名校验与签名校验是 `AND` 关系**：

| 是否定义 `KSU_MANAGER_PACKAGE` | 行为 |
|---|---|
| **未定义**（本流程的选择） | 只校验签名 → 管理器改包名后**依然可用** |
| 已定义 | 包名必须完全相等 → 上游改包名后**旧内核不认新管理器** |

**已知的上游变更**：下一个版本 Manager **改名为 `moesu`**，
包名从 `me.yuki.folksu` 改为 `me.yuki.moesu`，**签名证书不变**。
因为本流程不固化包名，改名的**新** Manager 刷到本流程编译的**旧**内核上
依然会被识别为可信管理器。

| 版本 | Manager 展示名 | Manager 包名 | 签名 |
|---|---|---|---|
| 当前 | FolkSU | `me.yuki.folksu` | 不变 |
| 下一版 | **moesu** | `me.yuki.moesu` | **不变** |

> 包名相关的引用全在用户态，与内核构建无关：
> `manager/app/build.gradle.kts`（`defaultManagerPackageName` 第 28 行 /
> `defaultManagerName` 第 29 行 / `resValue app_name` 第 154 行）、
> `manager/app/src/main/res/values/strings.xml`（`home_tile_manager`）、
> `userspace/ksud/build.rs`（`KSU_PACKAGE_NAME` 环境变量，可覆盖）、
> `.github/workflows/ksud.yml`、`scripts/test_anykernel3_device.py`。
> 经检索，`kernel/` 目录内**不含**任何包名或展示名硬编码。

可信签名来源：`Kbuild` 里的 `FOLKSU_TRUSTED_HASH ← EXPECTED_HASH`，
由官方用仓库 keystore 签出的 release 证书算出（实测 `0x033b` /
`c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6`）。
`apk_sign_keys[]` 里其余（KernelSU / KowSU / KernelSU-Next / ReSukiSU /
SukiSU / MKSU / RKSU / xxKSU）都只是"**识别但不自动授权**"，需要用户在
动态管理器界面手动批准。

> workflow 里会打印 Manager 的包名与签名指纹并做记录，便于跨版本比对。

## 编译时长

**单个 KMI 约 40–150 分钟**（取决于 runner 与是否开 SUSFS）。
本流程设计为**一次一个 KMI**，避免大批量 CI 触发 GitHub 风控。

## 上游来源

| 组件 | 来源 |
|---|---|
| 内核基座 | `android.googlesource.com/kernel/common` |
| Root 内核 | `LyraVoid/MoeSU`（原名 FolkSU，GPL-3.0） |
| Manager APK | `LyraVoid/MoeSU` Actions → `build-manager.yml` |
| SUSFS | `ShirkNeko/susfs4ksu` |
| AK3 框架 | `WildKernels/AnyKernel3@gki-2.0` |
| 参考实现 | `LingLuo17/AnyKernel3@dev`、`ShirkNeko/GKI_KernelSU_SUSFS` |

## 风险提示

- 刷内核**可能变砖**。刷前务必备份原厂 `boot.img` / `init_boot.img`。
- 内置模式与 LKM 模式**不可共存**；从 LKM 转内置前请先还原原厂镜像。
- AK3 脚本以 root 运行，请只刷可信包。
- Manager 版本与内核版本不一致时会提示"需要更新内核"，这时把 `folksu_ref`
  固定到该 Manager 对应的 commit 即可对齐。

## 仓库结构

```
.
├── .github/workflows/build.yml   # 主构建流程（19 步）
├── config/kmi-matrix.json        # KMI 分支对照表
├── scripts/fetch-manager.sh      # 自动抓取最新 Manager APK
└── README.md
```

## License

构建脚本：MIT。集成产物受各上游许可约束（MoeSU GPL-3.0、AK3 见其 LICENSE）。

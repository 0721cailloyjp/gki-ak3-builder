<div align="center">

# GKI Kernel Build

### 在线构建 GKI 内核（Root 内置）

**FinaSU / KernelSU / SukiSU-Ultra / KernelSU-Next + SUSFS**

选择方案与机型，云端编译，产物直接刷入

[![Build](https://github.com/0721cailloyjp/gki-ak3-builder/actions/workflows/build.yml/badge.svg)](https://github.com/0721cailloyjp/gki-ak3-builder/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/0721cailloyjp/gki-ak3-builder?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/0721cailloyjp/gki-ak3-builder/releases)
[![KernelSU](https://img.shields.io/badge/KernelSU-Supported-5AA300?style=flat-square)](https://kernelsu.org/)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

---

</div>

## 快速导航

- [开始构建](https://github.com/0721cailloyjp/gki-ak3-builder/actions/workflows/build.yml) — Actions → Run workflow
- [下载产物](https://github.com/0721cailloyjp/gki-ak3-builder/releases) — 已发布的内核与管理器
- [支持的 KMI](#支持的-kmi) — `uname -r` 对照表
- [附加功能](#附加功能可选) — BBG 防格机 / 网络增强 / ZRAM LZ4KD
- [注意事项](#注意事项) — 刷入前请阅读

---

## 最近更新

> 2026-10-11

1. 工作流界面中文化，输入项重新排序（基础配置在前、功能开关在后）
2. 新增 **BBG 防格机**：拦截对基带、efisp 等关键分区的非法写入
3. 新增 **网络增强**：BBRv3 拥塞控制、IPSet、Qdisc、CIFS
4. 新增 **ZRAM LZ4KD 增强**：ZRAM / ZSMALLOC 编入内核，使用 LZ4KD 压缩
5. 新增 **编译失败日志收集**：失败时自动打包诊断信息并上传 artifact

> 更早：内核调优档位（`none` / `safe` / `smart`）、Android 17 支持、LKM 构建模式。

---

## 支持的 root 方案

本项目集成 4 个持续维护的开源 root 方案，全部为完整内核方案（built-in）：

| 方案 | 说明 | Manager 包名 |
|---|---|---|
| **FinaSU** | 原 FolkSU / MoeSU，仓库多次更名，同一项目 | `me.yuki.fina` |
| **KernelSU** | 官方原版 | `me.weishu.kernelsu` |
| **SukiSU-Ultra** | 功能最全，支持 KPM 内核模块 | `com.sukisu.ultra` |
| **KernelSU-Next** | KernelSU 分支版 | `com.rifsxd.ksunext` |

> **如何选择**：一般推荐 **KernelSU** 或 **SukiSU-Ultra**。
> FinaSU 在中文社区使用较多，KernelSU-Next 相对小众。

> **内核与管理器如何匹配**：内核只校验管理器**签名**，不校验包名。
> 因此同一方案的任意版本管理器均可搭配任一版本内核使用。

> **FinaSU 更名影响**：`FolkSU` → `MoeSU` → `FinaSU` 共更名三次，
> 但**签名证书始终未变**，旧内核可继续搭配新版管理器。

## 项目说明

将所选 root 方案的代码以 **built-in 模式**（`CONFIG_KSU=y`）集成进 Google GKI 内核源码，
编译出完整 `Image`，再由 [AnyKernel3](https://github.com/WildKernels/AnyKernel3) 打包为刷机 zip，
同时自动获取配套的 Manager APK 一并发布。

与官方 **LKM 模式**（仅提供 `kernelsu.ko`，由管理器运行时加载）不同，
本流程产出**完整 GKI 内核**，直接刷入 `boot` 分区，开机即生效。

## 支持的 KMI

覆盖 ≥ **5.10** 的全部 GKI 主线，共 9 个目标：

| KMI | kernel | Android | AOSP 分支 | 备注 |
|---|---|---|---|---|
| `android12-5.10` | 5.10 | 12 | `android12-5.10-lts` | |
| `android13-5.10` | 5.10 | 13 | `android13-5.10-lts` | |
| `android13-5.15` | 5.15 | 13 | `android13-5.15-lts` | |
| `android14-5.15` | 5.15 | 14 | `android14-5.15-lts` | |
| `android14-6.1` | 6.1 | 14 | `android14-6.1-lts` | |
| `android15-6.6` | 6.6 | 15 | `android15-6.6-lts` | |
| `android16-6.12` | 6.12 | 16 | `android16-6.12-lts` | |
| `android17-6.12` | 6.12 | **17** | `android16-6.12-lts` | **跨代**：A17 系统沿用 6.12 内核 |
| `android17-6.18` | 6.18 | **17** | `android17-6.18` | A17 原生新内核（分支名**无** `-lts` 后缀） |

分支表见 [`config/kmi-matrix.json`](config/kmi-matrix.json)，`branch` 字段是唯一真源。

### 如何确定你的机型

在 adb shell 中执行：

```bash
uname -r
```

输出形如 `6.6.30-android15-8-gxxxx`，取前面 `主.次` 两位（即 `6.6`）。

| 内核版本 | Android 版本 | 对应 KMI |
|---|---|---|
| 5.10 | 12 / 13 | `android12-5.10` / `android13-5.10` |
| 5.15 | 13 / 14 | `android13-5.15` / `android14-5.15` |
| 6.1 | 14 | `android14-6.1` |
| 6.6 | 15 | `android15-6.6` |
| 6.12 | 16 | `android16-6.12` |
| 6.12 | 17 | `android17-6.12` |
| 6.18 | 17 | `android17-6.18` |

> **Android 版本与内核版本并非一一对应。** 例如 Android 17 存在两批设备，
> 分别使用 6.12 与 6.18 内核 —— 请以 `uname -r` 的结果为准，不要按 Android 版本推断。

> **Android 17 说明**：`android17-6.12` 与 `android16-6.12` 编译产物同源
> （均使用 `android16-6.12-lts` 分支），两者均可刷入，任选其一。

> **SUSFS 在 Android 17 上不可用**：上游尚未提供 6.12 / 6.18 补丁，
> 开启 SUSFS 时工作流会自动跳过并在日志中说明，root 功能本身不受影响。

## 怎么用

### 1. 触发构建

进入 **Actions** 页面 → 选择 **构建内核（GKI + AnyKernel3）** → 点击 **Run workflow**。

### 2. 填写参数

| 参数 | 说明 |
|---|---|
| 构建模式 | 常规使用选 `builtin`（编入内核，需刷 boot 分区）；`lkm` 见下节 |
| root 方案 | FinaSU / KernelSU / SukiSU-Ultra / KernelSU-Next 四选一 |
| 机型 | 按上表选择，例如 `android15-6.6` |
| SUSFS | 需要则开启（Android 17 不可用，会自动跳过） |
| 内核调优 | 默认 `safe`，一般无需修改 |
| 附加功能 | BBG 防格机 / 网络增强 / ZRAM LZ4KD，按需开启 |
| 发布 | 开启后生成 Release，可直接下载产物 |

### 3. 下载产物

单次构建约需 **30 分钟至 1 小时**，完成后在 **Releases** 获取：

- `<方案名>-<机型>-GKI-AnyKernel3.zip` — 内核刷机包（`builtin` 模式）
- `<方案名>-Manager-<版本>.apk` — 配套管理器
- `lkm` 模式下产物为 `.ko` 文件

**刷入顺序：先刷内核 zip，重启开机后再安装管理器 APK。**

> `lkm` 模式相反：先安装管理器，再由管理器加载 `.ko`，无需刷写分区。

### 选型建议

| 需求 | 建议 |
|---|---|
| 常规 root | 方案选 `KernelSU`，模式选 `builtin` |
| 功能丰富 | 方案选 `SukiSU-Ultra` |
| 不变动分区 | 模式选 `lkm` |
| 需要隐藏 root 痕迹 | 开启 SUSFS |

其余参数保持默认即可。

### 完整参数列表

<details>
<summary>展开</summary>

| 参数 | 说明 |
|---|---|
| `build_mode` | `builtin` = 编入内核（需刷 boot）/ `lkm` = 编译为 `.ko`（不刷分区）；默认 `builtin` |
| `root_solution` | root 方案，必填（四选一） |
| `kmi` | 机型，必填 |
| `kernel_branch` | 内核源码分支，留空则按机型自动解析 |
| `solution_ref` | 固定 root 源码版本，留空使用最新 |
| `enable_susfs` | 集成 SUSFS |
| `skip_on_patch_failure` | 补丁失败时跳过而不中断构建（不推荐） |
| `kernel_tweaks` | 内核调优档位，默认 `safe` |
| `feature_kpm` | 仅 SukiSU-Ultra：KPM 内核模块，默认关闭 |
| `feature_bbg` | BBG 防格机，默认关闭 |
| `feature_networking` | 网络增强，默认关闭 |
| `feature_zram_lz4` | ZRAM LZ4KD 增强，默认关闭 |
| `collect_fail_logs` | 构建失败时收集日志，默认开启 |
| `make_release` | 构建成功后创建 Release |
| `release_tag` | 自定义版本号，留空自动生成 |

</details>

## 方案差异

4 个方案的内核代码并不完全一致，部分功能为特定方案独有：

| 功能 | FinaSU | KernelSU | SukiSU | KSU-Next | 本项目处理 |
|---|:-:|:-:|:-:|:-:|---|
| root 主体 | ✅ | ✅ | ✅ | ✅ | 全部启用 |
| 动态管理器（更改包名不影响 root） | ✅ | — | — | — | FinaSU 自动启用 |
| 手动提权 | — | — | ✅ | — | SukiSU 自动启用 |
| KPM 内核模块 | — | — | ✅ | — | 需手动开启 `feature_kpm` |
| 调试模式 | ✅ | ✅ | ✅ | ✅ | 不启用 |

> 上表中的调试模式、`KSU_DISABLE_MANAGER`、`KSU_DISABLE_POLICY` 等均不启用 ——
> 它们会禁用管理器或逐应用授权，仅供开发者排查问题。

差异全部声明在 [`config/root-solutions.json`](config/root-solutions.json) 的 `kernel_features`
字段，工作流中不含任何方案名硬编码。

> <details><summary>实现说明</summary>
>
> **KPM**：SukiSU 独有，可在不重编内核的情况下于运行时加载 `.kpm` 补丁文件。
> 上游说明其可能影响系统稳定性，因此默认关闭，需要时手动开启。
>
> **配置项检测**：判断内核编译选项是否存在，**不能依赖 `scripts/config -e` 的返回码** ——
> 现代版本的 `scripts/config` 在符号不存在时会直接将其写入 `.config`，返回码仍为 0。
> 本流程统一先用 `--state` 查询（返回 `undef` 表示不存在），再决定是否启用，最后回读断言。
>
> </details>

## 附加功能（可选）

除 root 主体外，另提供 4 个附加功能。**默认全部关闭，且仅在 `builtin` 模式下生效**
（`lkm` 模式不修改内核代码）。支持情况见
[`config/kernel-extras.json`](config/kernel-extras.json)。

| 功能 | 对应参数 | 默认 | 说明 |
|---|---|:-:|---|
| **BBG 防格机** | `feature_bbg` | 关 | 拦截对**基带、efisp** 等关键分区的非法写入，避免误写导致设备无法开机 |
| **网络增强** | `feature_networking` | 关 | BBRv3 拥塞控制、IPSet、Qdisc、CIFS |
| **ZRAM LZ4KD 增强** | `feature_zram_lz4` | 关 | 将 ZRAM / ZSMALLOC 编入内核，使用 LZ4KD 压缩 |
| **失败日志收集** | `collect_fail_logs` | **开** | 构建失败时自动打包诊断信息并上传 artifact |

### KMI 支持情况

补丁源并非覆盖全部内核版本，**不支持的目标会自动跳过并在日志中说明**：

| 功能 | 5.10 | 5.15 | 6.1 | 6.6 | 6.12 | 6.18 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| BBG 防格机 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 网络增强 | ✅ | ✅ | ✅ | ✅ | ⚠️ 部分 | — |
| ZRAM LZ4KD | ✅ | ✅ | ✅ | ✅ | — | — |

- **网络增强**在 6.12 会先执行 dry-run，失败则整体回退；**6.18 上游无补丁**，直接跳过。
- **ZRAM LZ4KD** 上游补丁仅覆盖至 6.6。
- **BBG 防格机**全部 KMI 可用。
- 5.10 的网络增强需先打 2 个 sysctl 前置补丁，脚本已自动处理。

> 以上功能与 SUSFS 同属增强项，应用失败**不会中断构建**（各自 `continue-on-error`），
> 最终在 Actions 的 **Summary** 页与 `RELEASE_NOTES.md` 中列出「已启用 / 跳过 / 未启用」。

## 两种构建模式

构建时需选择一种模式，区别在于 **root 是开机即生效，还是由模块在运行时加载**。

| | `builtin`（内置） | `lkm`（模块） |
|---|---|---|
| root 位置 | **编入内核**，开机即生效 | `.ko` 文件，由管理器加载 |
| 是否刷写分区 | **是**（boot / init_boot） | **否** |
| 变砖风险 | **有**，机型选错可能无法开机 | 极低，删除文件重启即可恢复 |
| 产物形式 | 刷机 zip | `.ko` 文件 |
| SUSFS 支持 | 支持 | **不支持** |
| 适用场景 | 需要开机即生效的完整 root | 不变动分区 / 模拟器 / 需随时卸载 |

**选择建议**：常规使用选 `builtin`；不希望刷写分区选 `lkm`。

> 两种模式均要求**完整克隆**源码仓库。版本号由提交次数推导，
> 浅克隆会导致版本号错误，管理器将持续提示「需要更新内核」。

> <details><summary>实现说明</summary>
>
> - LKM 模式在 6.12 / 6.18 上必须开启 `CONFIG_CFI_ICALL_NORMALIZE_INTEGERS`，否则模块加载时 CFI 校验失败。
> - 6.18 的 Kbuild 需使用 `MO=` 传递模块源码目录（上游有注释说明），旧写法 `src=` 在 6.18 上无法定位源文件。
>
> 上述两条已在 `scripts/build-lkm.sh` 中处理。
>
> </details>

## 内核调优档位

构建时可选用调优档位，共三档，默认 `safe`。完整清单见
[`config/kernel-tweaks.json`](config/kernel-tweaks.json)。

| 档位 | 说明 | 风险 |
|---|---|---|
| `none` | 不做任何改动，与官方一致 | 无 |
| `safe`（默认） | **仅将功能编入内核，不修改默认设置** —— 例如 BBR、fq_codel、BFQ 编入内核，但开机仍使用原有算法，需手动切换 | 基本无 |
| `smart` | 在 `safe` 基础上**将默认算法改为上述新算法** | 有一定风险，网络与功耗表现可能变化 |

**建议**：常规使用保持 `safe` 或 `none`；仅在明确了解影响时使用 `smart`。

`safe` 档主要编入以下内容：

| 类别 | 内容 | 作用 |
|---|---|---|
| 网络 | BBR、fq_codel、CAKE、BPF 流量分类 | 弱网吞吐与延迟改善，支持流量工具 |
| 存储 | BFQ、Kyber 调度 | 交互优先调度 |
| CPU / 功耗 | schedutil 调频、CPU Boost | 提升响应速度 |
| 内存 | ZRAM、LZ4、ZSTD | 内存压缩，降低低内存卡顿 |
| 编译精简 | 移除调试信息 | **镜像体积减少 30%~50%** |

`smart` 档在此基础上，将 BBR / fq_codel / BFQ / schedutil 设为默认算法，
并关闭与之冲突的旧默认项。

> 若使用 `smart` 后出现耗电增加或卡顿，改回 `safe` 重新构建即可。
> BFQ 在 UFS 4.0 设备上收益有限，个别场景反而增加 CPU 占用。

## 开发者文档

<details>
<summary><b>构建流程、实现细节与已知问题</b></summary>


### 构建链路

```
AOSP kernel/common @ <kmi>-lts
        │
        ├─ <root 方案仓库>（默认完整克隆，保留 .git）
        │     └─ kernel/  → common/drivers/ksu-src/kernel
        │                     （软链为 common/drivers/kernelsu）
        │
        ├─ susfs4ksu @ gki-<av>-<kv> (可选)
        │
        ├─ make gki_defconfig + CONFIG_KSU=y (+ 关 LTO)
        │     └─ apply-tweaks.sh <safe|smart>（网络/功耗调优，可选）
        │
        ├─ make Image
        │
        ├─ WildKernels/AnyKernel3@gki-2.0  → 生成 anykernel.sh → zip
        │     └─ ZIP 合规自检（见下）
        │
        └─ 抓最新 Manager APK（Actions artifact 或 GitHub Release）
```

### 七个关键实现细节

#### 1. 多数方案必须完整克隆（不能 `--depth=1`）

`kernel/Kbuild` 里的版本号推导是：

```make
KSU_VERSION = 30000 + $(git rev-list --count HEAD)
```

浅克隆会让 commit 计数退化成 `1` → `KSU_VERSION=30001`，与真实值不符，
管理器会提示"**需要更新内核**"。实测 FinaSU 当前 master 为 **2794** 个提交 → `KSU_VERSION=32794`，
与官方 Manager APK 文件名里的 `_32792` 完全吻合。

**例外：SukiSU-Ultra** 的算法不同：

```make
VERSION_BASE   := 40000
VERSION_OFFSET := 2815
LOCAL_COUNT    := $(if $(GITHUB_COMMITS),$(GITHUB_COMMITS),$(git_commit_count))
KSU_VERSION    := $(VERSION_BASE) + $(LOCAL_COUNT) - $(VERSION_OFFSET)
```

它支持 `GITHUB_COMMITS` 环境变量覆盖，**不依赖 git 历史**，所以配置里
`needs_git_history: false` → workflow 对它走浅克隆（省时间）。是否浅克隆由配置驱动。

#### 2. 必须把 `.git` 一起放进内核树

`kernel/Kbuild` 用 `git rev-parse --show-toplevel` 判断"是否处于内核仓库之外的独立仓库"：

```make
GIT_ROOT        := $(shell cd $(MDIR) && git rev-parse --show-toplevel)
KERNEL_GIT_ROOT := $(shell cd $(srctree) && git rev-parse --show-toplevel)
ifneq ($(GIT_ROOT),$(KERNEL_GIT_ROOT))   # 只有不同才会设版本号
```

如果只 `cp -a kernel/`（丢掉 `.git`），`GIT_ROOT` 会向上命中 `gki/.git`，
与 `KERNEL_GIT_ROOT` 相同 → **跳过推导 → `KSU_VERSION=16`**。
所以 workflow 把**整个源码仓库**（含 `.git`）复制进 `drivers/ksu-src/`，
再软链 `kernelsu -> ksu-src/kernel`。

> 这也是不直接跑官方 `kernel/setup.sh` 的原因：它会 `git clone tiann/KernelSU`
> 并执行 `git stash/checkout/pull`，对已克隆的本地源码不可靠，而且上游的
> `kernel/` 本身就是自包含的完整内核侧源码树，不需要再去拉上游。

#### 3. 内核靠签名认管理器 —— 所以必须**不**定义 `KSU_MANAGER_PACKAGE`

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

这也是**一个内核能跨 4 个方案识别管理器**的原因：不固化包名，只按签名信任。

**已发生的上游变更（FinaSU）**：Manager 已从 `FolkSU` / `me.yuki.folksu` 改名为
**`FinaSU`** / **`me.yuki.fina`**（PR 构建为 `me.yuki.fina.pr`），**签名证书不变**。
因为本流程不固化包名，改名后的**新** Manager 刷到本流程编译的**旧**内核上
依然会被识别为可信管理器 —— **无需重新编译内核**。

| 时期 | Manager 展示名 | Manager 包名 | 签名 |
|---|---|---|---|
| 最初（FolkSU） | FolkSU | `me.yuki.folksu` | — |
| 过渡（MoeSU） | FolkSU | `me.yuki.folksu` | 不变 |
| **现在（FinaSU）** | **FinaSU** | **`me.yuki.fina`** | **不变** |

> 包名白名单里同时保留了 `me.yuki.fina*` 与历史 `me.yuki.folksu*` / `me.yuki.moesu*`，
> 所以无论抓到的是哪个时期的 Manager APK 都能正确识别，不会因改名而误报。

> 包名相关的引用全在用户态，与内核构建无关：
> `manager/app/build.gradle.kts`（`defaultManagerPackageName` / `defaultManagerName` /
> `resValue app_name`）、`manager/app/src/main/res/values/strings.xml`（`home_tile_manager`）、
> `userspace/ksud/build.rs`（`KSU_PACKAGE_NAME` 环境变量，可覆盖）等。
> 经检索，`kernel/` 目录内**不含**任何包名或展示名硬编码。

可信签名来源：`Kbuild` 里的 `FOLKSU_TRUSTED_HASH ← EXPECTED_HASH`，
由官方用仓库 keystore 签出的 release 证书算出。`apk_sign_keys[]` 里其余
（KernelSU / KowSU / KernelSU-Next / ReSukiSU / SukiSU / MKSU / RKSU / xxKSU）
都只是"**识别但不自动授权**"，需要用户在动态管理器界面手动批准。

> workflow 里会打印 Manager 的包名与签名指纹并做记录，便于跨版本比对。

#### 4. AnyKernel3 ZIP 要做合规自检

上游 ksud 已加固 AnyKernel3 ZIP 校验（见 `userspace/ksud/ANYKERNEL3.md`）：

- 必须**恰好一个** `META-INF/com/google/android/update-binary`
- 顶层必须有 `anykernel.sh`
- 拒绝模块 ZIP、重复条目、绝对路径与 `../` 穿越
- 安装脚本（`update-binary`）体积上限 **4 MiB**

所以打包后 workflow 会调 `scripts/verify-ak3-zip.sh` 做一次自检
（`unzip -Z1` 列条目 → 逐项断言），避免生成"刷不进去"的包。
该脚本可独立运行：`bash scripts/verify-ak3-zip.sh <某个.zip>`。

#### 5. 防格机保护（anti-brick）

生成的 `anykernel.sh` 在**写任何分区之前**做三重闸门检查，任一不符即 `abort`：

| 闸门 | 检查 | 不符后果 |
|---|---|---|
| A1 架构 | `ro.product.cpu.abi` 必须是 `arm64*` / `aarch64` | 直接中止 |
| A2 内核主版本 | 设备 `/proc/version` 的主版本号必须**等于**包内内核（5.10 / 5.15 / 6.1 / 6.6 / 6.12 / 6.18） | 直接中止 |
| A3 分区 | `boot` 或 `init_boot` 至少一个存在且可读 | 直接中止 |

设计原则是**宁可刷不进去，也绝不刷错变砖**。AK3 自带的 `do_check_boot_version`
作为第二道闸保留。A2 是最关键的一条 —— 跨 KMI（例如把 `android15-6.6` 的包刷到
6.1 的设备上）会导致无法开机，这里会提前拦下来。

#### 6. 一加 / OPPO 兼容

一加（OnePlus）与 OPPO（含 realme）在 Android 13+ 的 GKI 机型上有几个共性坑，
脚本里做了运行时分流：

- **独立 `init_boot` 分区**：13+ 一加/OPPO 常把 ramdisk 从 `boot` 搬到 `init_boot`，
  脚本会探测 `init_boot` 是否存在并相应提示；`boot` 内无 ramdisk 时降级为整刷。
- **品牌探测**：同时看 `ro.product.brand` / `ro.product.manufacturer` /
  `ro.separate.soft`（OPPO 系专有属性），命中 `OnePlus` / `OPPO` / `realme` / `oplus`
  即进入兼容分支。
- **AVB / vbmeta**：OPPO/一加 校验较严，`patch_vbmeta_flag=auto` 保留给 AK3 自动判断；
  脚本末尾会提示"若开机卡 logo 可尝试 patch vbmeta / 关闭 avb 校验"。
- **A/B 槽位**：`is_slot_device=auto` + 分区路径自动拼 `ro.boot.slot_suffix`。

> 兼容逻辑只做**分流与提示**，不修改 AK3 本体行为，因此对非一加/OPPO 机型无副作用。

#### 7. LKM 模式用上游自带的树外编译入口

上游每个方案的 `<solution>/kernel/` 目录都自带一套 `Makefile`，它从环境变量取
`KDIR`（内核构建目录）并据此决定 `KBUILD_ARGS`：

```make
ifeq ($(KMI),android17-6.18)
KBUILD_ARGS := M=$(MDIR) MO=$(ODIR)
else
KBUILD_ARGS := M=$(ODIR) src=$(MDIR)
endif
```

所以 LKM 模式**不需要把源码拷进内核树**，只要 `KDIR=<内核树> make` 即可。
`scripts/build-lkm.sh` 做的就是：给 arm64 / x86_64 各准备一份内核构建目录
（`gki_defconfig` + 关 LTO + 6.12/6.18 补 CFI + `modules_prepare` + 生成 SELinux 头），
再分别编译，最后 `llvm-strip -d` 瘦身。

> `llvm-strip -d` 只删调试段、保留符号表 —— 模块加载需要符号，不能整体 strip。

**单个 KMI 约 40–150 分钟**（取决于 runner、构建模式与是否开 SUSFS）。
本流程设计为**一次一个方案 / 一个 KMI**，避免大批量 CI 触发 GitHub 风控。

#### 上游来源

| 组件 | 来源 |
|---|---|
| 内核基座 | `android.googlesource.com/kernel/common` |
| Root 内核 | `LyraVoid/FinaSU`、`tiann/KernelSU`、`SukiSU-Ultra/SukiSU-Ultra`、`KernelSU-Next/KernelSU-Next` |
| Manager APK | 各项目自己的 Actions / Release |
| SUSFS | `ShirkNeko/susfs4ksu` |
| BBG 防格机 | `vc-teahouse/Baseband-guard`（走上游 `setup.sh`） |
| 网络增强 | `WildKernels/kernel_patches@main/common/bbrv3` |
| ZRAM LZ4KD | `ShirkNeko/SukiSU_patch@main/other/zram` |
| AK3 框架 | `WildKernels/AnyKernel3@gki-2.0` |
| LKM 编译方式 | 参考 FinaSU `.github/workflows/ddk-lkm.yml`（本项目改为现场生成 KDIR，不依赖预置 DDK 容器） |
| 参考实现 | `LingLuo17/AnyKernel3@dev`、`ShirkNeko/GKI_KernelSU_SUSFS` |

</details>

## 注意事项

- **刷写内核有变砖风险。** 刷入前请务必备份原厂 `boot.img` / `init_boot.img`。
- **确认机型选择正确。** 错误的 KMI 会导致无法开机，建议先执行 `uname -r` 复核。
- **仅刷入自行构建的包。** 刷机脚本以 root 权限运行，请勿刷入来源不明的包。
- **内核与管理器需匹配。** 4 个方案的产物不可混用管理器，除非签名互通。
- **提示「需要更新内核」**：表示管理器版本高于内核，并非故障。可换用较旧版本的管理器，或重新构建。
- **`lkm` 与 `builtin` 不可共存。** 从 `lkm` 换回 `builtin` 前，需先卸载模块。

## 仓库结构

```
.
├── .github/workflows/build.yml    # 主构建流程（两种模式）
├── config/                        # 配置
│   ├── root-solutions.json        #   root 方案注册表
│   ├── kmi-matrix.json            #   机型 ↔ 内核分支对照表
│   ├── kernel-tweaks.json         #   内核调优清单
│   └── kernel-extras.json         #   附加功能支持矩阵
├── scripts/                       # 脚本
│   ├── resolve-solution.sh        #   解析方案配置
│   ├── resolve-features.sh        #   解析方案独有功能开关
│   ├── fetch-manager.sh           #   获取最新管理器
│   ├── apply-tweaks.sh            #   应用调优
│   ├── apply-extras.sh            #   应用附加功能
│   ├── collect-fail-logs.sh       #   收集失败日志
│   ├── build-lkm.sh               #   编译 LKM 模块
│   └── verify-ak3-zip.sh          #   AK3 包合规校验
└── README.md
```

> <details><summary><b>新增 root 方案</b></summary>
>
> 共两步：在 `config/root-solutions.json` 的 `solutions[]` 中新增一项，
> 并在 `build.yml` 的 `root_solution.options` 中添加同名 id。
> 其余流程（克隆、集成、版本号算法、管理器获取、包名白名单、产物命名）均自动生效。
>
> 此外，本流程设计为**单次构建仅面向一个方案、一个机型**，以避免批量触发 GitHub 风控。
>
> </details>

## License

构建脚本：MIT。集成产物受各上游许可约束（FinaSU / KernelSU 等均为 GPL-3.0，AK3 见其 LICENSE）。

---

<div align="center">

如果这个项目对你有帮助，欢迎点个 Star。

</div>

# GKI Kernel Build — KSU 系列自动构建

自动化构建 **KSU 系列 root 方案** 的 GKI 内核 + AnyKernel3 刷机包 + 配套 root 管理器。

支持 4 个**正式主流**项目（全部有公开仓库、持续维护、社区规模大，非来源不明的小项目）：

| id | 项目 | 仓库 | ★ | 默认分支 | Manager 包名 |
|---|---|---|---|---|---|
| `finasu` | **FinaSU**（原 FolkSU / MoeSU） | `LyraVoid/FinaSU` | 36 | `master` | `me.yuki.fina` |
| `kernelsu` | **KernelSU** | `tiann/KernelSU` | 19k+ | `main` | `me.weishu.kernelsu` |
| `sukisu` | **SukiSU-Ultra** | `SukiSU-Ultra/SukiSU-Ultra` | 6.5k+ | `main` | `com.sukisu.ultra` |
| `kernelsu-next` | **KernelSU-Next** | `KernelSU-Next/KernelSU-Next` | 4.4k+ | `dev` | `com.rifsxd.ksunext` |

> 为什么能共用一套流程？实测四家的 `kernel/Kconfig` 里 `config KSU` 定义**逐字节相同**
> （`tristate` + `depends on KPROBES && EXT4_FS` + `default y`），`kernel/` 目录结构也一致
> （`Kbuild` / `Kconfig` / `setup.sh` + `core/ feature/ hook/ infra/ manager/ policy/ runtime/ selinux/ sulog/ supercall/`）。
> 差异（仓库地址、默认分支、版本算法、Manager 获取方式、包名白名单）全部抽到
> [`config/root-solutions.json`](config/root-solutions.json)，workflow 只是消费它。

> **改名说明（FinaSU）**：项目是 **KernelSU fork**，仓库名经**三次改名**，但一直是
> 同一个仓库（id `1147947994`），旧地址均 301 重定向：
>
> | 时期 | 仓库 | Manager 展示名 | Manager 包名 |
> |---|---|---|---|
> | 最初 | `LyraVoid/FolkSU` | FolkSU | `me.yuki.folksu` |
> | 2026-10 上旬 | `LyraVoid/MoeSU` | FolkSU | `me.yuki.folksu` |
> | **现在** | **`LyraVoid/FinaSU`** | **FinaSU** | **`me.yuki.fina`** |
>
> **签名证书始终未变**（`c371061b...`），所以内核只按签名信任 → 跨版本 Manager 始终可用。

## 这是什么

把所选 root 方案的内核以 **built-in 模式**（`CONFIG_KSU=y`）集成进 Google GKI 内核源码，
编译出完整 `Image`，再用 [AnyKernel3](https://github.com/WildKernels/AnyKernel3) 的 **gki-2.0**
分支打成刷机 zip；同时自动抓取官方最新的 **Manager APK** 一并发布。

与官方 **LKM 模式**（只出 `kernelsu.ko`）不同，本流程产出的是**完整 GKI 内核**，直接刷入 `boot` 分区。

## 支持的 KMI

≥ **5.10** 的全部 GKI 主线（含 Android 17）：

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

### 关于 Android 17

Android 版本与内核版本**不是一一对应**的，所以 A17 有两个 target：

| 你的设备 | 选哪个 KMI |
|---|---|
| A17 系统，`uname -r` 显示 **6.12.x** | `android17-6.12` |
| A17 系统，`uname -r` 显示 **6.18.x** | `android17-6.18` |

**怎么确认**：在 adb shell 里敲 `uname -r`，取前面 `主.次` 两位（如 `6.12.69` → `6.12`）。

> `android17-6.12` 与 `android16-6.12` 编译产物**同源**（都用 `android16-6.12-lts` 分支），
> 差别只在包名与 KMI 标记。所以 A17+6.12 的设备，用这两者任一都能刷。

**SUSFS 在 Android 17 上不可用**：上游 `ShirkNeko/susfs4ksu` 目前最高只有
`gki-android15-6.6`，**没有 6.12 也没有 6.18 分支**。开到 6.12/6.18 时工作流会
自动检测并跳过 SUSFS（日志会明确提示），root 功能本身不受影响。

## 怎么用

1. 进 **Actions** → **Build GKI Kernel + AnyKernel3** → **Run workflow**
2. 选 **root 方案**（`finasu` / `kernelsu` / `sukisu` / `kernelsu-next`）
3. 选 **KMI**（例如 `android15-6.6`）
4. 按需开 **SUSFS**
5. 按需选 **内核调优档位**（`none` / `safe` / `smart`，默认 `safe`）
6. 跑完在 **Releases** 下载：
   - `<方案名>-<KMI>-GKI-AnyKernel3.zip` — 内核刷机包
   - `<方案名>-Manager-<版本>.apk` — 配套管理器
7. 先刷内核 zip，再装 Manager APK

### 输入项

| 输入 | 说明 |
|---|---|
| `root_solution` | root 方案，必填（4 选 1） |
| `kmi` | 目标 KMI，必填 |
| `kernel_branch` | AOSP 分支，留空 = `<kmi>-lts`；也可填 `android15-6.6-2026-10` |
| `solution_ref` | root 源码引用，留空 = 配置里的默认分支（FinaSU `master` / KernelSU `main` / SukiSU `main` / KSU-Next `dev`） |
| `enable_susfs` | 集成 SUSFS 内核补丁 |
| `skip_on_patch_failure` | 补丁失败时跳过（不中断构建） |
| `kernel_tweaks` | 内核调优档位，见下节；默认 `safe` |
| `make_release` | 成功后创建 Release |
| `release_tag` | 自定义 tag，留空自动生成 |

## 内核调优档位（`kernel_tweaks`）

> **先说清楚**：这一节的内容**不是** KernelSU / SUSFS 的功能。
> 我逐条读过上游 FinaSU 的 `kernel/Kconfig`（只有 6 个 `KSU*` 项）和 SUSFS 补丁
> （只有 11 个 `KSU_SUSFS_*` 项，全是「隐藏/伪装」类）——**两边都没有任何网络或功耗相关开关**。
> 「优化网络功耗」只能在内核自身的 defconfig 层面做，所以有了这个档位。

完整清单在 [`config/kernel-tweaks.json`](config/kernel-tweaks.json)，共 58 条，分五组：
网络 / 存储 / CPU·功耗 / 内存 / 编译精简。三档语义：

| 档位 | 做什么 | 风险 |
|---|---|---|
| `none` | 完全不动，保持 AOSP GKI 原样 | 无 |
| `safe` | **只启用可选能力，不改任何默认值**。只是把 BBR、fq_codel、BFQ、各种调频器等编译进内核，开机默认行为一字不变，需用户手动切换才生效 | 理论为零 |
| `smart` | 在 `safe` 之上，把更优算法设为**系统默认**（BBR / fq_codel / schedutil / BFQ），并调 `MMC_BLOCK_MINORS` | 改变默认行为 |

`safe` 档典型内容（44 条）：

| 组 | 代表项 | 作用 |
|---|---|---|
| 网络 | `TCP_CONG_BBR`、`NET_SCH_FQ_CODEL`、`NET_SCH_CAKE`、`NET_CLS_BPF` | 弱网吞吐、降延迟、支持流量工具 |
| 存储 | `IOSCHED_BFQ`、`MQ_IOSCHED_KYBER` | 交互优先调度，滑动跟手 |
| CPU·功耗 | `CPU_FREQ_GOV_SCHEDUTIL`、`CPU_BOOST` | 能耗感知调频，点击响应 |
| 内存 | `ZRAM`、`CRYPTO_LZ4`、`CRYPTO_ZSTD` | 内存压缩交换，低内存防卡顿 |
| 编译精简 | `DEBUG_INFO_NONE`、`DEBUG_LIST` 关闭 | Image 体积降 30%~50% |

`smart` 档额外内容（14 条）：把 `DEFAULT_TCP_CONG_BBR` / `DEFAULT_FQ_CODEL` /
`DEFAULT_BFQ` / `DEFAULT_SCHEDUTIL` 打开，同时关掉互斥的旧默认项
（`DEFAULT_TCP_CONG_CUBIC` / `DEFAULT_FQ` / `DEFAULT_MQ_DEADLINE` / `DEFAULT_PERFORMANCE`），
`ZRAM_DEF_COMP_LZ4` 设为 zram 默认算法。

三条工程约束：

1. **必须在 `olddefconfig` 之前执行** —— 否则选中的 `DEFAULT_*` 会被 Kconfig
   依赖关系重置回默认值。
2. **不存在的配置项自动跳过**。各 KMI（5.10 ~ 6.12）的 Kconfig 有差异，
   脚本只记日志不报错，实测 44 条里通常有一半以上在某代内核上不存在。
3. **单条失败不中断构建**。调优是锦上添花，不该拖垮主流程。

> 如果刷了 `smart` 档后觉得耗电变快 / 卡顿 / 信号异常，改回 `safe` 档重新构建即可。
> BFQ 在 UFS 4.0 设备上收益不明显，个别场景反而增加 CPU 占用。

## 构建链路

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

## 六个关键实现细节

### 1. 多数方案必须完整克隆（不能 `--depth=1`）

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

### 2. 必须把 `.git` 一起放进内核树

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

### 3. 内核靠签名认管理器 —— 所以必须**不**定义 `KSU_MANAGER_PACKAGE`

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

### 4. AnyKernel3 ZIP 要做合规自检

上游 ksud 已加固 AnyKernel3 ZIP 校验（见 `userspace/ksud/ANYKERNEL3.md`）：

- 必须**恰好一个** `META-INF/com/google/android/update-binary`
- 顶层必须有 `anykernel.sh`
- 拒绝模块 ZIP、重复条目、绝对路径与 `../` 穿越
- 安装脚本（`update-binary`）体积上限 **4 MiB**

所以打包后 workflow 会做一次自检（`unzip -Z1` 列条目 → 逐项断言），
避免生成"刷不进去"的包。

### 5. 防格机保护（anti-brick）

生成的 `anykernel.sh` 在**写任何分区之前**做三重闸门检查，任一不符即 `abort`：

| 闸门 | 检查 | 不符后果 |
|---|---|---|
| A1 架构 | `ro.product.cpu.abi` 必须是 `arm64*` / `aarch64` | 直接中止 |
| A2 内核主版本 | 设备 `/proc/version` 的主版本号必须**等于**包内内核（5.10 / 5.15 / 6.1 / 6.6 / 6.12 / 6.18） | 直接中止 |
| A3 分区 | `boot` 或 `init_boot` 至少一个存在且可读 | 直接中止 |

设计原则是**宁可刷不进去，也绝不刷错变砖**。AK3 自带的 `do_check_boot_version`
作为第二道闸保留。A2 是最关键的一条 —— 跨 KMI（例如把 `android15-6.6` 的包刷到
6.1 的设备上）会导致无法开机，这里会提前拦下来。

### 6. 一加 / OPPO 兼容

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


**单个 KMI 约 40–150 分钟**（取决于 runner 与是否开 SUSFS）。
本流程设计为**一次一个方案 / 一个 KMI**，避免大批量 CI 触发 GitHub 风控。

## 上游来源

| 组件 | 来源 |
|---|---|
| 内核基座 | `android.googlesource.com/kernel/common` |
| Root 内核 | `LyraVoid/FinaSU`、`tiann/KernelSU`、`SukiSU-Ultra/SukiSU-Ultra`、`KernelSU-Next/KernelSU-Next` |
| Manager APK | 各项目自己的 Actions / Release |
| SUSFS | `ShirkNeko/susfs4ksu` |
| AK3 框架 | `WildKernels/AnyKernel3@gki-2.0` |
| 参考实现 | `LingLuo17/AnyKernel3@dev`、`ShirkNeko/GKI_KernelSU_SUSFS` |

## 风险提示

- 刷内核**可能变砖**。刷前务必备份原厂 `boot.img` / `init_boot.img`。
- 内置模式与 LKM 模式**不可共存**；从 LKM 转内置前请先还原原厂镜像。
- AK3 脚本以 root 运行，请只刷可信包。
- Manager 版本与内核版本不一致时会提示"需要更新内核"，这时把 `solution_ref`
  固定到该 Manager 对应的 commit 即可对齐。
- 4 个方案产出的内核**只能配各自的管理器**（或签名互通的管理器）；
  不要把一个方案的内核配上另一个方案的管理器。

## 仓库结构

```
.
├── .github/workflows/build.yml    # 主构建流程
├── config/root-solutions.json     # root 方案注册表（唯一需要改的地方）
├── config/kmi-matrix.json         # KMI 分支对照表
├── config/kernel-tweaks.json      # 内核调优清单（网络/功耗/存储/内存/编译精简）
├── scripts/resolve-solution.sh    # 解析 root 方案配置 → workflow 输出
├── scripts/fetch-manager.sh       # 自动抓取最新 Manager APK
├── scripts/apply-tweaks.sh        # 按档位把调优项写进 .config
└── README.md
```

### 新增一个 root 方案

只需在 `config/root-solutions.json` 的 `solutions[]` 里加一项，并在
`build.yml` 的 `root_solution.options` 里加一个同名 id。
其余（克隆、集成、版本算法、Manager 获取、包名白名单、产物命名）全部自动生效。

## License

构建脚本：MIT。集成产物受各上游许可约束（FinaSU / KernelSU 等均为 GPL-3.0，AK3 见其 LICENSE）。

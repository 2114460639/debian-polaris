# 小米 MIX 2S（xiaomi-polaris）Debian 13 刷机包 —— 无 GUI 控制台版

面向小米 MIX 2S 的 **Debian GNU/Linux 13 (trixie) aarch64** 成品镜像：开机直接进入
Linux framebuffer 终端，屏幕底部常驻一个全尺寸虚拟键盘（fbkeyboard），触摸即可打字。

本版本定位为**追求稳定的英文控制台系统**：界面语言英文 `en_US.UTF-8`，**无任何图形界面**
（不含 phosh / phoc / greetd / display-manager），**内核层面已无摄像头**，并把全部
设备适配（网络、音频、按键、ADB、固件）固化进镜像，开机即用，无需首启配置。

- 发行版：Debian GNU/Linux 13.7 (trixie)，aarch64，约 381 个包
- 内核：postmarketOS 的 `linux-postmarketos-qcom-sdm845` **7.1_rc1-r61**
  （版本串 `7.1.0-rc1-sdm845`，`#62`），同一份内核与设备树；
  在上游基础上打了 fbdev 背缓冲、fbcon 回滚、**WiFi 关机死锁**、**USB OTG / Type-C / PD**
  四处补丁，见 [kernel/README.md](kernel/README.md)
- 构建方式：**官方 Debian 源 + debootstrap**（非 Mobian），第三方预编译件仅为
  pmOS 内核/固件、静态 adbd、fbkeyboard 与 `polaris-keys`

> 刷机会**清空 userdata 分区**，手机内所有数据（照片、文档等）都会丢失，请先备份。

## 功能支持一览

图例：**Y** = 正常可用，**P** = 部分可用，**N** = 不可用。标「本次」的是本轮镜像更新新增/改动的能力。

| 功能 | 状态 | 注释 |
| -------------- | :--: | ---------------------------------------------------------------------------------- |
| Screen 屏幕 / Touch 触控 | P | ✅ 开机直入 fbcon 控制台，Terminus **16x32** 大字（console-setup 原生机制，非 pmOS 那套 drop-in）；触摸只用于屏幕下半部的 fbkeyboard 虚拟键盘，无图形手势 |
| 3D GPU | Y | ✅ 本次内置 `libvulkan1` + `mesa-vulkan-drivers`（turnip / freedreno ICD），`fastfetch` 直接显示 `GPU: Qualcomm Turnip Adreno (TM) 630 [Integrated]`；`a630_zap.mbn` 固件单拷贝 + DT 派生路径相对软链，dmesg 0 错 |
| Wifi Wi‑Fi | Y | ✅ WCN3990 固件按内核标准路径放置；`ath10k_snoc` 经 QMI WLFW 绑定，5GHz 满速 AC 866.7 Mbps；`iperf3` 上行 / 下行 ≈686 Mbps、0 重传 |
| Bluetooth 蓝牙 | Y | ✅ WCN3990 固件（`crbtfw21.tlv` + 设备专属 `qca/polaris/crnv21.bin`）下载完成后控制器正常启动：`hciconfig -a` 为 **UP RUNNING**、`bluetoothctl scan on` 可发现周边设备；MAC 由 bootmac 固定；并已内置 `pulseaudio-module-bluetooth`，蓝牙耳机 / 音箱（A2DP）可用 |
| Modem 移动数据 4G | Y | ✅ 插卡即用：`polaris-modem-uim` 先建 UIM primary GW 会话，ModemManager 达 `registered`；与 Wi‑Fi 并存时**优先 Wi‑Fi**（route-metric 600 vs 20000），Wi‑Fi 断开 4G 自动接管 |
| Audio 音频 | Y | ✅ DTS 音频节点 + ALSA UCM（Polaris-HiFi）一层，PulseAudio 开机接管；扬声器 / 麦克风、`pactl` 音量键调音均正常 |
| Swap 内存交换 zram | Y | ✅ **本次新增**：开机自动建 **4 GiB / zstd** 压缩的 `/dev/zram0`（`polaris-zram-swap.service`，priority 100）；`vm.swappiness=180`、`vm.page-cluster=0`；`free -h` Swap 显示 4.0 GiB |
| USB Net USB 网络 | Y | ✅ 设备侧固定 `172.16.42.1/24` + 内置 DHCP，插线电脑即得 `172.16.42.2`；由 systemd-networkd 管理，与 NetworkManager 不打架 |
| USB OTG USB 主机 / Type-C PD | Y | ✅ **本次新增**：DWC3 由 `peripheral` 改为 `otg`（`usb-role-switch`），Type-C 连接器按 CC 自动判定角色 —— 插 U 盘 / 键鼠即可当 **USB 主机**；PMI8998 的 Type-C/PD 能力已补齐（VBUS 调节器 + TCPC + PD PHY），支持 **PD 边充边用 / 电源角色自动切换**，见 [kernel/README.md](kernel/README.md) 改动 4 |
| ADB 直连 | Y | ✅ 内置静态 adbd 开机自启；`adb shell` 直接得到 `root@polaris:~#` 并默认位于 `/root`，方向键 / Ctrl-C 行编辑正常 |
| SSH | Y | ✅ 默认开启（`ssh user@172.16.42.1`）；主机密钥首启自动生成（自建 `polaris-ssh-keygen.service` 绕过 Debian `ConditionFirstBoot` 陷阱） |
| Keyboard 虚拟键盘 | Y | ✅ fbkeyboard 常驻下半屏、uinput 注入；`Bcksp` 与方向键长按连发（0.4 s 后 / 每 80 ms）；隐藏格右上 / 右下发 `Shift+PgUp` / `Shift+PgDn` 回滚控制台日志 |
| Keys 电源 / 音量键 | Y | ✅ 电源键循环亮度 40% → 80% → 熄屏；音量键短按注入 `↑` / `↓`、长按调 PulseAudio 音量 |
| Polkit 普通用户免密管理网络 | Y | ✅ **本次新增**：`/etc/polkit-1/rules.d/49-polaris-network.rules` 把 `org.freedesktop.NetworkManager.*` 全部动作授予 `netdev` / `sudo` 组，`user` 免 sudo 即可 `nmtui` / `nmcli` |
| Suspend 挂起 / 休眠 | N | ⛔ 已整体禁用（`IdleAction=ignore` + mask `sleep.target` 等）；空闲 10 分钟仅按 `consoleblank=600` 熄屏，不改系统状态 |
| Camera 摄像头 | N | ⛔ 本版本刻意为之：内核与设备树层面已移除，不可用 |

## 目录结构

```
debian-polaris/
├── README.md                    本文档：刷机 + 全部适配方法
├── flash.sh                     Linux 一键刷机脚本
├── flash.bat                    Windows 一键刷机脚本
├── images/
│   ├── boot.img                 内核 + 设备树 + initramfs（刷到 boot 分区）
│   ├── xiaomi-polaris.img       系统镜像，刷到 userdata 分区
│   │                            （**内容是 Android sparse 格式**，不是 raw ext4，
│   │                            不要拿去 loop 挂载 / e2fsck）
│   └── *.md5                    镜像校验值
├── kernel/                      内核方法：fbcon 回滚 / WiFi 关机死锁补丁、APKBUILD、内核 config
│   └── README.md                构建步骤与三处改动说明
├── rootfs/                      镜像内定制的配置文件（保持原始路径）
│   ├── etc/systemd/system/      fbkeyboard / polaris-* / qc-* 单元、睡眠 mask
│   ├── etc/systemd/network/     usb0 固定 172.16.42.1
│   ├── etc/NetworkManager/      WiFi MAC 固定、usb0 不交给 NM、4G 连接 Mobile4G
│   ├── etc/polkit-1/rules.d/    普通用户免密管理 NetworkManager
│   ├── etc/issue               登录界面来源标注（Build by …debian-polaris）
│   ├── usr/sbin/polaris-modem-uim  建立 UIM primary GW provisioning session
│   ├── usr/bin/bootmac          WiFi/蓝牙 MAC 固定脚本
│   └── usr/lib/udev/rules.d/    bootmac 触发规则
├── scripts/
│   ├── mk_sparse_fill.py        raw → Android sparse（RAW+FILL，无空洞）
│   ├── repack_boot.py           只换 boot.img 的 kernel 段
│   └── apply_local_overlay.sh   把 local/rootfs/ 注入 raw ext4 镜像（本机私有配置）
├── local/                       本机私有 overlay（**不进 git**，结构与 rootfs/ 一致）
│   └── rootfs/                  WiFi 密码等敏感配置，只在本机构建时注入镜像
├── fbkeyboard/                  虚拟键盘源码（fbkeyboard.c + Makefile）
├── tools/
│   ├── linux/    adb、fastboot、lib64、51-android.rules（udev 规则）
│   └── windows/  adb.exe、fastboot.exe 及所需 DLL
└── drivers/
    └── windows/usb_driver/      Google USB 驱动（Windows 识别 fastboot 设备用）
```

> 原始 raw ext4 镜像不随刷机包携带，统一放在编译产物目录
> `/home/wxs/debian-polaris/out/xiaomi-polaris.grown.img`（分区全尺寸 57 GiB 的稀疏文件），
> 需要 loop 挂载 / e2fsck 检查时用那份。

## 镜像从哪来

仓库里**只放方法**（脚本、文档、补丁、配置），镜像和第三方二进制统一发在
[Release v1.0](https://github.com/2114460639/debian-polaris/releases/tag/v1.0)：

| 资产 | 大小 | 说明 |
| --- | --- | --- |
| `debian-polaris-flash-console.7z` | 403 MiB | **完整刷机包**（内容合计约 1.63 GiB，7z LZMA2 压到约 24%）|
| `debian-polaris-flash-console.7z.sha256` | 98 B | 校验值 |

7z 里包含全部刷机所需：

- `images/boot.img`（25 MiB）、`images/xiaomi-polaris.img`（1.57 GiB，**Android sparse 格式**）、`images/*.md5`
- `flash.sh` / `flash.bat`
- `tools/`（adb、fastboot）、`drivers/`（Windows USB 驱动）
- `kernel/` `rootfs/` `scripts/` `fbkeyboard/`（与仓库同源的适配方法）

```bash
sha256sum -c debian-polaris-flash-console.7z.sha256
7z x debian-polaris-flash-console.7z
cd debian-polaris-flash-console && ./flash.sh     # 输入 yes
```

> 为什么压成 7z：GitHub 单文件上限 100 MB，1.6 GiB 的镜像没法直接放仓库；
> 打成一个 7z 既绕开限制，又只有原来的 24%，慢速网络也传得动。
> 解压后的 `images/*.md5` 可以直接 `md5sum -c` 再校验一遍。

`tools/`、`drivers/` 是第三方二进制（**二进制 + 第三方许可证**），不进 git。
如果你是 `git clone` 拿的仓库（没下载 Release），需要自行准备：

- Linux：`sudo apt install android-tools-adb android-tools-fastboot`
- Windows：下载 [platform-tools](https://developer.android.com/tools/releases/platform-tools)
  解压到 `tools/windows/`，驱动用 `drivers/windows/usb_driver/`

`flash.sh` 在随包工具不存在时会自动回退到系统 `PATH` 里的 fastboot / adb。

## 刷机步骤

1. 用数据线连电脑，直接运行脚本即可：
   - Linux：`./flash.sh`
   - Windows：双击 `flash.bat`（首次需先装 `drivers/windows/usb_driver` 里的驱动）
2. 脚本按三级顺序自动找设备，**不需要你手动进 fastboot**：
   1. 先看有没有 fastboot 设备，有就直接开始刷；
   2. 没有就看有没有 adb 设备，有就 `adb reboot bootloader`，然后每秒探测一次、
      最多等 60 秒等它进入 fastboot；
   3. adb 也没有、或 60 秒后仍未进 fastboot，才提示你手动进入
      （音量下 + 电源）。
3. 输入 `yes` 确认后脚本会依次：刷 `boot` → **`fastboot erase userdata`** → 刷系统镜像
   → 用 `fastboot reboot` 引导系统（失败自动退回 `fastboot continue`）。`erase` 是必须的
   （原因见下方「手动刷机」的说明），只要约 6 秒。**引导阶段可能较慢**：设备要把刚刷入的
   数据落盘到 UFS，可能持续几分钟。**首次开机**会自动把根文件系统扩容到整块 `userdata`
   （并生成 SSH 主机密钥），约 1~2 分钟。

### Windows 驱动安装（仅首次）

设备管理器里找到带感叹号的 `Android` 设备 → 右键「更新驱动程序」→「浏览我的电脑」→
选择 `drivers/windows/usb_driver` 目录。

### Linux 权限

若提示 `no permissions`，安装随包的 udev 规则：

```bash
sudo cp tools/linux/51-android.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 手动刷机（不用脚本）

```bash
fastboot flash boot     images/boot.img
fastboot erase  userdata      # 必须先清空分区，见下方说明
fastboot flash userdata images/xiaomi-polaris.img
fastboot reboot               # 若卡住/失败，再执行 fastboot continue
```

> **刷 userdata 之前必须先 `fastboot erase userdata`。**
> 本机 bootloader **从不写入全零数据**：FILL chunk 整个跳过，连 RAW chunk 里的全零块也
> 一样跳过（用 `cmp` 比对刷写前后的设备数据验证过，与 chunk 大小、类型都无关）。
> erase 走 discard、只要约 6 秒，清完之后被 bootloader 跳过的零区本来就是零，文件系统
> 才与镜像一致。不 erase 直接覆盖刷写的话，旧 Android 数据会留在「镜像要求为 0」的位图区，
> 每次开机 e2fsck 都报
> `ext2fs_check_desc: Corrupt group descriptor: bad block for block bitmap`
> 并强制约 3.5 分钟的全盘检查。
>
> **`images/xiaomi-polaris.img` 名字叫 `.img`，内容其实是 Android sparse 镜像**
> （按官方 postmarketOS 刷机包格式预先做好：只有 RAW/FILL chunk、没有 don't-care）。
> fastboot 会原样发给 bootloader 原生解析，可正常启动。别拿它当 raw 镜像去 loop 挂载 /
> e2fsck；需要 raw 镜像（loop 挂载、e2fsck 检查）时去编译产物目录取
> `/home/wxs/debian-polaris/out/xiaomi-polaris.grown.img`。
>
> 千万别换成 raw ext4 镜像让 fastboot 现场转换：现场转换会把全零块当成 don't-care 空洞，
> 实际写进 userdata 的内容会与镜像不一致。
>
> `boot.img` 的 cmdline 带 `fsck.repair=yes`：轻微不一致会自动 `fsck -y` 修复后继续
> 启动。
>
> **刷完后用 `fastboot reboot` 引导系统**（脚本里也用 `timeout 60` 兜底，超时或失败则
> 自动退回 `fastboot continue`）。本机 bootloader 偶发「接受了 `fastboot reboot` 命令、
> 复位后却**回落进 fastboot、进不了系统**」的情况，宿主侧 fastboot 进程也可能一直卡住
> 不返回（实测 15 分钟仍不返回），所以脚本对 `reboot` 加了 60 秒超时；`fastboot continue`
> 则是让 ABL 直接引导刚刷入的镜像，作为兜底。引导阶段设备要把刚刷入的数据落盘到 UFS，
> **可能持续几分钟**（刷机传输被背压时更明显），屏幕可能先黑后亮，属正常现象。若手机仍停在
> fastboot，**长按电源键 12~15 秒**物理复位即可（数据已经写完了，不会丢）。

## 系统功能介绍

- **开机即终端**：启动后屏幕就是 Linux framebuffer 控制台，最后停在 `polaris login:` 提示符（tty1）。
- **登录界面标注来源**：登录提示符上方显示一行 `Build by https://github.com/2114460639/debian-polaris`，
  由 `/etc/issue`（本地 console）与 `/etc/issue.net`（远程）提供，说明镜像来源。
- **登录账号**：
  - 普通用户 `user`，密码 `password`（uid 1000，可登录）；
  - `root` 密码已锁定，请用 `sudo`；`user` 已在 sudo 白名单中，**任意命令免密**
    （由 `/etc/sudoers.d/00-user-nopasswd` 提供，随镜像固化）。
  - 登录后主机名是 `polaris`；会话由 logind 正常管理（镜像含 `libpam-systemd`，
    `loginctl list-sessions` 可见会话，`user@1000.service` 正常）。
- **常驻虚拟全键盘（fbkeyboard）**：在屏幕下半部分绘制 QWERTY 全键位键盘，通过 uinput
  注入按键，开机自启（`fbkeyboard.service` 已 enable），触摸/指针均可点击。
  - 键盘**上方**那条区域是隐藏的 3×3 导航格（无视觉提示，直接点即可）：
    上排 `Home / ↑ / 日志上翻`、中排 `← / Enter / →`、下排 `End / ↓ / 日志下翻`；
    注意正中间是 `Enter`，容易误触。
  - 隐藏格**右上 / 右下**两键是**滚动控制台日志**：发送 `Shift+PageUp` / `Shift+PageDown`，
    点一下向上/向下翻一屏，可回看之前的输出。
    注意：主线 fbcon **没有实现** `con_scrolldelta`（`struct consw fb_con` 缺这一项），
    所以原生内核下这两个键按下去毫无反应。本包内核打了自研补丁
    `fbcon-scrollback.patch`：内核里加一条环形历史缓冲（4096 行），`fbcon_scroll()`
    在整屏上滚时把被顶出的行存进去，再注册 `fb_con.con_scrolldelta` —— 收到回滚请求
    就按「历史行 + 实时内容」整屏重绘（按属性分段 `putcs`，与 `fbcon_redraw()` 同款）。
    新的控制台输出会自动落回实时画面，切 VT 也会归零；历史缓冲只在
    `fbcon_init`/`fbcon_resize` 这类可睡眠上下文里分配，滚动路径零分配。
    内核版本 `7.1.0-rc1-sdm845 #62-postmarketos-qcom-sdm845`（pkgrel 61）。
  - 另外还有 `Esc / Tab / F10` 与 `Shift / Ctrl / Alt` 等功能键行。
  - **长按连发**：`Bcksp` 与四个方向键（`↑ ↓ ← →`）按住不放会持续生效——按住约 0.4 秒
    后开始连发（约每 80 毫秒一次），松手即停；其余按键仍是抬手触发一次。
- **大号控制台字体**：内核内置字体 8x16 在 1080×2160 屏上约 135 列 × 90 行，字非常小；
  本镜像改用 Terminus **16x32**（正好 2 倍），约 67 列 × 44 行。开机自动生效：
  - 主机制：`/etc/default/console-setup` 设为 `FONTFACE="Terminus" FONTSIZE="16x32"`，
    CHARMAP=UTF-8 → CODESET=Uni2，故开机由 udev 在 framebuffer 控制台注册阶段执行
    `/etc/console-setup/cached_setup_font.sh` 加载
    `/usr/share/consolefonts/Uni2-Terminus32x16.psf.gz`（文件名是「高x宽」= 32 高 × 16 宽）；
  - 保险：`fbkeyboard.service` 的 drop-in 在 `console-setup.service` 之后再对 `/dev/tty1`
    显式 `setfont`，确保登录用的那个控制台一定是大字体。
- **电源键 / 音量键**（`polaris-keys.service`）：
  - **电源键**：按一次循环亮度 40% → 80% → 熄屏 → 回到 40% …（开机若亮度过低会自动提到 40%）；
  - **音量上/下**：短按 = 终端中注入 `↑` / `↓` 方向键；长按 = 调节音量（PulseAudio）。
- **永不挂起 / 十分钟熄屏**：
  - `logind` 已设 `IdleAction=ignore`、`IdleActionSec=0`，盖子/挂起/休眠键全部忽略，
    `suspend` / `hibernate` / `hybrid-sleep` / `suspend-then-hibernate` / `sleep.target`
    均已 mask 到 `/dev/null`，系统**永不挂起或休眠**；
  - 内核命令行加 `consoleblank=600`：空闲 10 分钟后**只关闭屏幕背光**（不改系统状态），
    按任意键即点亮；`HandlePowerKey=ignore` 把电源键让给 `polaris-keys` 循环亮度，
    不会因误按关机。
- **联网**：
  - **USB 网络**：设备侧固定 `172.16.42.1/24`，并自带 DHCP 服务，电脑插上线一般会自动
    拿到 `172.16.42.2`；由 systemd-networkd 管理 `usb0`（NetworkManager 已通过
    `unmanaged-devices` 忽略 `usb0`，两边不打架）。
  - **Wi‑Fi**：NetworkManager 已启用，自带 `nmtui`、`nmcli`、`iw`、`rfkill` 等；
    `wpa_supplicant`、`bluetooth` 也已启用。
    WCN3990 固件按**内核实际查找的标准路径**放置：`ath10k/WCN3990/hw1.0/{board-2.bin,
    firmware-5.bin,wlanmdsp.mbn}`、`qca/crbtfw21.tlv`、`qca/crnv21.bin`、`regulatory.db(.p7s)`、
    `qcom/a630_{gmu.bin,sqe.fw}`。此前这些只以 `postmarketos/` 前缀存在（内核不搜索该前缀），
    导致 `ath10k_snoc` 不绑定、无 `wlan0`、dmesg 报 `error -2`。
  - **普通用户可直接改网络（无需 sudo）**：`user` 已在 `netdev` / `sudo` 组，镜像另加
    `/etc/polkit-1/rules.d/49-polaris-network.rules`，把 `org.freedesktop.NetworkManager.*`
    下的**全部动作**授予这两个组。因此不必 `sudo`，`user` 即可 `nmtui` / `nmcli` 连接 Wi‑Fi、
    开关 Wi‑Fi 与移动数据 radio、连接/断开设备、扫描、增删改连接、改主机名/DNS 等。
    背景：NetworkManager 自带规则只放开 `settings.modify.system`，且限定
    `subject.local && subject.active`（本地会话）；其余动作默认 `auth_admin`，
    而本系统没有图形 polkit agent，一旦落到 `auth_admin` 就直接失败。
    验证：以 `user` 身份执行 `nmcli general permissions`，应全部为 `yes`。
  - **WiFi 依赖基带（MPSS）的完整链路**（缺一环都会导致 `wlan0` 不出现，dmesg 无任何
    ath10k 报错、`nmcli` 里没有 wifi 设备）：`ath10k_snoc` 绑定后要等 QMI **WLFW 服务(0x45)**，
    该服务由基带提供，且基带启动后要靠 **QRTR TFTP** 拉取 `wlanmdsp.mbn` 才会注册它。
    本镜像开机自动跑齐这条链：
    `qc-tqftpserv.service`（QRTR TFTP，供基带取 `wlanmdsp.mbn`/`mcfg`）、
    `qc-pd-mapper.service`（TZ PIL 映射）、`qc-rmtfs.service`（基带 EFS）、
    `polaris-modem.service`（前三个就绪后 `echo start > /sys/class/remoteproc/remoteproc2/state`
    启动 MPSS）。验证：`systemctl is-active qc-tqftpserv polaris-modem` 均为 active、
    `cat /sys/class/remoteproc/remoteproc2/state` 为 running、`ip link show wlan0` 存在。
    这三个守护进程是 pmOS 的 musl 二进制，放在 `/usr/lib/qc-mesh/`（自带 musl 运行时），
    由 `Environment=LD_LIBRARY_PATH=/usr/lib/qc-mesh` 运行，不污染系统 glibc 库。
  - **WiFi/蓝牙 MAC 固定**（bootmac）：`wlan0`/`hci0` 出现时由 udev 规则
    `90-bootmac-{wifi,bluetooth}.rules` 拉起 `bootmac@.service`，脚本 `/usr/bin/bootmac`
    从内核 cmdline 的 `androidboot.serialno` 派生确定性 MAC（本地管理地址，前缀 `02:00:`），
    例如本机 `wlan0 = 02:00:45:4c:08:31`；不再每次开机随机。
    验证：`cat /sys/class/net/wlan0/address` 开机两次应一致。
  - **移动数据（4G / SIM）**：插卡即可上网，与 Wi‑Fi 并存时**优先走 Wi‑Fi**。
    镜像内置 ModemManager 1.24 + libqmi/libmbim + qrtr-tools，并在开机时跑
    `polaris-modem-uim.service`（在 `ModemManager.service` 之前）。
    该服务的由来是本机基带的一处固件行为：MPSS 启动后**不会自动建立 UIM 的
    "primary GW provisioning session"**（`--uim-get-card-status` 里 `index_gw_primary=65535`），
    于是 ModemManager 初始化时报 `GW primary session index unknown` 并直接判
    `sim-missing`、modem `failed`。修复办法是用
    `qmicli -d qrtr://0 --uim-change-provisioning-session=session-type=primary-gw-provisioning,activate=yes,slot=1,aid=<USIM AID>`
    显式激活会话（**必须带 USIM 的 AID**，不带会报 `could not power off SIM: QMI protocol error (3)`）；
    脚本会先等 QMI 服务就绪、再等 SIM 出现，**没插卡就直接退出、不启用 4G**。
    会话建好后 modem 达到 `registered`（LTE home），`Mobile4G`（NetworkManager 的 gsm 连接，
    空 APN → 按 SIM 的 MCC/MNC 自动选网）即可拨号，数据面是 IPA 上的
    `qmapmux0.0@rmnet_ipa0`（需 `rmnet` 模块，已由 `modules-load.d/polaris.conf` 加载）。
    **优先级**：Wi‑Fi 的 route-metric 是默认的 600，`Mobile4G` 显式调大到 **20000**，
    故只要连着 Wi‑Fi 就优先走 Wi‑Fi（`ip route get 1.1.1.1` 落在 wlan0）；Wi‑Fi 一断开，
    4G 立刻成为默认路由自动接管（`autoconnect=true`，无 Wi‑Fi 时无需手动切换），DNS 也随
    链路切换。把 4G 的跃点设得更大是为了确保它只在没有更优链路时才真正被选用。
    验证：`mmcli -m 0`（state registered）、`nmcli connection show --active`、
    `ip route get 1.1.1.1`。
  - **SSH**：默认开启，`ssh user@172.16.42.1`，密码 `password`。主机密钥在首启自动生成
    （镜像内不含任何密钥，machine-id 亦为空），由自建的 `polaris-ssh-keygen.service` 负责：
    Debian 自带的 `sshd-keygen.service` 依赖 `ConditionFirstBoot=yes`，而 systemd 启动时会
    先把空的 `/etc/machine-id` 填上，导致该条件恒为假、主机密钥永不生成，本镜像已绕过。
  - **ADB 直连**：内置静态 `adbd`（`polaris-adbd.service` 开机自启，复用 pmOS 的
    functionfs 接线脚本），USB 线插电脑即可 `adb devices` / `adb shell` / `adb push` / `adb pull`，
    与 NCM 网络共存、互不影响。
    `adb shell` 已可直接得到 `root@polaris:~#` 提示符并默认位于 `/root`、方向键/Ctrl-C 行编辑正常。
    原理：adbd 硬编码 `exec("/bin/sh", "-")`，故把 `/bin/sh` 指向 `bash`，并在
    `polaris-adbd-setup` 里 `export ENV=/root/.adbshrc`——bash 以 `sh` 名运行时是 POSIX 模式，
    只读 `$ENV`（不读 `.bashrc`/`/etc/bash.bashrc`），由该文件设置提示符并 `cd /root`。
- **蓝牙**：BlueZ 5.82 开机自启；WCN3990 固件（`qca/crbtfw21.tlv` + 设备专属
  `qca/polaris/crnv21.bin`）加载后控制器正常启动，`bluetoothctl` 可扫描/配对，
  MAC 由 `bootmac@bluetooth` 固定；蓝牙音频（A2DP 耳机/音箱）由内置的
  `pulseaudio-module-bluetooth` 提供（`/etc/pulse/default.pa` 自动加载
  `module-bluetooth-discover`/`module-bluetooth-policy`）。
  验证：`hciconfig -a`（UP RUNNING）、`bluetoothctl scan on`。
- **音频**：ALSA UCM 层（`/usr/share/alsa/ucm2/Qualcomm/sdm845/Polaris-HiFi.conf`，
  经 `conf.d/sdm845/Xiaomi Mi MIX 2S.conf` 按声卡名自动加载），PulseAudio 开机接管，
  扬声器/麦克风端口规范暴露；`pactl` 可用（`polaris-keys` 的长按调音量依赖它）。
  蓝牙耳机/音箱（A2DP）见上方「蓝牙」。
- **界面语言**：英文 `en_US.UTF-8`（未装中文字体）。
- **稳定性加固**：systemd 硬件看门狗 `RuntimeWatchdogSec=10`；内核 `panic=120`、
  `panic_on_oops=1`、`panic_on_rcu_stall=1`（卡死自动重启）；`fs.protected_regular=0`。
- **内存与交换（zram）**：开机自动启用一块 **4 GiB、zstd 压缩**的 zram 交换设备
  （`/dev/zram0`，priority 100），由开机自启的 `polaris-zram-swap.service`
  （`WantedBy=swap.target`）调用 `/usr/sbin/polaris-zramswap` 创建；`systemctl stop` 时
  `/usr/sbin/polaris-zramstop` 会 `swapoff` 并复位设备，start/stop 可反复执行且始终只保留
  一个 zram 设备（幂等）。配套 `/etc/sysctl.d/91-polaris-zram.conf` 调优：
  `vm.swappiness=180`、`vm.page-cluster=0`（zram 随机读取代价极低，关闭预读）、
  `vm.min_free_kbytes=100000`。
  验证：`zramctl`、`cat /proc/swaps`、`free -h`（Swap 一栏显示 4.0 GiB）。
- **常用工具**：`nano`、`less`、`iw`、`rfkill`、`e2fsprogs`、`usbutils`、`iproute2`、
  `alsa-utils`、`python3` 等；**已预装 `fastfetch`、`iperf3`**，并内置让 `fastfetch`
  显示完整 GPU 名称所需的 `libvulkan1` + `mesa-vulkan-drivers`（turnip / freedreno ICD），
  开机后 `fastfetch` 即可看到 `GPU: Qualcomm Turnip Adreno (TM) 630 [Integrated]`，
  `iperf3` 直接可做网络吞吐测试。固件约 79M、内核模块约 22M。系统用官方 Debian 源，
  需要别的软件直接 `sudo apt update && sudo apt install <包名>` 即可（`apt` 可用，免密 sudo）。

## 分区与文件系统

| 镜像 | 刷入分区 | 内容 | 大小 |
| --- | --- | --- | --- |
| `boot.img` | `boot` | 内核 `7.1.0-rc1-sdm845`（#62，含 fbcon 回滚、USB OTG/Type-C/PD 补丁；WiFi 死锁补丁只改模块）+ 追加 DTB + initramfs | 25,825,280 B |
| `xiaomi-polaris.img` | `userdata` | Debian 根文件系统（ext4, 4096 字节块，**首启自动扩容到整块 userdata**），**Android sparse 格式**；含 r61 内核的 USB/PD 模块（`qcom_pmic_tcpm.ko.zst`、`qcom_usb_vbus-regulator.ko.zst`） | 1,682,727,216 B (≈1.57 GiB，声明覆盖 550502 个 4K 块 ≈ 2.1 GiB) |

> 同一份根文件系统的 raw ext4 版（2.1 GiB）为
> `/home/wxs/debian-polaris/out/xiaomi-polaris-2g.img`；分区全尺寸稀疏版为
> `/home/wxs/debian-polaris/out/xiaomi-polaris.grown.img`。均不随包携带，需要 loop 挂载 /
> e2fsck 检查时用它们。

- 内核 cmdline：`root=UUID=cac37d97-8a41-48ca-b85c-4350669188b4 rootfstype=ext4 rootwait rw loglevel=4 console=tty0 consoleblank=600 fsck.repair=yes`
- **开机自愈**：cmdline 里的 `fsck.repair=yes` 让 initramfs 对根分区执行 `fsck -y`
  （自动修复），而不是默认的 `fsck -a`（只修"安全"问题、其它一律报错退出）。
  万一刷写过程出现任何不一致，开机时会被自动修复并继续启动，**不会**像以前那样
  停在 `(initramfs)` 紧急 shell。若文件系统本来就是干净的，这一步是无操作，不影响正常启动。
- **小镜像 + 首启自动扩容**：镜像里的根文件系统只做到 **2.1 GiB**（550502 个 4K 块，
  约 0.80 GiB 空闲），`/etc/fstab` 里带 `x-systemd.growfs`。这样刷机时 bootloader 需要
  写入的**声明覆盖面积小**（fastboot 用 total_blks 而不是文件大小估算刷写量，覆盖越小刷得越快）；
  设备首次开机时由 systemd 的 `systemd-growfs-root.service` 依据该选项把根文件系统
  **自动扩到整块 `userdata`（53.5 GiB）**。
  > 下限说明：本 fs 用 flex_bg（每 16 个 group 一组），第二个 flex 组的 inode 表被固定在
  > 第 524288 块，`resize2fs` 因此最小只能缩到约 536437 块（2.05 GiB），再小会报
  > `New size smaller than minimum`。
  > 若个别情况下首启未自动扩容，手动执行 `sudo resize2fs /dev/sda21` 即可（瞬时完成）。
- initramfs 由 Debian `initramfs-tools` 生成（`MODULES=list`：ext4/ufs/显示等驱动已编入内核，
  故无需带模块），约 10.7 MB，内含自建的 `polaris-usb-gadget` 所需组件。

## 与 pmOS 控制台版（`pmos-polaris-flash-console`）的差异

| 项目 | pmOS 控制台版 | 本 Debian 控制台版 |
| --- | --- | --- |
| 发行版 | postmarketOS / Alpine | **Debian 13 (trixie)**，apt 软件源 |
| 内核/设备树 | pmOS 自建 | **复用同一份** pmOS `7.1_rc1-r61` 内核与 DTB（另打 USB OTG/PD 等补丁） |
| 显示启动 | 有 plymouth | **无 plymouth**（直接 fb 控制台） |
| 大字体 | fbkeyboard drop-in + 字体复查服务 | **console-setup 原生** Terminus 16x32（+ drop-in 保险） |
| initramfs | pmOS initramfs（自动创建 g1 gadget） | Debian initramfs-tools + **自建 `polaris-usb-gadget.service`** |
| 中文字体 | 无（英文控制台） | 无（英文控制台） |
| 摄像头 | 内核已移除 | 内核已移除 |
| 首启扩容 | pmOS 首启脚本 | **`x-systemd.growfs` 自动扩容**（首启扩到整块 userdata） |

功能对齐（均可用）：fbkeyboard 虚拟键盘、大字体、电源键亮度循环、音量键方向键/音量、
USB 网络 172.16.42.1、**USB 主机 / Type-C PD 边充边用**、ADB 直连、免密 sudo、
**普通用户免密管理网络**、英文 locale、SSH、
Wi‑Fi（nmtui）、**移动数据 4G（插 SIM 即用，Wi‑Fi 优先）**、登录界面来源标注、无 GUI、无摄像头。

## 已知限制

- 无图形界面、无 GPU 桌面（本版本刻意如此，控制台不受影响）。
- 摄像头在内核与设备树层面已移除，不可用。
- 挂起/休眠已禁用（永不休眠）；空闲 10 分钟只按 `consoleblank=600` 熄灭屏幕背光。
- 首次开机需生成 SSH 密钥，比后续开机慢。

## 校验

```bash
cd images
md5sum -c boot.img.md5 xiaomi-polaris.img.md5
```

预期结果：`boot.img` = `9084e022…`、`xiaomi-polaris.img` = `b91b7969…`
（对应 raw 版 `b82b1851…`，可在 `/home/wxs/debian-polaris/out/xiaomi-polaris-2g.img` 下比对）。

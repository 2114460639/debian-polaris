# 小米 MIX 2S（xiaomi-polaris）Debian 13 刷机包 —— 无 GUI 控制台版

面向小米 MIX 2S 的 **Debian GNU/Linux 13 (trixie) aarch64** 成品镜像：开机直接进入
Linux framebuffer 终端，屏幕底部常驻一个全尺寸虚拟键盘（fbkeyboard），触摸即可打字。

本版本定位为**追求稳定的英文控制台系统**：界面语言英文 `en_US.UTF-8`，**无任何图形界面**
（不含 phosh / phoc / greetd / display-manager），**内核层面已无摄像头**，并把全部
设备适配（网络、音频、按键、ADB、固件）固化进镜像，开机即用，无需首启配置。

- 发行版：Debian GNU/Linux 13.7 (trixie)，aarch64，约 381 个包
- 内核：postmarketOS 的 `linux-postmarketos-qcom-sdm845` **7.1_rc1-r53**
  （版本串 `7.1.0-rc1-sdm845`，`#54`），同一份内核与设备树；
  在上游基础上打了 fbdev 背缓冲与 fbcon 回滚两处补丁，见 [kernel/README.md](kernel/README.md)
- 构建方式：**官方 Debian 源 + debootstrap**（非 Mobian），第三方预编译件仅为
  pmOS 内核/固件、静态 adbd、fbkeyboard 与 `polaris-keys`

> 刷机会**清空 userdata 分区**，手机内所有数据（照片、文档等）都会丢失，请先备份。

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
├── kernel/                      内核方法：fbcon 回滚补丁、APKBUILD、内核 config
│   └── README.md                构建步骤与两处改动说明
├── rootfs/                      镜像内定制的配置文件（保持原始路径）
│   ├── etc/systemd/system/      fbkeyboard / polaris-* / qc-* 单元、睡眠 mask
│   ├── etc/systemd/network/     usb0 固定 172.16.42.1
│   ├── etc/NetworkManager/      WiFi MAC 固定、usb0 不交给 NM
│   ├── usr/bin/bootmac          WiFi/蓝牙 MAC 固定脚本
│   └── usr/lib/udev/rules.d/    bootmac 触发规则
├── scripts/
│   ├── mk_sparse_fill.py        raw → Android sparse（RAW+FILL，无空洞）
│   └── repack_boot.py           只换 boot.img 的 kernel 段
├── fbkeyboard/                  虚拟键盘源码（fbkeyboard.c + Makefile）
├── tools/
│   ├── linux/    adb、fastboot、lib64、51-android.rules（udev 规则）
│   └── windows/  adb.exe、fastboot.exe 及所需 DLL
└── drivers/
    └── windows/usb_driver/      Google USB 驱动（Windows 识别 fastboot 设备用）
```

> 原始 raw ext4 镜像（1.5 GiB）不随刷机包携带，统一放在编译产物目录
> `/home/wxs/debian-polaris/out/xiaomi-polaris.img`，需要检查文件系统时用那份。

## 镜像从哪来

仓库里**不放镜像文件**（GitHub 单文件上限 100 MB），成品镜像统一发在
[Releases](https://github.com/2114460639/debian-polaris/releases)：

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `boot.img` | 25 MiB | 内核 + DTB + initramfs，刷到 `boot` 分区 |
| `xiaomi-polaris.img` | 1.2 GiB | 系统镜像（**Android sparse 格式**），刷到 `userdata` |
| `*.md5` | — | 校验值，下载后先 `md5sum -c` |

把它们放进本仓库的 `images/` 目录，`flash.sh` / `flash.bat` 就能直接用。

`tools/`（adb、fastboot）和 `drivers/`（Windows USB 驱动）是第三方二进制，
**同样不入库**，需要自行准备：

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
      最多等 20 秒等它进入 fastboot；
   3. adb 也没有、或 20 秒后仍未进 fastboot，才提示你手动进入
      （音量下 + 电源）。
3. 输入 `yes` 确认后脚本会刷入 boot 与系统镜像并重启。**首次开机较慢**
   （约 1~2 分钟）：需要扩展根分区并生成 SSH 主机密钥，请耐心等待。

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
fastboot flash userdata images/xiaomi-polaris.img
fastboot reboot
```

> **`images/xiaomi-polaris.img` 名字叫 `.img`，内容其实是 Android sparse 镜像**
> （按官方 postmarketOS 刷机包格式预先做好：只有 RAW/FILL chunk、没有 don't-care）。
> fastboot 会原样发给 bootloader 原生解析，可正常启动。
>
> 千万别换成 raw ext4 镜像让 fastboot 现场转换：本机 fastboot 会把全零块当成
> don't-care 空洞交给 bootloader，实际写进 userdata 的内容会与镜像不一致，开机 fsck
> 报 `Superblock has an invalid journal (inode 8)` /
> `Block bitmap for group 0 is not in the group` 并停在 initramfs 紧急 shell。
> 需要 raw 镜像（loop 挂载、e2fsck 检查）时去编译产物目录
> `/home/wxs/debian-polaris/out/` 取。
>
> `boot.img` 的 cmdline 带 `fsck.repair=yes`：轻微不一致会自动 `fsck -y` 修复后继续
> 启动；但若文件系统结构性损坏（如 group descriptor 坏），fsck 修不动时（退出码 12）
> 仍会停在 `(initramfs)` 紧急 shell —— 这种情况重新跑一次刷机脚本即可恢复。

## 系统功能介绍

- **开机即终端**：启动后屏幕就是 Linux framebuffer 控制台，最后停在 `polaris login:` 提示符（tty1）。
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
    内核版本 `7.1.0-rc1-sdm845 #54-postmarketos-qcom-sdm845`（pkgrel 53）。
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
  - **Wi‑Fi**：NetworkManager 已启用，自带 `nmtui`（终端里执行 `sudo nmtui` 连接 Wi‑Fi）、
    `nmcli`、`iw`、`rfkill` 等；`wpa_supplicant`、`bluetooth` 也已启用。
    WCN3990 固件按**内核实际查找的标准路径**放置：`ath10k/WCN3990/hw1.0/{board-2.bin,
    firmware-5.bin,wlanmdsp.mbn}`、`qca/crbtfw21.tlv`、`qca/crnv21.bin`、`regulatory.db(.p7s)`、
    `qcom/a630_{gmu.bin,sqe.fw}`。此前这些只以 `postmarketos/` 前缀存在（内核不搜索该前缀），
    导致 `ath10k_snoc` 不绑定、无 `wlan0`、dmesg 报 `error -2`。
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
- **音频**：ALSA UCM 层（`/usr/share/alsa/ucm2/Qualcomm/sdm845/Polaris-HiFi.conf`，
  经 `conf.d/sdm845/Xiaomi Mi MIX 2S.conf` 按声卡名自动加载），PulseAudio 开机接管，
  扬声器/麦克风端口规范暴露；`pactl` 可用（`polaris-keys` 的长按调音量依赖它）。
- **界面语言**：英文 `en_US.UTF-8`（未装中文字体）。
- **稳定性加固**：systemd 硬件看门狗 `RuntimeWatchdogSec=10`；内核 `panic=120`、
  `panic_on_oops=1`、`panic_on_rcu_stall=1`（卡死自动重启）；`fs.protected_regular=0`。
- **常用工具**：`nano`、`less`、`iw`、`rfkill`、`e2fsprogs`、`usbutils`、`iproute2`、
  `alsa-utils`、`python3` 等；固件约 79M、内核模块约 22M。系统用官方 Debian 源，
  需要别的软件直接 `sudo apt update && sudo apt install <包名>` 即可（`apt` 可用，免密 sudo）。

## 分区与文件系统

| 镜像 | 刷入分区 | 内容 | 大小 |
| --- | --- | --- | --- |
| `boot.img` | `boot` | 内核 `7.1.0-rc1-sdm845`（#54，含 fbcon 回滚补丁）+ 追加 DTB + initramfs | 25,825,280 B |
| `xiaomi-polaris.img` | `userdata` | Debian 根文件系统（ext4, 4096 字节块），**Android sparse 格式** | 1,232,204,752 B (≈1.2 GiB) |

> 同一份根文件系统的 raw ext4 版为 1,610,612,736 B (≈1.5 GiB)，不随包携带，
> 见 `/home/wxs/debian-polaris/out/xiaomi-polaris.img`。

- 内核 cmdline：`root=UUID=cac37d97-8a41-48ca-b85c-4350669188b4 rootfstype=ext4 rootwait rw loglevel=4 console=tty0 consoleblank=600 fsck.repair=yes`
- **开机自愈**：cmdline 里的 `fsck.repair=yes` 让 initramfs 对根分区执行 `fsck -y`
  （自动修复），而不是默认的 `fsck -a`（只修"安全"问题、其它一律报错退出）。
  万一刷写过程出现任何不一致，开机时会被自动修复并继续启动，**不会**像以前那样
  停在 `(initramfs)` 紧急 shell。若文件系统本来就是干净的，这一步是无操作，不影响正常启动。
- **首启自动扩容**：`/etc/fstab` 中根分区挂载带 `x-systemd.growfs`，开机后根文件系统会
  自动扩展到整个 `userdata` 分区（本机约 55 GB），之后 `df -h /` 即显示完整容量。
- initramfs 由 Debian `initramfs-tools` 生成（`MODULES=list`：ext4/ufs/显示等驱动已编入内核，
  故无需带模块），约 10.7 MB，内含自建的 `polaris-usb-gadget` 所需组件。

## 与 pmOS 控制台版（`pmos-polaris-flash-console`）的差异

| 项目 | pmOS 控制台版 | 本 Debian 控制台版 |
| --- | --- | --- |
| 发行版 | postmarketOS / Alpine | **Debian 13 (trixie)**，apt 软件源 |
| 内核/设备树 | pmOS 自建 | **复用同一份** pmOS `7.1_rc1-r52` 内核与 DTB |
| 显示启动 | 有 plymouth | **无 plymouth**（直接 fb 控制台） |
| 大字体 | fbkeyboard drop-in + 字体复查服务 | **console-setup 原生** Terminus 16x32（+ drop-in 保险） |
| initramfs | pmOS initramfs（自动创建 g1 gadget） | Debian initramfs-tools + **自建 `polaris-usb-gadget.service`** |
| 中文字体 | 无（英文控制台） | 无（英文控制台） |
| 摄像头 | 内核已移除 | 内核已移除 |
| 首启扩容 | pmOS 首启脚本 | `/etc/fstab` 的 `x-systemd.growfs` |

功能对齐（均可用）：fbkeyboard 虚拟键盘、大字体、电源键亮度循环、音量键方向键/音量、
USB 网络 172.16.42.1、ADB 直连、免密 sudo、英文 locale、SSH、Wi‑Fi（nmtui）、无 GUI、无摄像头。

## 已知限制

- 无图形界面、无 GPU 桌面（本版本刻意如此，控制台不受影响）。
- 摄像头在内核与设备树层面已移除，不可用。
- 挂起/休眠已禁用（永不休眠）；空闲 10 分钟只按 `consoleblank=600` 熄灭屏幕背光。
- 首次开机需生成 SSH 密钥并扩容，比后续开机慢。

## 校验

```bash
cd images
md5sum -c boot.img.md5 xiaomi-polaris.img.md5
```

预期结果：`boot.img` = `6511830e…`、`xiaomi-polaris.img` = `fed395f2…`
（对应 raw 版 `e2690aee…`，可在 `/home/wxs/debian-polaris/out/` 下比对）。

# 内核：构建方法与三处改动

内核来自 postmarketOS 的 pmaports 包
`device/community/linux-postmarketos-qcom-sdm845`（上游源码
`gitlab.com/sdm845-mainline/linux`，tag `sdm845-7.1-rc1-r0`，Linux 7.1-rc1）。

本项目在这个包上只做了 **三处改动**，其余全部沿用上游。

## 改动 1：fbdev 背缓冲 100% → 300%

`config-postmarketos-qcom-sdm845.aarch64`：

```diff
-CONFIG_DRM_FBDEV_OVERALLOC=100
+CONFIG_DRM_FBDEV_OVERALLOC=300
```

默认 100% 时 `yres_virtual == yres`，`fb0` 没有任何 panning 余量
（`/sys/class/graphics/fb0/virtual_size` 会是 `1080,2160`）。
改成 300% 后变成 `1080,6480`，为屏幕外留出 2 屏空间。

> 注意：这一项**单独改并不能让滚动键生效**，它是改动 2 的前提条件之一。

## 改动 2：`fbcon-scrollback.patch`（让 Shift+PageUp/Down 真正生效）

`fbcon-scrollback.patch` —— 自研补丁，251 行，只改 `drivers/video/fbdev/core/fbcon.c`。

**为什么需要它**：主线 fbcon 没有实现 `con_scrolldelta`，`struct consw fb_con`
缺这一项，于是 VT 层 [vt.c] 里这段直接跳过：

```c
if (vc->vc_mode == KD_TEXT && vc->vc_sw->con_scrolldelta)
        vc->vc_sw->con_scrolldelta(vc, scrollback_delta);
```

结果就是 `Shift+PageUp`（`K_SCROLLBACK` → `fn_scroll_back` → `scrolldelta()`）
按下去毫无反应 —— 键位映射是好的，是控制台驱动不接。

[vt.c]: https://github.com/torvalds/linux/blob/master/drivers/tty/vt/vt.c

**补丁做了什么**：

1. 一条 4096 行的环形历史缓冲（`fbcon_sb_*`）；
2. `fbcon_scroll()` 在整屏上滚（`SM_UP && t==0 && b==vc_rows`）时，先把即将被顶出的
   行从 `vc_origin` 抓进缓冲，再执行原有的滚屏逻辑；
3. 实现 `fbcon_scrolldelta()` 并注册到 `fb_con.con_scrolldelta`：
   负值 = 往回翻（`back += -lines`），`0` = 回到实时画面；
4. 回滚渲染 = 整屏重绘「历史行 + 实时内容」，按属性（`c & 0xff00`）分段调
   `fbcon_putcs()`，与 `fbcon_redraw()` 同款写法 —— 因为 `bit_putcs()` 只用第一个
   字符的前景/背景色，不分段会整行变色；
5. 兜底行为：
   - 新的控制台输出（`fbcon_putcs/clear/scroll/bmove`）会自动落回实时画面；
   - `fbcon_switch()`（切 VT）归零；
   - `fb_flashcursor()` 与 `fbcon_cursor()` 在回滚视图下不画光标；
   - 缓冲只在 `fbcon_init()` / `fbcon_resize()` 这类**可睡眠上下文**里分配，
     滚动路径零分配（避免在 printk 的原子上下文里 `kmalloc(GFP_KERNEL)`）。

## 改动 3：`polaris-sta-destroy-nowarn.patch`（修关机死锁 / 文件系统损坏）

`polaris-sta-destroy-nowarn.patch` —— 只改 `net/mac80211/sta_info.c`，删掉
`__sta_info_destroy_part2()` 里的 3 处 `WARN_ON_ONCE`。

**问题**：关机时 NetworkManager/wpa_supplicant 停止会触发 WiFi 主动 deauth
(`DEAUTH_LEAVING`)，此时 ath10k 固件已开始下电，`drv_sta_state()` 会返回错误
（`failed to remove key ... -108/-110`）。`__sta_info_destroy_part2()` 在这个返回值上
打了 `WARN_ON_ONCE`（`sta_info.c:1580`），而 WARN 走 `report_bug() → printk() → 控制台写入`；
关机中段控制台最繁忙，多颗 CPU 在 console/printk 锁上自旋死锁 → `rcu_preempt detected stalls`
→ panic → **强制断电，rootfs 每次多几条 EXT4 错误**（累积到一定程度会掉进 initramfs 紧急 shell）。

**为什么删 WARN 而不是修驱动**：这是"设备正在关机、固件已下电"场景下的预期错误返回，
上游在热插拔路径上也容许它失败；真正致命的是 WARN 的打印路径与关机控制台竞争。
删掉这 3 处 WARN 后，`__sta_info_destroy_part2+0x158` 的 `brk #0x800`（反汇编确认）
不再存在，deauth 无论返回 `-108` 还是 `-110` 都只安静地往下走。

**验证**：连续 5 轮关机（静音控制台 / 正常控制台 / 生产形态 systemd 服务管理三种形态）
全部干净走完 `systemd-shutdown`，`sta_info.c` WARN 计数恒为 0，无 stall、无 panic。

> 该补丁只重编了 `mac80211.ko`（增量编译），**内核 Image 与 DTB 未变**，因此
> `boot.img` 无需更新，只需替换 rootfs 里的 `mac80211.ko.zst`。

## 构建

```bash
# 1. 把 patch 放进包目录，并登记到 APKBUILD（source 列表 + sha512sums）
cp fbcon-scrollback.patch polaris-sta-destroy-nowarn.patch \
   ~/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-qcom-sdm845/
#    APKBUILD: pkgrel 52 -> 53 追加 fbcon-scrollback.patch；53 -> 54 追加 polaris-sta-destroy-nowarn.patch

# 2. 重新算校验值并编译（有 ccache，增量只要 1 分钟左右）
pmbootstrap checksum linux-postmarketos-qcom-sdm845
pmbootstrap build linux-postmarketos-qcom-sdm845 --force
```

产物：

```
~/.local/var/pmbootstrap/packages/v26.06/aarch64/linux-postmarketos-qcom-sdm845-7.1_rc1-r54.apk
└── boot/vmlinuz        ← 内核（zImage）
└── boot/dtbs/qcom/sdm845-xiaomi-polaris.dtb
└── usr/lib/modules/7.1.0-rc1-sdm845/kernel/net/mac80211/mac80211.ko.zst  ← 改动 3 的产物
```

验证有没有编进去：

```bash
uname -a    # 应显示 #54-postmarketos-qcom-sdm845（KBUILD_BUILD_VERSION = pkgrel+1）
```

## 打包 boot.img

boot.img 是 Android 格式（`ANDROID!` magic + header v0），只换 kernel 段，
ramdisk 与 cmdline 原样保留：

```bash
# zImage = vmlinuz + 追加 DTB
cat vmlinuz sdm845-xiaomi-polaris.dtb > /tmp/zimage-new

python3 scripts/repack_boot.py <旧boot.img> /tmp/zimage-new <新boot.img>

fastboot flash boot <新boot.img>
```

## 滚动功能验证

注入按键后对比 `/dev/fb0` 的 md5：

```bash
# 往回翻两屏：两次 md5 都应变化
# 往下翻两屏：第一次应回到「第一次上翻」的 md5，第二次应回到实时 baseline
```

屏幕上也可以直接点虚拟键盘上方那条隐藏导航格的右上/右下两格，应能来回翻看历史日志。

# 内核：构建方法与两处改动

内核来自 postmarketOS 的 pmaports 包
`device/community/linux-postmarketos-qcom-sdm845`（上游源码
`gitlab.com/sdm845-mainline/linux`，tag `sdm845-7.1-rc1-r0`，Linux 7.1-rc1）。

本项目在这个包上只做了 **两处改动**，其余全部沿用上游。

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

## 构建

```bash
# 1. 把 patch 放进包目录，并登记到 APKBUILD（source 列表 + sha512sums）
cp fbcon-scrollback.patch ~/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-qcom-sdm845/
#    APKBUILD: pkgrel 52 -> 53, source= 里追加 fbcon-scrollback.patch

# 2. 重新算校验值并编译（有 ccache，增量只要 1 分钟左右）
pmbootstrap checksum linux-postmarketos-qcom-sdm845
pmbootstrap build linux-postmarketos-qcom-sdm845 --force
```

产物：

```
~/.local/var/pmbootstrap/packages/v26.06/aarch64/linux-postmarketos-qcom-sdm845-7.1_rc1-r53.apk
└── boot/vmlinuz        ← 内核（zImage）
└── boot/dtbs/qcom/sdm845-xiaomi-polaris.dtb
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

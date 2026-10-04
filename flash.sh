#!/usr/bin/env bash
# ============================================================
#  小米 MIX 2S (xiaomi-polaris) Debian 13 控制台版 刷机脚本 —— Linux
#  用法：把手机进入 fastboot 模式后，执行  ./flash.sh
#  注意：会清空手机 userdata 分区（所有数据/照片都会丢）
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 优先用随包附带的 fastboot/adb，找不到再退回系统安装的
FASTBOOT="$HERE/tools/linux/fastboot"
ADB="$HERE/tools/linux/adb"
export LD_LIBRARY_PATH="$HERE/tools/linux/lib64:${LD_LIBRARY_PATH:-}"
[ -x "$FASTBOOT" ] || FASTBOOT="$(command -v fastboot || true)"
[ -x "$ADB" ]      || ADB="$(command -v adb || true)"

BOOT_IMG="$HERE/images/boot.img"
# 注意：文件名叫 .img，但内容是**预先生成好的 Android sparse 镜像**
ROOTFS_IMG="$HERE/images/xiaomi-polaris.img"

info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. 检查镜像文件 ----------
[ -f "$BOOT_IMG" ]   || die "缺少 $BOOT_IMG"
[ -f "$ROOTFS_IMG" ] || die "缺少系统镜像 $ROOTFS_IMG"
[ -n "${FASTBOOT:-}" ] && [ -x "$FASTBOOT" ] || die "找不到 fastboot，可安装： sudo apt install android-tools-fastboot android-tools-adb"
[ -n "${ADB:-}" ] && [ -x "$ADB" ] || warn "找不到 adb，只能靠 fastboot 或手动进入 fastboot 模式"

# ---------- 2. 找设备：先 fastboot，没有就用 adb 重启进去，再没有就提示手动 ----------
# wait_fastboot <次数>：每秒探测一次 fastboot，成功返回 0
wait_fastboot() {
    local i
    for i in $(seq 1 "$1"); do
        if [ -n "$("$FASTBOOT" devices 2>/dev/null | awk 'NF{print $1; exit}')" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

manual_hint() {
    warn "没有可用的 fastboot 设备。请手动进入 fastboot 模式："
    echo "    - 关机后按住【音量下 + 电源】不放，出现 fastboot 字样/图标后松开；或"
    echo "    - 若手机当前正跑本系统，可 SSH 登录后执行："
    echo "        sudo systemctl reboot --reboot-argument=bootloader"
    echo "    - 若手机当前是 Android，可执行： adb reboot bootloader"
}

info "检测 fastboot 设备 ..."
if ! wait_fastboot 1; then
    info "没有 fastboot 设备，改用 adb 重启到 fastboot ..."

    ADBDEV=""
    if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
        # 本系统的 adbd（tonyho/adbd-linux）在 adb 里上报的状态是 "host" 而不是
        # "device"（adb shell/push 一切正常，只是状态名不同），所以两种都认。
        ADBDEV="$("$ADB" devices 2>/dev/null | awk 'NR>1 && ($2 == "device" || $2 == "host") {print $1; exit}')"
    fi

    if [ -z "$ADBDEV" ]; then
        warn "adb 下也没有在线设备。"
        manual_hint
        exit 1
    fi

    info "检测到 adb 设备：$ADBDEV，正在重启到 bootloader ..."
    "$ADB" reboot bootloader >/dev/null 2>&1 || true

    # 本机 bootloader 从 adb 重启到 fastboot 后，枚举 fastboot 往往要 30~40 秒，所以
    # 这里给足 60 秒的轮询窗口（每秒一次），避免误判“进不去 fastboot”。
    if ! wait_fastboot 60; then
        warn "重启后 60 秒内仍未进入 fastboot。"
        manual_hint
        exit 1
    fi
fi

DEV="$("$FASTBOOT" devices 2>/dev/null | awk 'NF{print $1; exit}')"
[ -n "$DEV" ] || { manual_hint; exit 1; }
info "已连接设备：$DEV"

# ---------- 3. 二次确认 ----------
echo
warn "接下来会刷入 boot + 系统镜像，并【清空 userdata】，手机内所有数据将丢失。"
read -r -p "确认继续？输入 yes 回车： " ans
[ "$ans" = "yes" ] || die "已取消。"

# ---------- 4. 刷入 boot（内核 + 设备树 + initramfs） ----------
info "刷入 boot.img -> boot 分区"
"$FASTBOOT" flash boot "$BOOT_IMG"

# ---------- 5. 清空 userdata，再刷入 rootfs（系统）----------
# 【必须先 erase】本机 bootloader 从不写入全零数据：FILL chunk 整个跳过，连 RAW chunk
# 里的全零块也一样跳过。若直接覆盖刷写，旧 Android 数据就会残留在「镜像要求为 0」的
# 位图区，每次开机 e2fsck 都报
#   ext2fs_check_desc: Corrupt group descriptor: bad block for block bitmap
# 并强制约 3.5 分钟的全盘检查。erase 走 discard，只要约 6 秒。
info "清空 userdata 分区（fastboot erase，约 6 秒）"
"$FASTBOOT" erase userdata

# images/xiaomi-polaris.img 名字叫 .img，内容其实是**预先生成好的 Android sparse
# 镜像**（只有 RAW+FILL chunk，没有 don't-care 空洞），直接 fastboot 原样发给
# bootloader 解析即可。
# 千万别拿它当 raw 镜像去 loop 挂载/e2fsck，也别用 raw 大镜像让 fastboot 现场转换：
# 现场转换会把全零块写成 don't-care 空洞，写进 userdata 的内容与镜像不一致。
info "刷入 xiaomi-polaris.img (sparse) -> userdata 分区（镜像约 1.2G，请耐心等待）"
"$FASTBOOT" flash userdata "$ROOTFS_IMG"

# ---------- 6. 引导系统 ----------
info "刷机完成，开始引导系统 ..."
# 优先用 `fastboot reboot`。本机 bootloader 偶发「接受了 reboot 命令、复位后却回落进 fastboot」
# 的情况，宿主侧 fastboot 进程也可能一直卡住不返回，所以这里用 timeout 兜底（60 秒）：
# reboot 卡死或失败时，再退回 `fastboot continue`（让 ABL 直接引导刚刷入的镜像）。
# 注意：设备会把刚刷入的数据落盘到 UFS，这一步可能持续几分钟（刷机传输阶段被背压时更明显），
# 期间屏幕可能先黑后亮，属正常现象，请耐心等待。
info "等待系统启动（最多 6 分钟；引导阶段设备要把数据落盘，可能较慢，请耐心等待）..."

if ! timeout 60 "$FASTBOOT" reboot; then
    warn "fastboot reboot 超时或失败，退回 fastboot continue ..."
    timeout 60 "$FASTBOOT" continue || true
fi

# 等系统起来（adbd 上线），确认刷机成功
if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
        for _ in $(seq 1 360); do
        if [ -n "$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2 != "offline" {print $1; exit}')" ]; then
            info "系统已启动，设备名：$("$ADB" devices 2>/dev/null | awk 'NR>1{print $1; exit}')"
            break
        fi
        sleep 1
    done
fi

echo
warn "若手机仍停在 fastboot，长按电源键 12~15 秒物理复位即可（数据已经刷好，不会丢）。"
info "完成。首次开机会自动把根分区扩容到整块 userdata（并生成 SSH 密钥），请等待 1~2 分钟。"
echo "    SSH 登录： ssh user@172.16.42.1   默认密码：password"

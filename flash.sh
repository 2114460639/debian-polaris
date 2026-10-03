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
        ADBDEV="$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2 == "device" {print $1; exit}')"
    fi

    if [ -z "$ADBDEV" ]; then
        warn "adb 下也没有在线设备。"
        manual_hint
        exit 1
    fi

    info "检测到 adb 设备：$ADBDEV，正在重启到 bootloader ..."
    "$ADB" reboot bootloader >/dev/null 2>&1 || true

    if ! wait_fastboot 20; then
        warn "重启后 20 秒内仍未进入 fastboot。"
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

# ---------- 5. 刷入 rootfs（系统）----------
# images/xiaomi-polaris.img 名字叫 .img，内容其实是**预先生成好的 Android sparse
# 镜像**（只有 RAW+FILL chunk，没有 don't-care 空洞），直接 fastboot 原样发给
# bootloader 解析即可。
# 千万别拿它当 raw 镜像去 loop 挂载/e2fsck，也别用 raw 大镜像让 fastboot 现场
# 转换：本机 fastboot 会把全零块写成 don't-care 空洞，导致 userdata 上的根文件系统
# 与镜像不一致，开机 fsck 报
#   "Superblock has an invalid journal (inode 8)" /
#   "Block bitmap for group 0 is not in the group"
# 然后停在 initramfs 紧急 shell。
info "刷入 xiaomi-polaris.img (sparse) -> userdata 分区（约 1.2G，请耐心等待）"
"$FASTBOOT" flash userdata "$ROOTFS_IMG"

# ---------- 6. 重启 ----------
info "刷机完成，重启手机 ..."
"$FASTBOOT" reboot

echo
info "完成。首次开机较慢，请等待 1~2 分钟。"
echo "    SSH 登录： ssh user@172.16.42.1   默认密码：password"

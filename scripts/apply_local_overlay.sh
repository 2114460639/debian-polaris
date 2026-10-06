#!/bin/sh
# 把「本机私有」overlay 注入到已构建好的 raw ext4 镜像。
#
# 为什么需要它：WiFi 密码这类内容不能提交到公开仓库（本仓库是 Public），
# 所以放在 .gitignore 掉的 local/rootfs/ 下，只在本地构建时打进镜像。
# 目录结构与仓库的 rootfs/ 一致，只是不进 git：
#
#   local/rootfs/etc/NetworkManager/system-connections/xxx.nmconnection
#
# 用法：
#   scripts/apply_local_overlay.sh /home/wxs/debian-polaris/out/xiaomi-polaris-2g.img
# 然后再用 scripts/mk_sparse_fill.py 生成 sparse 镜像。
set -e

IMG=$1
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
	echo "用法: $0 <raw-ext4.img>" >&2
	exit 1
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC=$ROOT/local/rootfs
if [ ! -d "$SRC" ]; then
	echo "apply-local-overlay: 没有 $SRC，跳过（本机私有文件不存在）"
	exit 0
fi

# e2fsprogs 通常在 /sbin，非登录 shell 的 PATH 里可能没有
DEBUGFS=$(command -v debugfs 2>/dev/null || echo /sbin/debugfs)
if [ ! -x "$DEBUGFS" ]; then
	echo "找不到 debugfs（e2fsprogs），请先安装" >&2
	exit 1
fi

n=0
find "$SRC" -type f | while read -r f; do
	rel=${f#"$SRC"}
	d=$(dirname "$rel")
	# 目标目录逐级创建：必须先 stat 判断存在性，只对缺失的目录调 mkdir。
	# debugfs 的 mkdir 对「已存在」的目录会先分配 inode、再报错且不回滚，
	# 会在父目录里留下一个名字损坏的空壳目录，其数据块还可能与其他文件
	# 撞在同一块上 —— e2fsck 会报 "directory corrupted" 与
	# "multiply-claimed block(s)"，镜像直接不可用。
	cur=""
	old_ifs=$IFS
	IFS=/
	for part in ${d#/}; do
		cur="$cur/$part"
		if ! "$DEBUGFS" -R "stat $cur" "$IMG" 2>/dev/null | grep -q '^Inode:'; then
			"$DEBUGFS" -w -R "mkdir $cur" "$IMG" >/dev/null 2>&1
		fi
	done
	IFS=$old_ifs
	# 覆盖：先删再写（debugfs 的 write 遇到已存在文件会失败）
	"$DEBUGFS" -w -R "rm $rel" "$IMG" >/dev/null 2>&1 || true
	"$DEBUGFS" -w -R "write $f $rel" "$IMG" >/dev/null 2>&1
	# 还原权限与属主（NetworkManager 要求 *.nmconnection 为 root:root 0600，
	# 否则会拒绝加载该连接）
	mode=$(stat -c %a "$f")
	"$DEBUGFS" -w -R "sif $rel mode 0100$mode" "$IMG" >/dev/null 2>&1
	"$DEBUGFS" -w -R "sif $rel uid 0" "$IMG" >/dev/null 2>&1
	"$DEBUGFS" -w -R "sif $rel gid 0" "$IMG" >/dev/null 2>&1
	echo "injected $rel (mode $mode, root:root)"
	n=$((n + 1))
done

echo "apply-local-overlay: 完成（$IMG）"

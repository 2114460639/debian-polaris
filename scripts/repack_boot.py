#!/usr/bin/env python3
"""重打包 Android boot.img：只替换 kernel 段（vmlinuz + append dtb），
ramdisk 段与 cmdline 从现有 boot.img 原样保留。

用法:
  repack_boot.py OLD ZIMAGE OUT            # 换 kernel，ramdisk 原样
  repack_boot.py OLD - OUT                 # kernel/ramdisk 都原样（仅重建）
  repack_boot.py OLD - OUT NEW_INITRD.img  # 换 ramdisk（kernel 原样），
                                           # 如往 initramfs 追加 GPU 固件
ZIMAGE 为 "-" 表示沿用 OLD 中的 kernel 段。"""
import struct
import sys

OLD, ZIMAGE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
RAMDISK = sys.argv[4] if len(sys.argv) > 4 else None

d = open(OLD, "rb").read()
assert d[:8] == b"ANDROID!", "not an android boot image"
# header v0: kernel_size kernel_addr ramdisk_size ramdisk_addr second_size
#           second_addr tags_addr page_size header_version os_version
(ks, ka, rs, ra, ss, sa, ta, ps, hv, ov) = struct.unpack_from("<10I", d, 8)
name = d[48:64]
cmdline = d[64:576]
ident = d[576:608]
extra = d[608:1632]
print("old: k=%d r=%d page=%d hv=%d" % (ks, rs, ps, hv))
print("cmdline:", cmdline.split(b"\0")[0].decode())

# 提取 ramdisk 段
koff = ps
roff = koff + ((ks + ps - 1) // ps) * ps
if RAMDISK:
    ramdisk = open(RAMDISK, "rb").read()
    print("new ramdisk: %d (was %d)" % (len(ramdisk), rs))
else:
    ramdisk = d[roff:roff + rs]
    assert len(ramdisk) == rs

if ZIMAGE == "-":
    kernel = d[koff:koff + ks]
    print("keep kernel: %d" % len(kernel))
else:
    kernel = open(ZIMAGE, "rb").read()
    print("new kernel: %d (was %d)" % (len(kernel), ks))


def pad(b):
    return b + b"\0" * ((ps - len(b) % ps) % ps)


hdr = b"ANDROID!" + struct.pack(
    "<10I", len(kernel), ka, len(ramdisk), ra, ss, sa, ta, ps, hv, ov
) + name + cmdline + ident + extra
assert len(hdr) <= ps, len(hdr)

img = pad(hdr) + pad(kernel) + pad(ramdisk)
open(OUT, "wb").write(img)
print("wrote %s (%d bytes)" % (OUT, len(img)))

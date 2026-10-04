#!/usr/bin/env python3
"""
把 raw ext4 镜像转成 Android sparse 镜像：只用 RAW + FILL 两种 chunk，
绝不产生 CHUNK_TYPE_DONT_CARE 空洞。

为什么不交给 fastboot 现场转换：
  `fastboot flash` 遇到“非稀疏”的大镜像时会自己转成 sparse，并把全零块写成
  DONT_CARE；很多 bootloader 对 DONT_CARE 的处理就是「跳过不写」，分区里原来的
  旧数据就会残留在这些空洞里。

关键前提（本机 xiaomi-polaris 实测）：
  这台 bootloader 完全**不写入全零数据** —— FILL chunk 整个跳过，连 RAW chunk 里的
  全零块也一样跳过（用 cmp 比对刷写前后的设备数据验证过，与 chunk 大小、类型无关）。
  所以**刷写 userdata 之前必须先 `fastboot erase userdata`**：分区先被清成零后，
  被 bootloader 跳过的那些零区本来就是零，文件系统才与镜像一致。
  否则旧 Android 数据会留在「镜像要求为 0」的位图区，每次开机 e2fsck 都报
      ext2fs_check_desc: Corrupt group descriptor: bad block for block bitmap
  并强制约 3.5 分钟的全盘检查。

用法：
  python3 mk_sparse_fill.py <raw.img> <out.sparse.img> [--verify]
"""
import hashlib
import os
import struct
import sys

BS = 4096              # sparse 块大小，与 pmOS 镜像一致
HDR_SZ = 28
CHK_SZ = 12
RAW_CAP = 256          # 单个 RAW chunk 最多 256 块 = 1 MiB（与 pmOS 镜像的量级一致，
                       # 避免个别 bootloader 对超大 chunk 的缓冲区处理出问题）
ZERO = b"\0" * BS
TYPE_RAW = 0xCAC1
TYPE_FILL = 0xCAC2


def convert(src, dst):
    size = os.path.getsize(src)
    if size % BS:
        raise SystemExit("源镜像大小不是 %d 的整数倍：%d" % (BS, size))
    total_blocks = size // BS
    chunks = 0
    raw_bytes = 0

    with open(src, "rb") as f, open(dst, "wb") as o:
        o.write(b"\0" * HDR_SZ)          # header 占位，最后回填

        cur = None                       # 'raw' / 'fill'
        run_len = 0
        run_data = bytearray()

        def flush():
            nonlocal chunks, raw_bytes
            if cur is None or run_len == 0:
                return
            if cur == "fill":
                # total_sz 含 12 字节 chunk 头 + 4 字节填充值
                o.write(struct.pack("<HHII", TYPE_FILL, 0, run_len, CHK_SZ + 4))
                o.write(struct.pack("<I", 0))
                chunks += 1
            else:
                data = bytes(run_data)
                nb = len(data) // BS
                b = 0
                while b < nb:
                    k = min(RAW_CAP, nb - b)
                    o.write(struct.pack("<HHII", TYPE_RAW, 0, k, CHK_SZ + k * BS))
                    o.write(data[b * BS:(b + k) * BS])
                    chunks += 1
                    raw_bytes += k * BS
                    b += k

        while True:
            blk = f.read(BS)
            if not blk:
                break
            t = "fill" if blk == ZERO else "raw"
            if t != cur or (t == "raw" and run_len >= RAW_CAP):
                flush()
                cur, run_len = t, 0
                run_data = bytearray()
            run_len += 1
            if t == "raw":
                run_data += blk
        flush()

        o.seek(0)
        o.write(struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, HDR_SZ, CHK_SZ,
                            BS, total_blocks, chunks, 0))
    return size, total_blocks, chunks, raw_bytes


def md5(path, limit=None):
    h = hashlib.md5()
    n = 0
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b or (limit is not None and n >= limit):
                break
            h.update(b)
            n += len(b)
    return h.hexdigest()


def desparse(path, out_limit=None):
    """把 sparse 还原成 raw 字节流；返回 md5（用于和源镜像比对）。"""
    h = hashlib.md5()
    total = 0
    with open(path, "rb") as f:
        hdr = f.read(HDR_SZ)
        magic, major, minor, fhs, chs, bsz, tblks, tchunks, cks = struct.unpack("<IHHHHIIII", hdr)
        if magic != 0xED26FF3A:
            raise SystemExit("不是 sparse 镜像")
        for _ in range(tchunks):
            ct, res, cn, tb = struct.unpack("<HHII", f.read(chs))
            if ct == TYPE_RAW:
                data = f.read(tb - chs)
                if len(data) != tb - chs:
                    raise SystemExit("RAW chunk 数据不完整")
                h.update(data)
                total += len(data)
            elif ct == TYPE_FILL:
                v = f.read(4)
                n = cn * bsz
                h.update(v * (n // 4))
                total += n
            elif ct == 0xCAC3:
                raise SystemExit("出现了 DONT_CARE chunk（本脚本不应产生）")
            else:
                f.read(tb - chs)
    return h.hexdigest(), total, tblks * bsz


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    size, tb, chunks, raw_bytes = convert(src, dst)
    print("源镜像      : %s (%d 字节 = %.0f MiB, %d 块)" % (src, size, size / 1048576, tb))
    print("sparse 输出 : %s (%d 字节 = %.0f MiB)" % (dst, os.path.getsize(dst), os.path.getsize(dst) / 1048576))
    print("chunk 数    : %d  (RAW 部分 %.0f MiB)" % (chunks, raw_bytes / 1048576))
    if "--verify" in sys.argv:
        m_src = md5(src)
        m_dec, dec_len, expect = desparse(dst)
        print("还原校验    : raw md5=%s" % m_src)
        print("            : 还原 md5=%s (%d 字节, 头部声明 %d 字节)" % (m_dec, dec_len, expect))
        print("             %s" % ("一致 ✓" if (m_src == m_dec and dec_len == size == expect) else "不一致 ✗"))
        if m_src != m_dec or dec_len != size or dec_len != expect:
            raise SystemExit(1)


if __name__ == "__main__":
    main()

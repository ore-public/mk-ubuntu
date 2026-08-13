#!/usr/bin/env python3
"""xremap が出力する仮想入力デバイスからキーイベントを一定時間読み取る。

使い方:
    sudo python3 probe.py <秒数> [デバイス名]

デバイス名の既定は "xremap"。
EV_KEY (type=1) のイベントを「<キーコード> <値>」の形式で 1 行ずつ標準出力に出す。
値は 1=押下 / 0=解放 / 2=リピート。
"""

import glob
import os
import select
import struct
import sys
import time

EVENT_FORMAT = "@llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 1


def find_device(name):
    """名前が一致する /dev/input/eventN を返す。"""
    for sys_path in sorted(glob.glob("/sys/class/input/event*")):
        name_path = os.path.join(sys_path, "device", "name")
        try:
            with open(name_path, encoding="utf-8", errors="replace") as handle:
                if handle.read().strip() == name:
                    return "/dev/input/" + os.path.basename(sys_path)
        except OSError:
            continue
    return None


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
    wanted = sys.argv[2] if len(sys.argv) > 2 else "xremap"

    path = find_device(wanted)
    if path is None:
        print("ERROR: 入力デバイスが見つかりません: %s" % wanted, file=sys.stderr)
        return 2

    print("# device=%s (%s)" % (path, wanted), file=sys.stderr)
    deadline = time.monotonic() + duration

    with open(path, "rb", buffering=0) as device:
        os.set_blocking(device.fileno(), False)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([device], [], [], remaining)
            if not ready:
                continue
            chunk = device.read(EVENT_SIZE * 64)
            if not chunk:
                continue
            for offset in range(0, len(chunk) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, ev_type, code, value = struct.unpack_from(
                    EVENT_FORMAT, chunk, offset
                )
                if ev_type == EV_KEY:
                    print("%d %d" % (code, value), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

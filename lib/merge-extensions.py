#!/usr/bin/env python3
"""GNOME の enabled-extensions に UUID を足した値を出力する。

    merge-extensions.py "<現在の値>" <UUID>...

現在の値は dconf の書式 (["a", "b"] 形式) をそのまま渡す。
既にある UUID は重複させず、並び順も変えない。
何も足すものが無ければ入力と同じ文字列を返すので、
呼び出し側は「変化したかどうか」で書き込みの要否を判断できる。
"""

import re
import sys


def main():
    if len(sys.argv) < 2:
        print("使い方: merge-extensions.py <現在の値> <UUID>...", file=sys.stderr)
        return 2

    current = sys.argv[1]
    wanted = sys.argv[2:]

    have = re.findall(r"'([^']*)'", current)
    merged = list(have) + [u for u in wanted if u not in have]
    print("[" + ", ".join("'%s'" % u for u in merged) + "]")
    return 0


if __name__ == "__main__":
    sys.exit(main())

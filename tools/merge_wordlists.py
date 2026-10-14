#!/usr/bin/env python3
"""Build a Microsoft Pinyin word list from a public dictionary.

The Microsoft Pinyin self-learning lexicon accepts at most 20000 entries - the
converter reports "skipped" beyond that, and the native container stores the count in
its header (offset 0x0C). Personal entries therefore get priority: they are kept first
and the public list is trimmed to fill the remaining budget.

Usage:
    python merge_wordlists.py --public jieba-dict.txt --out merged.txt
                              [--personal personal.txt] [--top 20000]

Input
    --public   "<word> <freq> [pos]" per line (jieba-style) or a plain word list
    --personal existing entries to keep, one per line (optional)
Output
    one word per line: personal entries first, then public words by descending frequency

Requires: nothing beyond the standard library.
"""

import argparse
import re
import sys

CJK = re.compile(r"^[\u4e00-\u9fa5]{2,8}$")


def load_public(path):
    """Return public words sorted by descending frequency, pure-CJK 2-8 chars only."""
    rows = []
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            word = parts[0]
            if not CJK.match(word):
                continue
            freq = 0
            if len(parts) > 1:
                try:
                    freq = int(parts[1])
                except ValueError:
                    freq = 0
            rows.append((freq, word))

    rows.sort(key=lambda x: -x[0])
    seen, out = set(), []
    for _, word in rows:
        if word in seen:
            continue
        seen.add(word)
        out.append(word)
    return out


def load_personal(path):
    if not path:
        return []
    out = []
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            w = line.strip().split()[0] if line.strip() else ""
            if CJK.match(w):
                out.append(w)
    return out


def main():
    ap = argparse.ArgumentParser(description="Public dictionary -> Microsoft Pinyin word list")
    ap.add_argument("--public", required=True, nargs="+",
                    help="one or more public dictionaries / word lists (in priority order)")
    ap.add_argument("--out", required=True, help="output word list")
    ap.add_argument("--personal", help="existing entries to keep (one per line)")
    ap.add_argument("--top", type=int, default=20000,
                    help="total entry budget; the IME lexicon caps at 20000")
    args = ap.parse_args()

    personal, seen = [], set()
    for w in load_personal(args.personal):
        if w not in seen:
            seen.add(w)
            personal.append(w)
    if len(personal) > args.top:
        personal = personal[:args.top]

    budget = max(0, args.top - len(personal))
    public = []
    for path in args.public:
        for w in load_public(path):
            if w in seen:
                continue
            seen.add(w)
            public.append(w)
            if len(public) >= budget:
                break
        if len(public) >= budget:
            break

    final = personal + public
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(final) + "\n")

    print("personal kept :", len(personal))
    print("public kept   :", len(public))
    print("written       :", len(final), "->", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

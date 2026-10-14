#!/usr/bin/env python3
"""从本机微软拼音的"可读容器"里提取内置已知词，供选词时剔除。

为什么需要它：微软拼音内置词库覆盖面极广（含低频词、县区地名、人名、4 字词），
把内置已有的词灌进我们的 2 万额度等于浪费。剔除要先知道"内置有什么"。

能读出什么（实测）：
  C:\\Windows\\InputMethod\\CHS\\ChsPinyinDM*.lex   49 个专业词典（IMDX，明文 UTF-16）→ 约 17.9 万词
  C:\\Windows\\InputMethod\\CHS\\ChsPinyinAP.lex    内置短语（mschxudp，明文）        → 约 4.5 万条
  C:\\Windows\\InputMethod\\CHS\\ChsDoublePinyinUDP.lex 双拼短语（明文）
读不出的：ChsPinyin.lex（核心词库，索引编码，非明文；见 docs/format-and-limits.md）

用法：
    python extract_builtin_words.py [--out cache/builtin] [--ime-dir <path>]
"""

import argparse
import glob
import os
import re
import sys

import utf8_console  # noqa: F401

DEFAULT_IME_DIR = r'C:\Windows\InputMethod\CHS'
CJK = re.compile(r'[\u4e00-\u9fa5]{2,16}')


def utf16_words(path):
    try:
        raw = open(path, 'rb').read()
    except OSError:
        return set()
    return set(CJK.findall(raw.decode('utf-16-le', 'ignore')))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ime-dir', default=DEFAULT_IME_DIR)
    ap.add_argument('--out', default='cache/builtin')
    args = ap.parse_args()

    if not os.path.isdir(args.ime_dir):
        print('未找到内置词库目录: %s' % args.ime_dir)
        print('（非 Windows 或未安装微软拼音时，可跳过本步骤，但选词时会失去"剔除内置已知词"能力）')
        return 1

    domain, phrase = set(), set()
    dm_files = sorted(glob.glob(os.path.join(args.ime_dir, 'ChsPinyinDM*.lex')))
    for p in dm_files:
        domain |= utf16_words(p)
    for name in ('ChsPinyinAP.lex', 'ChsDoublePinyinUDP.lex'):
        phrase |= utf16_words(os.path.join(args.ime_dir, name))

    os.makedirs(args.out, exist_ok=True)
    d1 = os.path.join(args.out, 'builtin-domain-words.txt')
    d2 = os.path.join(args.out, 'builtin-phrase-words.txt')
    open(d1, 'w', encoding='utf-8', newline='\n').write('\n'.join(sorted(domain)) + '\n')
    open(d2, 'w', encoding='utf-8', newline='\n').write('\n'.join(sorted(phrase)) + '\n')

    print('专业词典 %d 个文件 -> %d 词  (%s)' % (len(dm_files), len(domain), d1))
    print('内置短语           -> %d 条  (%s)' % (len(phrase), d2))
    print('合计可剔除: %d' % len(domain | phrase))
    print('注意：核心词库 ChsPinyin.lex 是索引编码，读不出（见 docs/format-and-limits.md），'
          '所以实际内置覆盖比这个数字更高。')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""仓库自检：开源结构完整性 + 词表/容器的格式不变量。

用法：
    python tests/test_selfcheck.py           # 全部检查
    python tests/test_selfcheck.py --quick   # 跳过运行产物相关检查

纯 stdlib，无第三方依赖。
"""

import argparse
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import utf8_console  # noqa: E402,F401

CJK = re.compile('^[' + u'\u3007' + u'\u4e00' + '-' + u'\u9fa5' + ']{2,15}$')

REQUIRED_FILES = [
    'README.md', 'LICENSE', 'CHANGELOG.md', '.gitignore',
    'skill/SKILL.md', 'skill/sources.psd1', 'skill/profile.example.json',
    'tools/build_profile_lexicon.py', 'tools/fetch_sources.py',
    'tools/extract_builtin_words.py', 'tools/merge_wordlists.py', 'tools/utf8_console.py',
    'docs/format-and-limits.md', 'docs/runbook.md', 'docs/privacy.md',
    'scripts/A/Backup-PinyinData.ps1', 'scripts/A/Import-Lexicon.ps1',
    'scripts/A/Set-PinyinPrivacy.ps1', 'scripts/A/Restore-PinyinData.ps1',
    'scripts/lib/PinyinBoost.Common.psm1',
]

IGNORED_PATTERNS = [
    'cache/', 'out/', 'artifacts/', '*.mspinyin.dat',
    'tools/imewlconverter/', 'data/lexicons/*', 'skill/profile.json',
    'config/config.psd1', '__pycache__/',
]

PRIVATE_FILES = ['skill/profile.json', 'config/config.psd1']


class Check:
    def __init__(self):
        self.passed, self.failed = [], []

    def ok(self, name):
        self.passed.append(name)

    def fail(self, name, why):
        self.failed.append((name, why))

    def assertTrue(self, name, cond, why):
        self.ok(name) if cond else self.fail(name, why)


def check_structure(c):
    for rel in REQUIRED_FILES:
        p = os.path.join(ROOT, rel)
        c.assertTrue('exists:' + rel, os.path.isfile(p) and os.path.getsize(p) > 0, '缺失或为空')


def check_gitignore(c):
    path = os.path.join(ROOT, '.gitignore')
    if not os.path.isfile(path):
        c.fail('gitignore', '文件不存在')
        return
    lines = [l.strip() for l in open(path, encoding='utf-8') if l.strip() and not l.startswith('#')]
    for pat in IGNORED_PATTERNS:
        c.assertTrue('ignore:' + pat, pat in lines, '.gitignore 未覆盖 %s（个人数据/产物有泄露风险）' % pat)


def check_wordlists(c):
    d = os.path.join(ROOT, 'skill', 'wordlists')
    if not os.path.isdir(d):
        c.fail('wordlists', 'skill/wordlists 不存在')
        return
    for name in sorted(os.listdir(d)):
        if not name.endswith('.txt'):
            continue
        bad = []
        n = 0
        for line in open(os.path.join(d, name), encoding='utf-8'):
            w = line.strip()
            if not w or w.startswith('#'):
                continue
            n += 1
            if not CJK.match(w):
                bad.append(w)
        c.assertTrue('wordlist:' + name,
                     n > 0 and not bad,
                     '%d 条中含 %d 条非法（非纯中文或长度越界）: %s' % (n, len(bad), bad[:5]))


def check_sources_registry(c):
    p = os.path.join(ROOT, 'skill', 'sources.psd1')
    if not os.path.isfile(p):
        c.fail('sources.psd1', '不存在')
        return
    txt = open(p, encoding='utf-8').read()
    urls = re.findall(r"https?://[^\s'\",}]+", txt)
    http = [u for u in urls if u.startswith('http://')]
    c.assertTrue('sources:https-only', not http, '存在明文 http 源: %s' % http[:3])
    c.assertTrue('sources:license-recorded', txt.count('License') >= 1 and 'MIT' in txt,
                 '词库源未记录许可证')


def _git_tracked(rel):
    import subprocess
    r = subprocess.run(['git', 'ls-files', '--error-unmatch', rel],
                       cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0


def check_private_not_committed(c):
    for rel in PRIVATE_FILES:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            c.ok('private:' + rel + ' (不存在，跳过)')
            continue
        c.assertTrue('private:' + rel, not _git_tracked(rel), '个人数据已被 git 跟踪，必须 untrack')


def check_container(c):
    d = os.path.join(ROOT, 'artifacts', 'lexicon-out')
    if not os.path.isdir(d):
        c.ok('container (无产物，跳过)')
        return
    dats = [f for f in os.listdir(d) if f.endswith('.mspinyin.dat')]
    if not dats:
        c.ok('container (无 .dat，跳过)')
        return
    for f in dats:
        p = os.path.join(d, f)
        b = open(p, 'rb').read()
        magic_ok = b[:4] == bytes.fromhex('55aa8881')
        n = struct.unpack('<I', b[12:16])[0] if len(b) >= 16 else -1
        expect = ((9228 + 60 * n + 1023) // 1024) * 1024
        c.assertTrue('container:' + f,
                     magic_ok and 0 < n <= 20000 and expect == len(b),
                     'magic=%s count=%d size=%d 期望=%d（自学习词库格式或上限不变量被破坏）'
                     % (b[:4].hex(), n, len(b), expect))


def check_lexicon_cap(c):
    p = os.path.join(ROOT, 'data', 'lexicons', 'profile-lexicon.txt')
    if not os.path.isfile(p):
        c.ok('lexicon-cap (无词表，跳过)')
        return
    words = [l.strip() for l in open(p, encoding='utf-8') if l.strip() and not l.startswith('#')]
    c.assertTrue('lexicon:count<=20000', len(words) <= 20000, '%d 条，超过 IME 硬上限会被截断' % len(words))
    c.assertTrue('lexicon:unique', len(set(words)) == len(words), '存在重复词条')
    bad = [w for w in words if not CJK.match(w)]
    c.assertTrue('lexicon:pure-cjk-2-15', not bad, '非法词条: %s' % bad[:5])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--quick', action='store_true', help='跳过运行产物相关检查')
    args = ap.parse_args()

    c = Check()
    check_structure(c)
    check_gitignore(c)
    check_wordlists(c)
    check_sources_registry(c)
    check_private_not_committed(c)
    if not args.quick:
        check_container(c)
        check_lexicon_cap(c)

    print('自检 %d 项通过 / %d 项失败' % (len(c.passed), len(c.failed)))
    for name, why in c.failed:
        print('  [FAIL] %-34s %s' % (name, why))
    if not c.failed:
        print('  all good')
    return 1 if c.failed else 0


if __name__ == '__main__':
    sys.exit(main())

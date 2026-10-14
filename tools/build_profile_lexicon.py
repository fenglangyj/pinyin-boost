#!/usr/bin/env python3
"""画像 → 20,000 条微软拼音词表。

流程：加载数据源（cache/ 与 skill/wordlists/）→ 过滤（纯中文 2-15 字）
      → 剔除内置已知词（cache/builtin/）→ 去重 → 按类别配额打分排序 → 截断到 20000

用法：
    python build_profile_lexicon.py --profile skill/profile.json --out out/profile-lexicon.txt
    python build_profile_lexicon.py --profile skill/profile.json --out out/x.txt --dry-run
"""

import argparse
import collections
import glob
import json
import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CJK = re.compile(r'^[\u3007\u4e00-\u9fa5]{2,15}$')     # 纯中文 2-15 字（IME 记录上限 15）
CAP = 20000

# 数据源（相对项目根）。len_range 用于把"长短语"单独成类。
SOURCES = {
    'jieba':          dict(path='cache/jieba-dict/dict.txt',            category='general', weight=1.0, len_range=(2, 4)),
    'jieba-long':     dict(path='cache/jieba-dict/dict.txt',            category='phrase',  weight=1.2, len_range=(5, 8)),
    'xinhua-ci':      dict(path='cache/xinhua/ci.json',                 category='general', weight=0.8, len_range=(2, 4), fmt='json', field='ci'),
    'xinhua-ci-long': dict(path='cache/xinhua/ci.json',                 category='phrase',  weight=1.0, len_range=(5, 8), fmt='json', field='ci'),
    'thuocl-it':      dict(path='cache/thuocl/THUOCL_IT.txt',           category='domain',  weight=1.0),
    'thuocl-place':   dict(path='cache/thuocl/THUOCL_diming.txt',       category='place',   weight=1.0),
    'thuocl-car':     dict(path='cache/thuocl/THUOCL_car.txt',          category='brand',   weight=1.0),
    'thuocl-people':  dict(path='cache/thuocl/THUOCL_lishimingren.txt', category='proper',  weight=1.0),
    'thuocl-idiom':   dict(path='cache/thuocl/THUOCL_chengyu.txt',      category='idiom',   weight=1.0),
    'xinhua-idiom':   dict(path='cache/xinhua/idiom.json',              category='idiom',   weight=0.8, fmt='json', field='word'),
    'wiki-words':     dict(path='cache/wiki/wiki-words.txt',            category='media',   weight=1.0, fmt='tagged'),
    # 本仓库附带的 agent 整理清单（provenance=agent-curated，需用户确认）
    'wl-bike':        dict(path='skill/wordlists/bike-zh.txt',          category='brand',   weight=1.8),
    'wl-games':       dict(path='skill/wordlists/games-zh.txt',         category='media',   weight=1.5),
    'wl-slang':       dict(path='skill/wordlists/slang-zh.txt',         category='slang',   weight=1.4),
}
WIKI_TAG_TO_CAT = {'机车': 'brand', '游戏': 'media', '影视': 'media', '新词': 'slang'}

CATEGORY_WEIGHT = {'private': 10.0, 'domain': 1.6, 'brand': 1.8, 'media': 1.5, 'slang': 1.4,
                   'place': 1.2, 'proper': 1.1, 'general': 1.0, 'phrase': 1.2, 'idiom': 0.5}
# 配额（合计 20000）
QUOTA = {'private': CAP, 'domain': 5000, 'place': 4000, 'general': 3000, 'phrase': 3000,
         'proper': 2000, 'media': 1200, 'brand': 700, 'slang': 600, 'idiom': 500}
LOCAL_HINT = ('四川', '重庆', '成都', '川', '渝', '巴蜀', '山城', '蓉')
INDUSTRY_SOURCE = {'IT': 'thuocl-it'}          # 画像行业 → 领域源（可扩展）


def length_bonus(w):
    n = len(w)
    return 0.6 if n == 2 else (1.0 if n <= 4 else (1.2 if n <= 6 else 1.1))


def load(path, cfg):
    full = os.path.join(PROJECT, path)
    if not os.path.exists(full):
        return []
    fmt = cfg.get('fmt')
    if fmt == 'json':
        field = cfg.get('field', 'word')
        return [(str(it.get(field, '')).strip(), 1.0, '') for it in json.load(open(full, encoding='utf-8'))]
    rows = []
    with open(full, encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            if fmt == 'tagged':
                p = line.split('\t')
                rows.append((p[0].strip(), 1.0, p[1].strip() if len(p) > 1 else ''))
                continue
            p = re.split(r'[\t ]+', line.strip())
            wt = 1.0
            if len(p) > 1:
                try:
                    wt = float(p[1])
                except ValueError:
                    wt = 1.0
            rows.append((p[0], wt, ''))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--profile', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    profile = json.load(open(args.profile, encoding='utf-8'))
    print('画像: 行业=%s 兴趣=%s 地区=%s' % (profile.get('industry'), profile.get('interests'), profile.get('city')))

    builtin = set()
    for rel in ('cache/builtin/builtin-domain-words.txt', 'cache/builtin/builtin-phrase-words.txt'):
        p = os.path.join(PROJECT, rel)
        if os.path.exists(p):
            builtin |= set(open(p, encoding='utf-8').read().split())
    print('内置已知词（剔除用）: %d %s' % (len(builtin), '' if builtin else '（未生成，先跑 tools/extract_builtin_words.py）'))

    # 组装源：基础 + 画像命中的行业源 + 地名（cache/divisions/place-*.txt）
    active = ['jieba', 'jieba-long', 'xinhua-ci', 'xinhua-ci-long', 'thuocl-place', 'thuocl-people',
              'thuocl-idiom', 'xinhua-idiom', 'wiki-words', 'wl-bike', 'wl-games', 'wl-slang', 'thuocl-car']
    for ind in (profile.get('industry') or []):
        if ind in INDUSTRY_SOURCE:
            active.append(INDUSTRY_SOURCE[ind])
    dyn = []
    for i, p in enumerate(sorted(glob.glob(os.path.join(PROJECT, 'cache/divisions/place-*.txt')))):
        sid = 'place-div%d' % i
        SOURCES[sid] = dict(path=os.path.relpath(p, PROJECT).replace('\\', '/'), category='place', weight=1.3)
        dyn.append(sid)
    active = list(dict.fromkeys(active + dyn))

    pool, stats = {}, collections.Counter()
    for sid in active:
        cfg = SOURCES.get(sid)
        if not cfg:
            continue
        rows = load(cfg['path'], cfg)
        lo, hi = cfg.get('len_range', (2, 15))
        kept = 0
        for w, wt, tag in rows:
            if not CJK.match(w) or not (lo <= len(w) <= hi) or w in builtin:
                continue
            cat = WIKI_TAG_TO_CAT.get(tag.split('-')[0], cfg['category']) if cfg.get('fmt') == 'tagged' else cfg['category']
            score = cfg['weight'] * CATEGORY_WEIGHT.get(cat, 1.0) * length_bonus(w) * (1.0 + min(wt, 100000) / 200000.0)
            if cat == 'place' and any(h in w for h in LOCAL_HINT):
                score *= 2.5
            if w not in pool or score > pool[w][0]:
                pool[w] = (score, cat); kept += 1
        stats[sid] = kept
        print('  %-16s %-42s 保留 %6d' % (sid, cfg['path'], kept))

    print('\n去重后候选池: %d' % len(pool))
    by_cat = collections.defaultdict(list)
    for w, (s, c) in pool.items():
        by_cat[c].append((s, w))
    chosen, counts = [], collections.Counter()
    for cat, quota in QUOTA.items():
        for s, w in sorted(by_cat.get(cat, []), reverse=True)[:quota]:
            chosen.append(w); counts[cat] += 1
    if len(chosen) < CAP:
        have = set(chosen)
        for s, w in sorted(((s, w) for w, (s, c) in pool.items() if w not in have), reverse=True)[:CAP - len(chosen)]:
            chosen.append(w); counts['fill'] += 1
    chosen = chosen[:CAP]

    print('类别构成:', dict(counts))
    print('长度分布:', dict(sorted(collections.Counter(len(w) for w in chosen).items())))
    print('抽样:', ' '.join(chosen[:12]))

    if args.dry_run:
        print('（dry-run：未写文件）')
        return 0

    out = os.path.join(PROJECT, args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(chosen) + '\n')
    print('\n已写出 %d 条 -> %s' % (len(chosen), out))

    # 来源报告
    rep = os.path.splitext(out)[0] + '-report.md'
    with open(rep, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# 词库来源报告\n\n| 数据源 | 路径 | 保留 |\n|---|---|---:|\n')
        for sid, n in stats.most_common():
            f.write('| %s | `%s` | %d |\n' % (sid, SOURCES[sid]['path'] if sid in SOURCES else '-', n))
        f.write('\n类别构成: %s\n\n长度分布: %s\n' % (dict(counts), dict(sorted(collections.Counter(len(w) for w in chosen).items()))))
        f.write('\n> provenance：`cache/` 下为 verified-open（许可见 manifest.json）；'
                '`skill/wordlists/` 为 agent-curated，**请人工确认**。\n')
    print('报告 -> %s' % rep)
    print('\n下一步：把词表放进 data/lexicons/ 后转容器')
    print('  powershell -ExecutionPolicy Bypass -File .\\scripts\\A\\Import-Lexicon.ps1 -DownloadTool')
    return 0


if __name__ == '__main__':
    sys.exit(main())

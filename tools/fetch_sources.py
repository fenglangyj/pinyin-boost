#!/usr/bin/env python3
"""下载开放数据源到本地缓存（stdlib only，支持代理与断点复用）。

用法：
    python fetch_sources.py                          # 下载全部已验证源
    python fetch_sources.py --proxy http://127.0.0.1:7890
    python fetch_sources.py --only jieba,thuocl-it   # 只下载指定源
    python fetch_sources.py --skip-divisions         # 跳过 4MB 的行政区划
    python fetch_sources.py --province 50,51         # 顺便按省提取地名（重庆=50 四川=51）
    python fetch_sources.py --wiki 摩托车制造商,网络流行语   # 用维基分类 API 补充中文词条

缓存结构：cache/<group>/<file> + cache/<group>/manifest.json（按源 id 合并，
每条含 url/sha256/size/license/downloaded_at/provenance）
"""

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

import utf8_console  # noqa: F401

RAW = 'https://raw.githubusercontent.com'
SOURCES = {
    'jieba':      (RAW + '/fxsjy/jieba/master/jieba/dict.txt', 'cache/jieba-dict/dict.txt', 'MIT'),
    'xinhua-idiom': (RAW + '/pwxcoo/chinese-xinhua/master/data/idiom.json', 'cache/xinhua/idiom.json', 'MIT'),
    'xinhua-ci':  (RAW + '/pwxcoo/chinese-xinhua/master/data/ci.json', 'cache/xinhua/ci.json', 'MIT'),
    'divisions':  (RAW + '/modood/Administrative-divisions-of-China/master/dist/streets.json', 'cache/divisions/streets.json', 'WTFPL'),
}
THUOCL = ['IT', 'medical', 'law', 'caijing', 'food', 'car', 'animal', 'diming', 'lishimingren', 'poem', 'chengyu']
for _n in THUOCL:
    SOURCES['thuocl-' + _n.lower()] = (RAW + '/thunlp/THUOCL/master/data/THUOCL_%s.txt' % _n,
                                       'cache/thuocl/THUOCL_%s.txt' % _n, 'MIT')

WIKI_API = 'https://zh.wikipedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:%s&cmlimit=500&cmtype=page&format=json'


def opener(proxy=None):
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({'http': proxy, 'https': proxy}))
    return urllib.request.build_opener(*handlers)


def get(url, proxy=None, timeout=300):
    req = urllib.request.Request(url, headers={'User-Agent': 'pinyin-boost/0.3'})
    with opener(proxy).open(req, timeout=timeout) as r:
        return r.read()


def write_manifest(dest, sid, url, license_, size, digest, provenance='verified-open'):
    """按源 id 合并写入 manifest.json，避免同目录多源互相覆盖。"""
    path = os.path.join(os.path.dirname(dest), 'manifest.json')
    data = {}
    if os.path.exists(path):
        try:
            raw = json.load(open(path, encoding='utf-8'))
            if isinstance(raw, dict):
                if raw.get('id'):
                    data[raw['id']] = {k: v for k, v in raw.items() if k != 'id'}
                else:
                    data = raw
        except (ValueError, OSError):
            data = {}
    data[sid] = {
        'url': url, 'license': license_, 'size': size, 'sha256': digest,
        'downloaded_at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'provenance': provenance,
    }
    json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)


def _manifest_has(dest, sid):
    path = os.path.join(os.path.dirname(dest), 'manifest.json')
    if not os.path.exists(path):
        return False
    try:
        raw = json.load(open(path, encoding='utf-8'))
    except (ValueError, OSError):
        return False
    if isinstance(raw, dict) and raw.get('id') == sid:
        return True
    return isinstance(raw, dict) and sid in raw and not raw.get('id')


def fetch(sid, url, dest, license_, proxy, force=False, retries=2):
    if os.path.exists(dest) and os.path.getsize(dest) > 0 and not force:
        if not _manifest_has(dest, sid):
            body = open(dest, 'rb').read()
            write_manifest(dest, sid, url, license_, len(body),
                           hashlib.sha256(body).hexdigest(), provenance='cached-local')
        print('  %-16s 命中缓存 %s' % (sid, dest))
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    data = None
    for attempt in range(retries + 1):
        try:
            data = get(url, proxy)
            break
        except Exception as e:
            print('  %-16s 下载失败(第 %d 次): %s' % (sid, attempt + 1, e))
            if attempt < retries:
                time.sleep(2)
    if data is None:
        return None
    open(dest, 'wb').write(data)
    write_manifest(dest, sid, url, license_, len(data), hashlib.sha256(data).hexdigest())
    print('  %-16s 已下载 %8d bytes  (%s)' % (sid, len(data), license_))
    return dest


def extract_provinces(streets_path, codes, out_dir):
    """把行政区划按省提取为地名清单（如 50=重庆 51=四川）"""
    import re
    d = json.load(open(streets_path, encoding='utf-8'))
    names = [x.get('name', '') for x in d if x.get('provinceCode') in codes]
    cjk = re.compile(r'^[\u3007\u4e00-\u9fa5]{2,15}$')
    names = list(dict.fromkeys(n for n in names if cjk.match(n)))
    os.makedirs(out_dir, exist_ok=True)
    tag = '-'.join(sorted(codes))
    out = os.path.join(out_dir, 'place-%s.txt' % tag)
    open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(names) + '\n')
    print('  %-16s 省 %s -> %d 条 (%s)' % ('divisions', ','.join(codes), len(names), out))
    return out


def fetch_wiki(cats, out_path, proxy):
    import re
    cjk = re.compile(r'^[\u3007\u4e00-\u9fa5]{2,15}$')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    seen, lines = set(), []
    for cat in cats:
        url = WIKI_API % urllib.parse.quote(cat)
        try:
            j = json.loads(get(url, proxy, timeout=60).decode('utf-8'))
        except Exception as e:
            print('  维基分类 %s 失败: %s' % (cat, e)); continue
        for m in j.get('query', {}).get('categorymembers', []):
            t = re.sub(r'（[^）]*）|\([^)]*\)', '', m.get('title', '')).strip()
            if cjk.match(t) and t not in seen:
                seen.add(t)
                lines.append('%s\t%s' % (t, cat))
        print('  维基分类 %-16s -> 累计 %d 条' % (cat, len(lines)))
    open(out_path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    print('  wiki-words 写出: %s (%d 条；注意维基分类较稀疏)' % (out_path, len(lines)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--proxy', default='')
    ap.add_argument('--only', default='')
    ap.add_argument('--skip-divisions', action='store_true')
    ap.add_argument('--province', default='')
    ap.add_argument('--wiki', default='')
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()

    proxy = args.proxy or os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy') or None
    if proxy:
        print('使用代理: %s' % proxy)

    ids = [s.strip() for s in args.only.split(',') if s.strip()] or list(SOURCES)
    if args.skip_divisions and 'divisions' in ids:
        ids.remove('divisions')

    print('下载数据源（%d 个）:' % len(ids))
    ok = 0
    for sid in ids:
        if sid not in SOURCES:
            print('  %-16s 未注册的源，跳过' % sid); continue
        url, dest, lic = SOURCES[sid]
        if fetch(sid, url, dest, lic, proxy, args.force):
            ok += 1

    if args.province:
        sp = SOURCES['divisions'][1]
        if os.path.exists(sp):
            extract_provinces(sp, set(c.strip() for c in args.province.split(',')), 'cache/divisions')
    if args.wiki:
        fetch_wiki([c.strip() for c in args.wiki.split(',')], 'cache/wiki/wiki-words.txt', proxy)

    print('\n完成 %d/%d。缓存目录可用，接着跑：' % (ok, len(ids)))
    print('  python tools/extract_builtin_words.py')
    print('  python tools/build_profile_lexicon.py --profile skill/profile.json --out out/profile-lexicon.txt')
    return 0


if __name__ == '__main__':
    sys.exit(main())

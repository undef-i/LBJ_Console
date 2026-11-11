#!/usr/bin/env python3
import argparse
import csv
import importlib.util
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'}
XG = 'http://www.xiaguanzhan.com/'
EMU = 'https://emu.passearch.info/index.php?type=model&keyword='

RE_NORMAL = re.compile(r'<a class="jytb" href="ProView\.asp\?ProId=(\d+)" target="_blank">([^<]+)</a>')
RE_SPECIAL = re.compile(r'<td height="33"><div align="center"><span class="bottombr"><a href="ProView\.asp\?ProId=(\d+)" target="_blank">([^<]+)</a></span></div></td>')
RE_EMU_XG = re.compile(r'<td height="\d+"><div align="center"><span class="bottombr"><a href="ProView\d*\.asp\?ProId=(\d+)" target="_blank">([^<]+)</a></span></div></td>')
PATTERNS = (RE_NORMAL, RE_SPECIAL, RE_EMU_XG)
RE_PAGES = re.compile(r"\[页次<Font color='Red'>1</Font>/(\d+)页\]")
RE_PAGES_EMU = re.compile(r'\((\d+)/(\d{1,2})\)')
RE_PHOTO = re.compile(r'<td width="652"><a href="(.*?)"></a>')
ID_TOKEN = re.compile(r'^[A-Za-z0-9]+-.+$')
CJK = re.compile(r'[\u4e00-\u9fff]')
RE_INDEX = re.compile(r'href="([^"]+\.asp[^"]*)"[^>]*>([^<]*)</a>')
RE_LIST_LINK = re.compile(r'href="([^"]*-3\.asp)"', re.I)


def fetch(url, encoding='gb18030', tries=3):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode(encoding, errors='replace')
        except Exception as e:
            last = e
            time.sleep(2 * (i + 1))
    raise RuntimeError(f'fetch failed {url}: {last}')


def total_pages(text):
    m = RE_PAGES.search(text)
    if m:
        return int(m.group(1))
    m = RE_PAGES_EMU.search(text)
    return int(m.group(2)) if m else 1


def parse_loco_list(text, pattern, with_alloc=True):
    out = []
    for pro_id, raw in pattern.findall(text):
        if not CJK.search(raw):
            continue
        veh = None
        alloc = ''
        tokens = raw.split(' ')
        for i, tok in enumerate(tokens):
            if ID_TOKEN.match(tok):
                veh = tok
                if with_alloc and i + 1 < len(tokens):
                    alloc = tokens[i + 1]
                break
        if veh is not None:
            out.append((pro_id, veh, alloc if with_alloc else ''))
    return out


def fetch_list_pages(first_url):
    text = fetch(first_url)
    pattern = None
    rows = []
    for p in PATTERNS:
        rows = parse_loco_list(text, p, with_alloc=p is not RE_EMU_XG)
        if rows:
            pattern = p
            break
    if pattern is None:
        return []
    n = total_pages(text)
    for i in range(2, n + 1):
        sep = '&' if '?' in first_url else '?'
        t = fetch(f'{first_url}{sep}Page={i}')
        rows += parse_loco_list(t, pattern, with_alloc=pattern is not RE_EMU_XG)
        time.sleep(0.2)
    return rows


def strip_tags(html):
    html = re.sub(r'(?i)<br\s*/?>', '\n', html)
    return re.sub(r'<[^>]+>', '', html)


def field(text, label):
    m = re.search(label + r'[:：]([^\n<]+)', text)
    if not m:
        return ''
    v = m.group(1).strip()
    return '' if v == '暂无数据' else v


def parse_detail(html):
    text = strip_tags(html)
    digits = re.sub(r'\D', '', field(text, '拍摄日期'))
    m = RE_PHOTO.search(html)
    return {
        'manufacturer': field(text, '生产厂商'),
        'photo_date': digits[:6] if len(digits) >= 6 else '',
        'photo_author': field(text, '拍摄作者'),
        'photo_url': f'{XG}{m.group(1)}' if m else '',
    }


def parse_emu_table(html):
    rows = []
    for chunk in html.split('<tr'):
        km = re.search(r'emu_detail\.php\?keyword=([A-Za-z0-9-]+)', chunk)
        if not km:
            continue
        cells = [re.sub(r'\s+', ' ', strip_tags(c)).strip()
                 for c in re.findall(r'<td[^>]*>(.*?)</td>', chunk, re.S)]
        if len(cells) < 6:
            continue
        keyword = km.group(1)
        bureau, dept, mfr, note = cells[2], cells[3], cells[4], cells[5]
        if 'CR200J' in keyword or 'CR2OOJ' in keyword:
            tail = keyword.split('-')[-1]
            base = re.sub(r'[\u4e00-\u9fff\u3002\uff0c]|\uff08[^\uff08\uff09]*\uff09', '', note)
            keyword = f'{base}-{tail}'
        if bureau == '' and dept == '':
            alloc = '暂无数据'
        else:
            alloc = re.sub(r'集团动车所$', '集团', f'{bureau}{dept}动车所')
        rows.append({'id': keyword, 'allocation': alloc, 'manufacturer': mfr, 'note': note})
    return rows


def discover(index_page):
    hubs = {}
    text = fetch(XG + index_page)
    for url, label in RE_INDEX.findall(text):
        if 'ProView' in url:
            continue
        label = label.strip()
        tokens = [t for t in re.split(r'[/\s]+', label) if t]
        series = None
        if tokens and re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', tokens[-1]):
            series = tokens[-1]
        else:
            m = re.match(r'([A-Za-z][A-Za-z0-9-]*)型', label)
            if m:
                series = m.group(1)
        if series:
            hubs.setdefault(series, url)
    return hubs


def list_url(series, hub_url):
    if hub_url.lower().startswith('http'):
        hub = hub_url
    else:
        hub = XG + hub_url
    text = fetch(hub)
    for link in RE_LIST_LINK.findall(text):
        if link.split('/')[-1].lower().startswith(series.lower() + '-3'):
            return XG + link if not link.lower().startswith('http') else link
    return hub


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('resources_dir')
    ap.add_argument('--series', default='')
    ap.add_argument('--skip-emu', action='store_true')
    ap.add_argument('--skip-detail', action='store_true')
    ap.add_argument('--limit-detail', type=int, default=200)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    rdir = Path(args.resources_dir)
    base = json.loads((rdir / 'loco_base.json').read_text(encoding='utf-8'))

    stats = {'pages': 0, 'seen': 0, 'new': 0,
             'emu_seen': 0, 'emu_new': 0, 'emu_changed': 0, 'pro_filled': 0,
             'detail_fetched': 0, 'detail_filled': 0}

    by_series = {}
    for series, vehicles in base.items():
        idx = {}
        for v in vehicles:
            idx.setdefault((v.get('id', ''), v.get('allocation', '')), v)
        by_series[series] = idx

    def add_sighting(series, veh, alloc, pro_id):
        if not veh.upper().startswith(series.upper() + '-'):
            return
        if not veh.rsplit('-', 1)[-1].isdigit():
            return
        idx = by_series.setdefault(series, {})
        key = (veh, alloc)
        if key in idx:
            rec = idx[key]
            if pro_id and not rec.get('pro_id'):
                rec['pro_id'] = pro_id
                stats['pro_filled'] += 1
            return
        rec = {'id': veh, 'allocation': alloc, 'pro_id': pro_id}
        base.setdefault(series, []).append(rec)
        idx[key] = rec
        stats['new'] += 1

    loco_hubs = discover('jiche.asp')
    emu_hubs = {} if args.skip_emu else discover('pro3-1.asp')
    hubs = dict(loco_hubs)
    hubs.update(emu_hubs)

    for series, hub in hubs.items():
        if args.series and series != args.series:
            continue
        try:
            rows = fetch_list_pages(list_url(series, hub))
        except RuntimeError:
            continue
        stats['pages'] += 1
        stats['seen'] += len(rows)
        for pro_id, veh, alloc in rows:
            if series in emu_hubs:
                for rec in base.get(veh.rsplit('-', 1)[0], []):
                    if rec.get('id') == veh and not rec.get('pro_id'):
                        rec['pro_id'] = pro_id
                        stats['pro_filled'] += 1
            else:
                add_sighting(series, veh, alloc, pro_id)
        time.sleep(0.2)

    if not args.skip_emu:
        for model in emu_hubs:
            if args.series and model != args.series:
                continue
            url = f'{EMU}{model}'
            text = fetch(url, encoding='utf-8')
            rows = parse_emu_table(text)
            n = total_pages(text)
            for i in range(2, n + 1):
                rows += parse_emu_table(fetch(f'{url}&pagenum={i}', encoding='utf-8'))
                time.sleep(0.2)
            stats['pages'] += 1
            stats['emu_seen'] += len(rows)
            for row in rows:
                series = row['id'].rsplit('-', 1)[0]
                idx = by_series.setdefault(series, {})
                existing = None
                for (rid, _), rec in idx.items():
                    if rid == row['id']:
                        existing = rec
                        break
                if existing is None:
                    rec = {'id': row['id'], 'allocation': row['allocation'],
                           'manufacturer': row['manufacturer'],
                           'note': row['note'], 'pro_id': ''}
                    base.setdefault(series, []).append(rec)
                    idx[(row['id'], row['allocation'])] = rec
                    stats['emu_new'] += 1
                else:
                    changed = False
                    for f in ('allocation', 'manufacturer', 'note'):
                        if row[f] and existing.get(f, '') != row[f]:
                            existing[f] = row[f]
                            changed = True
                    if changed:
                        stats['emu_changed'] += 1
            time.sleep(0.2)

    if not args.skip_detail:
        todo = []
        for vehicles in base.values():
            for v in vehicles:
                if v.get('pro_id') and (not v.get('manufacturer') or not v.get('photo_date')):
                    todo.append(v)
        for v in todo[:args.limit_detail]:
            try:
                html = fetch(f"{XG}ProView.asp?ProId={v['pro_id']}")
            except RuntimeError:
                continue
            stats['detail_fetched'] += 1
            got = parse_detail(html)
            filled = False
            for f in ('manufacturer', 'photo_date', 'photo_author', 'photo_url'):
                if got[f] and not v.get(f):
                    v[f] = got[f]
                    filled = True
            if filled:
                stats['detail_filled'] += 1
            time.sleep(0.2)

    if not args.dry_run:
        (rdir / 'loco_base.json').write_text(
            json.dumps(base, ensure_ascii=False), encoding='utf-8')
        spec = importlib.util.spec_from_file_location(
            'convert_alloc', Path(__file__).resolve().parent / 'convert_alloc.py')
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        rows, skipped, gated = mod.build_rows(base)
        with open(rdir / 'loco_info.csv', 'w', encoding='utf-8', newline='') as f:
            csv.writer(f).writerows(rows)
        stats['csv_rows'] = len(rows)
        stats['skipped'] = skipped
        stats['gated'] = gated
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())

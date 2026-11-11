#!/usr/bin/env python3
import csv
import json
import sys
from collections import defaultdict

def build_rows(data):
    latest = {}
    skipped = 0
    gated = 0
    for series, vehicles in data.items():
        for v in vehicles:
            vid = v.get('id', '')
            suffix = vid[len(series) + 1:] if vid.startswith(series + '-') else ''
            if not suffix.isdigit():
                skipped += 1
                continue
            if '\ufffd' in (v.get('allocation', '') or ''):
                gated += 1
                continue
            key = (series, int(suffix))
            if key not in latest or (v.get('photo_date') or '') > (latest[key].get('photo_date') or ''):
                latest[key] = v
    groups = defaultdict(set)
    for (series, number), v in latest.items():
        allocation = v.get('allocation', '')
        groups[(series, allocation, v.get('manufacturer', ''))].add(number)
    rows = []
    for (series, allocation, manufacturer), numbers in groups.items():
        ordered = sorted(numbers)
        start = prev = ordered[0]
        for n in ordered[1:]:
            if n == prev + 1:
                prev = n
                continue
            rows.append((series, start, prev, allocation, '', manufacturer))
            start = prev = n
        rows.append((series, start, prev, allocation, '', manufacturer))
    rows.sort(key=lambda r: (r[0], r[1]))
    return rows, skipped, gated


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = json.load(open(src, encoding='utf-8'))
    rows, skipped, gated = build_rows(data)
    with open(dst, 'w', encoding='utf-8', newline='') as f:
        csv.writer(f).writerows(rows)
    print(f'rows={len(rows)} skipped={skipped} gated={gated}')


if __name__ == '__main__':
    main()

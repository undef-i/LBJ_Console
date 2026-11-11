#!/usr/bin/env python3
import hashlib
import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SPECS = [
    ('loco_info', '机车配属', 'loco_info.csv'),
    ('loco_type_info', '机车类型', 'loco_type_info.csv'),
]


def load_prev(source):
    try:
        if source.startswith('http'):
            with urllib.request.urlopen(source, timeout=30) as r:
                doc = json.loads(r.read().decode('utf-8'))
        else:
            doc = json.loads(Path(source).read_text(encoding='utf-8'))
        return {e['id']: e for e in doc['resources']}
    except Exception:
        return {}


def main():
    root = Path(sys.argv[1])
    prev = {}
    if len(sys.argv) > 2 and sys.argv[2]:
        prev = load_prev(sys.argv[2])
    if not prev and (root / 'manifest.json').exists():
        prev = load_prev(str(root / 'manifest.json'))
    now = datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')
    entries = []
    for rid, name, fname in SPECS:
        data = (root / fname).read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        old = prev.get(rid, {})
        version = old.get('version', '') if old.get('sha256') == sha else now
        entries.append({
            'id': rid,
            'name': name,
            'file': fname,
            'version': version,
            'sha256': sha,
            'size': len(data),
        })
    (root / 'manifest.json').write_text(
        json.dumps({'resources': entries}, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8')
    print(json.dumps(entries, ensure_ascii=False))


if __name__ == '__main__':
    main()

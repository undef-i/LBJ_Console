#!/bin/bash
set -euo pipefail
SRC=${1:?usage: inject.sh <resources-checkout-dir>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$SRC" "$ROOT" << 'PYEOF'
import hashlib
import json
import os
import shutil
import sys

src, root = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(src, 'manifest.json'), encoding='utf-8'))
for entry in manifest['resources']:
    path = os.path.join(src, entry['file'])
    data = open(path, 'rb').read()
    assert len(data) == entry['size'], entry['file']
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['file']
    target_dir = os.path.join(root, 'assets', 'data')
    os.makedirs(target_dir, exist_ok=True)
    shutil.copyfile(path, os.path.join(target_dir, entry['file']))
    print(entry['file'], entry['version'], len(data))
PYEOF

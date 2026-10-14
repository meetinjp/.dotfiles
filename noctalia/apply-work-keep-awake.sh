#!/usr/bin/env bash
# Install the local plugin without replacing Noctalia's other plugin settings.
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || exit 0
DOTFILES_NOCTALIA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$DOTFILES_NOCTALIA" <<'PY'
import json
from pathlib import Path
import sys

source = Path(sys.argv[1]) / 'work-keep-awake'
config = Path.home() / '.config/noctalia'
plugin = config / 'plugins/work-keep-awake'
plugin.mkdir(parents=True, exist_ok=True)
for name in ('Main.qml', 'manifest.json'):
    target = plugin / name
    desired = source / name
    if target.is_symlink() and target.resolve() == desired.resolve():
        continue
    if target.exists() or target.is_symlink():
        raise SystemExit(f'Refusing to replace unmanaged plugin file: {target}')
    target.symlink_to(desired)
path = config / 'plugins.json'
data = json.loads(path.read_text()) if path.exists() else {'version': 2, 'sources': []}
data.setdefault('states', {})['work-keep-awake'] = {'enabled': True, 'sourceUrl': 'local'}
temporary = path.with_suffix('.json.work-keep-awake.tmp')
temporary.write_text(json.dumps(data, indent=2) + '\n')
temporary.replace(path)
print(f'Enabled local work-keep-awake plugin in {path}; reload Noctalia if already running.')
PY

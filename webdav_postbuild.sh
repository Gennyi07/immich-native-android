#!/data/data/com.termux/files/usr/bin/bash
python3 - << 'PYEOF'
import re, os
path = os.path.expanduser('~/immich/app/dist/services/library.service.js')
with open(path, 'r') as f:
    c = f.read()
bypass = "if (importPath.startsWith('http://') || importPath.startsWith('https://')) { validation.isValid = true; return validation; }\n            "
pattern = r'(validation\.message = .Import path must be absolute)'
new_c = re.sub(pattern, bypass + r'\1', c, count=1)
if new_c != c:
    with open(path, 'w') as f:
        f.write(new_c)
    print('OK')
else:
    print('NOT FOUND')
PYEOF

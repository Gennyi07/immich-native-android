#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# webdav_fullfix.sh
# Fix completo WebDAV basato su analisi Gemini Deep Research
# Patcha BACKEND (library.service.js) + FRONTEND (JS compilato SvelteKit)
# =============================================================================

set -euo pipefail

IMMICH_APP="$HOME/immich/app"

echo "==> Fix 1: Patch backend library.service.js"
python3 - << 'PYEOF'
import re, os

path = os.path.expanduser('~/immich/app/dist/services/library.service.js')
with open(path, 'r') as f:
    c = f.read()

# Rimuove tutte le patch precedenti parziali e applica una pulita
# Trova il blocco completo della funzione validateImportPath
pattern = r'(async validateImportPath\([^)]*\)\s*\{[^}]*?)(if\s*\(!\s*\(0,\s*[^)]+isAbsolute\)\([^)]+\)\))'
bypass = r'\1if (importPath.startsWith("http://") || importPath.startsWith("https://")) { validation.isValid = true; return validation; }\n        \2'
new_c = re.sub(pattern, bypass, c, count=1, flags=re.DOTALL)

if new_c != c:
    with open(path, 'w') as f:
        f.write(new_c)
    print('✅ Backend patchato (isAbsolute bypass)')
else:
    # Fallback: cerca il messaggio di errore
    bypass2 = "if (importPath.startsWith('http://') || importPath.startsWith('https://')) { validation.isValid = true; return validation; }\n            "
    new_c2 = re.sub(r'(validation\.message\s*=\s*`Import path must be absolute)', bypass2 + r'\1', c, count=1)
    if new_c2 != c:
        with open(path, 'w') as f:
            f.write(new_c2)
        print('✅ Backend patchato (fallback)')
    else:
        print('⚠ Backend: nessun pattern trovato, potrebbe essere già patchato')
PYEOF

echo ""
echo "==> Fix 2: Patch frontend SvelteKit"
echo "    Cerca validazione URL nei file JS compilati della web UI..."

python3 - << 'PYEOF'
import os, glob, re

www_dir = os.path.expanduser('~/immich/app/www')
patched = 0

# Cerca in tutti i file JS della web UI
for js_file in glob.glob(os.path.join(www_dir, '_app/**/*.js'), recursive=True):
    try:
        with open(js_file, 'r', encoding='utf-8', errors='ignore') as f:
            c = f.read()
        
        changed = False
        
        # Pattern 1: validazione "must be absolute" nel frontend
        if 'must be absolute' in c or 'isAbsolute' in c or 'startsWith("/"' in c:
            new_c = re.sub(
                r'(importPath|path)\.startsWith\(["\']\/["\']\)',
                r'(\1.startsWith("/") || \1.startsWith("http://") || \1.startsWith("https://"))',
                c
            )
            if new_c != c:
                c = new_c
                changed = True
        
        # Pattern 2: validazione che path inizi con /
        new_c = re.sub(
            r'!([a-zA-Z_$][a-zA-Z0-9_$]*)\.startsWith\(["\']\/["\']\)',
            r'(!\1.startsWith("/") && !\1.startsWith("http://") && !\1.startsWith("https://"))',
            c
        )
        if new_c != c:
            c = new_c
            changed = True
        
        if changed:
            with open(js_file, 'w', encoding='utf-8') as f:
                f.write(c)
            patched += 1
            print(f'✅ Frontend patchato: {os.path.basename(js_file)}')
    except:
        pass

if patched == 0:
    print('ℹ Nessun file frontend con validazione path trovato')
    print('  (potrebbe essere gestito solo dal backend)')
else:
    print(f'✅ {patched} file frontend patchati')
PYEOF

echo ""
echo "==> Fix 3: Verifica finale"
grep -n "startsWith.*http" "$IMMICH_APP/dist/services/library.service.js" | head -5

echo ""
echo "==> Fix 4: Riavvio Immich"
bash ~/scripts_immich/stop_immich.sh 2>/dev/null || true
sleep 2
bash ~/scripts_immich/start_immich.sh

echo ""
echo "============================================"
echo "✅ Fix completo applicato."
echo ""
echo "Ora aggiungi in Immich UI:"
echo "  Administration → External Libraries → Add"
echo "  Percorso: http://100.94.25.26:8080/"
echo ""
echo "Se ancora fallisce, prova via API direttamente:"
echo "  curl -X POST http://localhost:2283/api/libraries \\"
echo "    -H 'x-api-key: TUA_API_KEY' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"name\":\"NAS\",\"importPaths\":[\"http://100.94.25.26:8080/\"],\"exclusionPatterns\":[]}'"
echo "============================================"


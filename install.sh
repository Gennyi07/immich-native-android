#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# install.sh — Immich native per Android/Termux
# Adattato da: https://github.com/arter97/immich-native
#
# Fix completi per Termux/Android (Bionic, no glibc, no FHS):
#   1.  Shebang corretto (no /usr/bin/env su Android)
#   2.  Fix shebang su pnpm/npm/node/node-gyp prima di usarli
#   3.  Fix shebang su TUTTI i .bin di node_modules dopo ogni install
#   4.  npm_config_script_shell=bash → sharp/bcrypt trovano npm/node
#   5.  npm_config_platform=linux → Sharp usa prebuilt linux-arm64
#   6.  SHARP_FORCE_GLOBAL_LIBVIPS=1 → linka libvips di Termux
#   7.  Sharp: prima tenta prebuilt linux-arm64, poi rebuild da sorgente
#   8.  bcrypt: rebuild da sorgente se prebuilt fallisce (Bionic vs glibc)
#   9.  No corepack, no auto-switch versione pnpm
#  10.  extism: non bloccante (|| true)
#  11.  TMP in $HOME/tmp (non /tmp che è read-only su Android)
#  12.  Nessun utente 'immich', nessun systemd, nessun sudo
# =============================================================================

set -xeuo pipefail

REV=v2.5.6
IMMICH_PATH="$HOME/immich"
APP="$IMMICH_PATH/app"

# =============================================================================
# Verifiche prerequisiti
# =============================================================================
for cmd in pnpm ffmpeg uv python3 node npm node-gyp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ '$cmd' non trovato. Esegui prima 02_install_deps_termux.sh"
        exit 1
    fi
done

# =============================================================================
# Variabili d'ambiente globali per tutta la build
# =============================================================================
export NODE_OPTIONS="--max-old-space-size=6144"
export PATH="$PREFIX/bin:$HOME/.local/bin:$PATH"
export ANDROID_API_LEVEL=35

# Cartelle necessarie per build native (node-gyp, extism, ecc.)
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.gyp"
export TMPDIR="$PREFIX/tmp"
mkdir -p "$TMPDIR"

# node-gyp config per Android
echo "{ 'variables': { 'android_ndk_path': '' } }" > "$HOME/.gyp/include.gypi"

# Header e librerie di Termux visibili al compilatore
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CPATH="$PREFIX/include/glib-2.0:$PREFIX/lib/glib-2.0/include:$PREFIX/include"
export LIBRARY_PATH="$PREFIX/lib"

# Bash come shell per install script (altrimenti sh non trova npm/node/python)
export npm_config_script_shell="$(which bash)"

# Fa credere a Sharp/node-gyp di essere su linux-arm64 (non android-arm64)
# I prebuilt di Sharp sono etichettati "linux", non "android"
export npm_config_platform="linux"
export npm_config_arch="arm64"
export npm_config_libc="glibc"

# Usa libvips di sistema (pkg install libvips) invece di quella bundled
export SHARP_FORCE_GLOBAL_LIBVIPS="1"
export SHARP_IGNORE_GLOBAL_LIBVIPS="0"

# Disabilita auto-switch versione pnpm
export COREPACK_ENABLE_AUTO_PIN=0
export PNPM_IGNORE_PACKAGEMANAGER=1

# Librerie matematiche per ML (OpenBLAS/FFTW installate da pkg)
export OPENBLAS_NUM_THREADS=2
export BLIS_NUM_THREADS=2

# =============================================================================
# Fix shebang binari Node installati globalmente
# =============================================================================
for bin in pnpm npm npx node node-gyp node-gyp-build; do
    bin_path="$(command -v "$bin" 2>/dev/null || true)"
    [ -n "$bin_path" ] && termux-fix-shebang "$bin_path" 2>/dev/null || true
done

# =============================================================================
# Pulizia e preparazione cartelle
# =============================================================================
rm -rf "$APP" "$APP/../i18n"
mkdir -p "$APP" "$IMMICH_PATH/upload" "$IMMICH_PATH/cache" "$IMMICH_PATH/home/.local/bin"
echo 'umask 077' > "$IMMICH_PATH/home/.bashrc"

# =============================================================================
# Clone repository Immich
# =============================================================================
# Usa $HOME/tmp — /tmp è read-only su Android (Scoped Storage)
mkdir -p "$HOME/tmp"
TMP="$HOME/tmp/immich-build-$(uuidgen 2>/dev/null || date +%s | md5sum | head -c 16)"

git clone https://github.com/immich-app/immich "$TMP" --depth=1 -b "$REV"
cd "$TMP"
git reset --hard "$REV"
rm -rf .git

# Patch percorsi: /usr/src → IMMICH_PATH
grep -Rl /usr/src | xargs -n1 sed -i -e "s@/usr/src@${IMMICH_PATH}@g"

# Patch percorsi: /build → APP
grep -RlE '"/build"|'"'"'/build'"'" | \
    xargs -n1 sed -i \
        -e "s@\"/build\"@\"${APP}\"@g" \
        -e "s@'/build'@'${APP}'@g"

# Rimuove "packageManager" — impedisce a pnpm di auto-aggiornarsi via corepack
find . -name "package.json" -not -path "*/node_modules/*" \
    | xargs -n1 sed -i '/"packageManager"/d'

# =============================================================================
# Patch WebDAV — aggiunge supporto URL http:// come External Library
# Permette di usare http://100.94.25.26:8080/ come percorso libreria in Immich
# =============================================================================
if [ -f "$HOME/scripts_immich/webdav_patch.sh" ]; then
    echo "==> Applicazione patch WebDAV..."
    bash "$HOME/scripts_immich/webdav_patch.sh" "$TMP"
else
    echo "⚠ webdav_patch.sh non trovato in ~/scripts_immich/, salto patch WebDAV"
fi

# =============================================================================
# extism/js-pdk — opzionale, non critico
# =============================================================================
(
    set +e
    curl -fsSO https://raw.githubusercontent.com/extism/js-pdk/main/install.sh || exit 0
    sed -i \
        -e 's@sudo@@g' \
        -e "s@/usr/local/binaryen@${HOME}/binaryen@g" \
        -e "s@/usr/local/bin@${HOME}/.local/bin@g" \
        install.sh
    termux-fix-shebang install.sh
    bash install.sh
    rm -f install.sh
) || echo "⚠ extism-js saltato — non critico per Immich"

# =============================================================================
# Helper: fix shebang su tutti i .bin di node_modules
# =============================================================================
fix_bin_shebangs() {
    local dir="${1:-node_modules/.bin}"
    find "$dir" -maxdepth 1 -type f 2>/dev/null | while read -r f; do
        head -c 20 "$f" 2>/dev/null | grep -q '^#!' \
            && termux-fix-shebang "$f" 2>/dev/null || true
    done
}

# =============================================================================
# Build immich-server
# =============================================================================
cd server
pnpm install --no-frozen-lockfile --force
fix_bin_shebangs "node_modules/.bin"
[ -d "../node_modules/.bin" ] && fix_bin_shebangs "../node_modules/.bin" || true
pnpm run build

# Post-build patch WebDAV sul .js compilato
if [ -f "$HOME/scripts_immich/webdav_postbuild.sh" ]; then
    bash "$HOME/scripts_immich/webdav_postbuild.sh"
fi

pnpm prune --prod --no-optional --config.ci=true
cd -

cd open-api/typescript-sdk
pnpm install --frozen-lockfile --force
pnpm run build
cd -

cd web
pnpm install --frozen-lockfile --force
fix_bin_shebangs "node_modules/.bin"
pnpm run build
cd -

cd plugins
pnpm install --frozen-lockfile --force
# Salta build:wasm (richiede extism-js che non funziona su Android)
# Esegui solo build:tsc
pnpm run build:tsc || echo "⚠ plugins build:tsc fallito, continuiamo"
cd -

# Copia file compilati
cp -aL server/node_modules server/dist server/bin "$APP/"
cp -a web/build "$APP/www"
cp -a server/resources server/package.json pnpm-lock.yaml "$APP/"
mkdir -p "$APP/corePlugin"
# Copia solo i file esistenti (plugin.wasm potrebbe mancare su Android)
[ -d "plugins/dist" ] && cp -a plugins/dist "$APP/corePlugin/" || mkdir -p "$APP/corePlugin/dist"
[ -f "plugins/manifest.json" ] && cp -a plugins/manifest.json "$APP/corePlugin/" || true
cp -a LICENSE "$APP/"
cp -a i18n "$APP/../"

cd "$APP"
pnpm store prune
cd -

# =============================================================================
# Sharp — linka libvips di Termux, con fallback rebuild
#
# Strategia:
# 1. Tenta prebuilt linux-arm64 (npm_config_platform=linux)
# 2. Se fallisce al runtime (android vs linux Node-API mismatch),
#    forza rebuild da sorgente con SHARP_FORCE_GLOBAL_LIBVIPS=1
# =============================================================================
cd "$APP"

VIPS_VERSION="$(pkg-config --modversion vips 2>/dev/null || true)"
echo "libvips Termux: ${VIPS_VERSION:-non trovata}"

# Rimuove sharp e reinstalla con rebuild forzato da sorgente
# Questo garantisce che i binding C++ siano compilati per Bionic (Android)
# e linkino libvips di Termux — nessun conflitto glibc/Bionic
pnpm remove sharp 2>/dev/null || true

SHARP_FORCE_GLOBAL_LIBVIPS=1 \
npm_config_build_from_source=true \
npm_config_platform=linux \
npm_config_arch=arm64 \
    pnpm add sharp --ignore-scripts=false --allow-build=sharp \
|| {
    echo "⚠ Build Sharp con libvips globale fallita, tentativo prebuilt..."
    npm_config_platform=linux \
    npm_config_arch=arm64 \
        pnpm install sharp
}

fix_bin_shebangs "node_modules/.bin"

# =============================================================================
# bcrypt — rebuild da sorgente per Bionic
# I prebuilt di bcrypt sono compilati per glibc, non funzionano su Android
# =============================================================================
cd "$APP"
if [ -d "node_modules/bcrypt" ]; then
    npm rebuild bcrypt --build-from-source 2>/dev/null \
        || echo "⚠ bcrypt rebuild fallito — potrebbe funzionare comunque"
fi
cd -

# =============================================================================
# Machine Learning (Python venv con uv da Termux)
# =============================================================================
mkdir -p "$APP/machine-learning"
python3 -m venv "$APP/machine-learning/venv"
(
    . "$APP/machine-learning/venv/bin/activate"

    # Forza Python 3.12 se versione superiore (uv sync richiede <= 3.12)
    # Python 3.13 va bene — non forziamo il downgrade a 3.12
    cd "$TMP/machine-learning"
    # Installa dipendenze ML con uv (cpu-only, no CUDA)

    # Patch pyproject.toml: rimuove dipendenze problematiche su Android
    # watchfiles: richiede Rust/maturin
    sed -i 's/uvicorn\[standard\]/uvicorn/g' pyproject.toml
    sed -i '/watchfiles/d' pyproject.toml
    # insightface: nessuna wheel manylinux, uv fallisce nella risoluzione multi-platform
    # Lo installiamo via pip separatamente e lo escludiamo dal pyproject.toml
    sed -i '/insightface/d' pyproject.toml

    # Rigenera lockfile dopo la patch
    uv lock --python-platform manylinux_2_28_aarch64 2>/dev/null || true

    # uv sync per tutto il resto
    uv sync --python-platform manylinux_2_28_aarch64 --no-dev --no-install-project --no-install-workspace \
        --extra cpu --no-cache --active --link-mode=copy

    # insightface: compila per Android con pip (dopo uv sync per non interferire)
    pip install insightface==0.7.3 --no-deps 2>/dev/null || pip install insightface --no-deps 2>/dev/null || true

)
cp -a "$TMP/machine-learning/immich_ml" "$APP/machine-learning/"

# =============================================================================
# GeoNames (reverse geocoding)
# =============================================================================
mkdir -p "$APP/geodata"
cd "$APP/geodata"
wget -q -O admin1CodesASCII.txt \
    https://download.geonames.org/export/dump/admin1CodesASCII.txt &
wget -q -O admin2Codes.txt \
    https://download.geonames.org/export/dump/admin2Codes.txt &
wget -q -O cities500.zip \
    https://download.geonames.org/export/dump/cities500.zip &
wget -q -O ne_10m_admin_0_countries.geojson \
    https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson &
wait
unzip cities500.zip
date --iso-8601=seconds | tr -d "\n" > geodata-date.txt
rm cities500.zip
cd -

# =============================================================================
# Link upload directory
# =============================================================================
ln -sf "$IMMICH_PATH/upload" "$APP/upload"
ln -sf "$IMMICH_PATH/upload" "$APP/machine-learning/upload"

# =============================================================================
# Script di avvio server
# =============================================================================
cat > "$APP/start.sh" <<STARTEOF
#!/data/data/com.termux/files/usr/bin/bash
export PATH=$PREFIX/bin:$HOME/.local/bin:\$PATH
export npm_config_platform=linux
export SHARP_FORCE_GLOBAL_LIBVIPS=1

set -a
. $IMMICH_PATH/env
set +a

cd $APP
exec node $APP/dist/main "\$@"
STARTEOF
chmod 700 "$APP/start.sh"

# =============================================================================
# Script di avvio machine-learning
# =============================================================================
cat > "$APP/machine-learning/start.sh" <<MLEOF
#!/data/data/com.termux/files/usr/bin/bash
export PATH=$PREFIX/bin:$HOME/.local/bin:\$PATH

set -a
. $IMMICH_PATH/env
set +a

cd $APP/machine-learning
. venv/bin/activate

: "\${MACHINE_LEARNING_HOST:=127.0.0.1}"
: "\${MACHINE_LEARNING_PORT:=3003}"
: "\${MACHINE_LEARNING_WORKERS:=1}"
: "\${MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S:=2}"
: "\${MACHINE_LEARNING_WORKER_TIMEOUT:=300}"
: "\${MACHINE_LEARNING_CACHE_FOLDER:=$IMMICH_PATH/cache}"
: "\${TRANSFORMERS_CACHE:=$IMMICH_PATH/cache}"

exec gunicorn immich_ml.main:app \\
    -k immich_ml.config.CustomUvicornWorker \\
    -c immich_ml/gunicorn_conf.py \\
    -b "\${MACHINE_LEARNING_HOST}":"\${MACHINE_LEARNING_PORT}" \\
    -w "\${MACHINE_LEARNING_WORKERS}" \\
    -t "\${MACHINE_LEARNING_WORKER_TIMEOUT}" \\
    --log-config-json log_conf.json \\
    --keep-alive "\${MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S}" \\
    --graceful-timeout 10
MLEOF
chmod 700 "$APP/machine-learning/start.sh"

# =============================================================================
# Pulizia
# =============================================================================
rm -rf \
    "$TMP" \
    "$IMMICH_PATH/home/.wget-hsts" \
    "$IMMICH_PATH/home/.pnpm" \
    "$IMMICH_PATH/home/.local/share/pnpm" \
    "$IMMICH_PATH/home/.cache"

echo ""
echo "============================================"
echo "✅ Immich installato in $IMMICH_PATH"
echo "Passo successivo: ./start_immich.sh"
echo "============================================"


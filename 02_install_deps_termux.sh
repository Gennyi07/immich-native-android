#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 02_install_deps_termux.sh
# Esegui in TERMUX (non in proot)
# Installa tutte le dipendenze native necessarie a Immich
# =============================================================================

set -euo pipefail

echo "==> [1/7] Aggiornamento pacchetti Termux..."
pkg update -y

echo "==> [2/7] Dipendenze base..."
pkg install -y \
    git \
    curl \
    wget \
    unzip \
    jq \
    uuid-utils \
    build-essential \
    pkg-config \
    autoconf \
    libtool

echo "==> [3/7] Node.js + pnpm..."
pkg install -y nodejs

echo "==> [4/7] Python 3 + uv..."
pkg install -y python

echo "==> [5/7] Librerie immagini (libvips, libraw)..."
pkg install -y \
    libvips \
    libraw \
    libjpeg-turbo \
    libwebp \
    libpng \
    libtiff \
    libheif \
    librsvg \
    giflib \
    libexif

echo "==> [6/7] Redis..."
pkg install -y redis

echo "==> [7/7] FFmpeg (build statica ARM64)..."
# Usa FFmpeg static build da johnvansickle.com (ARM64/aarch64)
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz"
FFMPEG_TMP="$HOME/ffmpeg_static.tar.xz"

echo "    Download FFmpeg static build (ARM64)..."
wget -q --show-progress -O "$FFMPEG_TMP" "$FFMPEG_URL"
tar -xf "$FFMPEG_TMP" -C "$HOME/"

# Trova la cartella estratta e sposta i binari
FFMPEG_DIR=$(find "$HOME" -maxdepth 1 -name "ffmpeg-*-arm64-static" -type d | head -1)
cp "$FFMPEG_DIR/ffmpeg" "$HOME/.local/bin/ffmpeg"
cp "$FFMPEG_DIR/ffprobe" "$HOME/.local/bin/ffprobe"
chmod +x "$HOME/.local/bin/ffmpeg" "$HOME/.local/bin/ffprobe"
rm -rf "$FFMPEG_TMP" "$FFMPEG_DIR"

# Assicura che ~/.local/bin sia nel PATH
if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo ""
echo "============================================"
echo "✅ Dipendenze Termux installate."
echo ""
echo "Verifica:"
echo "  node --version"
echo "  pnpm --version"
echo "  python3 --version"
echo "  ffmpeg -version"
echo "  redis-server --version"
echo "============================================"

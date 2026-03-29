#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 02_install_deps_termux.sh — Dipendenze Termux per Immich
# Fix rispetto alle versioni precedenti:
#   - Aggiunti fftw, libopenblas (ML Python needs math libs)
#   - Aggiunti make, clang (build toolchain per Sharp/bcrypt da sorgente)
#   - Aggiunti libvips headers (inclusi nel pacchetto libvips in Termux)
#   - pkg install uv (non pip install uv che fallisce su Android)
#   - FFmpeg da pkg (non build statica)
#   - Rimosso libgif → giflib
# =============================================================================

set -euo pipefail

echo "==> [1/8] Aggiornamento pacchetti Termux..."
pkg update -y

echo "==> [2/8] Dipendenze base + toolchain build..."
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
    libtool \
    clang \
    make \
    binutils

echo "==> [3/8] Node.js + pnpm + node-gyp..."
pkg install -y nodejs
# pnpm via npm --force (corepack non funziona su Termux)
npm install -g pnpm --force
npm install -g node-gyp --force
# Fix shebang (#!/usr/bin/env non esiste su Android)
termux-fix-shebang "$(which pnpm)" 2>/dev/null || true
termux-fix-shebang "$(which npm)" 2>/dev/null || true
termux-fix-shebang "$(which node-gyp)" 2>/dev/null || true
echo "    node: $(node --version), pnpm: $(pnpm --version)"

echo "==> [4/8] Python 3 + uv..."
pkg install -y python
pkg install -y uv
echo "    python: $(python3 --version), uv: $(uv --version)"

echo "==> [5/8] Librerie matematiche per ML (OpenBLAS, FFTW)..."
pkg install -y \
    fftw \
    openblas

echo "==> [6/8] Librerie immagini per Sharp (libvips, HEIF, RAW)..."
# In Termux i pacchetti includono già gli header (no -dev separato)
pkg install -y \
    libvips \
    libraw \
    libheif \
    libjpeg-turbo \
    libwebp \
    libpng \
    libtiff \
    librsvg \
    giflib \
    libexif \
    cgif

echo "==> [7/8] Redis + FFmpeg..."
pkg install -y redis
pkg install -y ffmpeg

echo "==> [8/8] Configurazione PATH..."
mkdir -p "$HOME/.local/bin"
if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PREFIX/bin:$PATH"' >> "$HOME/.bashrc"
fi
# Esporta ANDROID_API_LEVEL per eventuali build Rust
if ! grep -q 'ANDROID_API_LEVEL' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export ANDROID_API_LEVEL=35' >> "$HOME/.bashrc"
fi

echo ""
echo "============================================"
echo "✅ Dipendenze Termux installate."
echo ""
node --version
pnpm --version
python3 --version
uv --version
ffmpeg -version 2>&1 | head -1
redis-server --version
pkg-config --modversion vips 2>/dev/null && echo "libvips OK" || echo "⚠ libvips non trovata via pkg-config"
echo "============================================"


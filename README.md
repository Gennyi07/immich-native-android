# immich-native-android

> **Run Immich on Android — no Docker, no root, no cloud.**

[Immich](https://github.com/immich-app/immich) is a self-hosted photo/video backup platform designed to run on Linux servers via Docker. This project ports it to a stock Android phone using Termux, solving every compatibility layer from scratch.

**Tested on:** Samsung Galaxy S25 (Snapdragon 8 Elite, aarch64, Android 15)  
**Immich version:** v2.5.6  
**Base:** adapted from [arter97/immich-native](https://github.com/arter97/immich-native), then heavily reworked for Android/Bionic

---

## Why this is hard

Android is not Linux. It uses Bionic libc instead of glibc, has no FHS filesystem layout, no systemd, no root, no FUSE mounts, and kills background processes aggressively. Immich was never designed to run here. Every single layer of the stack required fixes.

---

## Architecture

```
proot Debian (container)
└── PostgreSQL 17 + VectorChord extension
        ↓ localhost:5432
Termux (native aarch64)
├── Redis
├── Node.js 20  →  Immich server      (port 2283)
└── Python + ONNX  →  Immich ML       (port 3003)
```

**Optional:** WebDAV external library support — index photos on a remote NAS without copying them locally.

---

## Problems solved

This is not a tutorial repackage. These are the actual blockers encountered and how they were resolved.

### 1. Node.js version incompatibility
The latest Node.js caused silent startup failures. Traced to native module ABI mismatches between Node versions and prebuilt binaries compiled against glibc. Solution: pinned to Node 20 LTS, which has stable arm64 prebuilts compatible with Bionic via the `npm_config_platform=linux` workaround.

### 2. Native dependencies — manual recompilation
Most npm packages ship Linux/glibc prebuilts that silently fail or crash on Android/Bionic. Sharp (image processing) and bcrypt required full recompilation from source against Termux's libvips. Python ML dependencies (ONNX Runtime, InsightFace) had no Android wheels — compiled inside a Python venv using Rust-based build tools (`maturin`, `uv`). `watchfiles` was removed entirely (requires Rust/maturin, incompatible with Android's Bionic).

Key environment flags that made this work:
```bash
npm_config_platform=linux          # tricks Sharp into using linux-arm64 prebuilts
npm_config_libc=glibc              # same
SHARP_FORCE_GLOBAL_LIBVIPS=1       # links Termux's libvips instead of bundled
NODE_OPTIONS=--max-old-space-size=6144  # prevents OOM during build
TMPDIR=$HOME/tmp                   # /tmp is read-only on Android
```

### 3. PostgreSQL — proot Debian isolation
PostgreSQL cannot run natively in Termux (missing kernel features, libc incompatibilities). Solution: run it inside a proot Debian container. However, PostgreSQL crashes when started as root inside proot. Fixed by creating a dedicated `postgres` user inside the container and launching the service under that user via a scripted proot session.

### 4. WebDAV external library — Immich source patch
The goal: index photos stored on a remote NAS without copying them to the phone.

The problem: Android has no FUSE support without root, so the NAS cannot be mounted as a filesystem path. The only working option (RSAF) exposes files through Android's Storage Access Framework — inaccessible from Termux.

The solution: patch Immich's source code directly. `StorageRepository` and `LibraryService` validate external library paths using `path.isAbsolute()`, which rejects HTTP URLs. Added bypass logic for paths starting with `http://` before the TypeScript build, and a post-build patch on the compiled JS as fallback.

```typescript
// patch applied to LibraryService before build
if (importPath.startsWith('http://')) {
  // WebDAV path — skip isAbsolute() check
}
```

The NAS serves files over WebDAV via `rclone serve webdav` over Tailscale.

### 5. ML library recompilation
Immich's machine learning service (face recognition, CLIP embeddings, smart search) depends on native Python extensions. None had Android/aarch64 wheels. Each was compiled manually inside the venv using:
```bash
uv sync --python-platform manylinux_2_28_aarch64
```
InsightFace was removed from `pyproject.toml` and installed separately via pip after the main sync, due to build order conflicts.

### 6. Phantom Process Killer
Android 12+ kills background processes not started by the foreground app. Immich (PostgreSQL + Redis + Node + Python) runs as four separate processes. Fixed via Shizuku + ADB:
```bash
adb shell device_config set_sync_disabled_for_tests persistent
adb shell device_config put activity_manager max_phantom_processes 2147483647
```

---

## Installation

> ⚠️ This setup is complex and environment-sensitive. It requires Termux, proot-distro with Debian, and approximately 30–90 minutes of build time. Keep the phone charging and on WiFi.

### Prerequisites
- Android 12+ (tested on Android 15)
- [Termux](https://f-droid.org/packages/com.termux/) from F-Droid
- proot-distro with Debian installed
- Shizuku (recommended — prevents process killing)
- ~8GB free storage

### Steps

```bash
# 1. PostgreSQL inside proot Debian
cp 01_setup_postgres.sh /sdcard/
proot-distro login debian -- bash /sdcard/01_setup_postgres.sh
# Save the generated DB_PASSWORD

# 2. Termux native dependencies
chmod +x installdepstermux.sh && ./installdepstermux.sh

# 3. Configure environment
mkdir -p ~/immich && cp env ~/immich/env
nano ~/immich/env  # set DB_PASSWORD from step 1

# 4. Build Immich (~30–90 min)
chmod +x install.sh webdav_patch.sh
./install.sh 2>&1 | tee ~/install_log.txt

# 5. Start
chmod +x start_immich.sh && ./start_immich.sh
```

Open: **http://localhost:2283**

---

## WebDAV external library (optional)

Allows Immich to index photos on a remote NAS without local copies — no FUSE, no root.

**On the NAS (Termux):**
```bash
rclone serve webdav /sdcard/YourFolder --addr 0.0.0.0:8080 --read-only &
```

**In Immich UI:**  
`Administration → External Libraries → Add → http://NAS_IP:8080/`

The WebDAV patch is applied automatically during `install.sh`.

---

## Known limitations

- ML (face recognition, smart search) stability depends on native module compatibility — works on this setup, may vary
- Immich updates require re-running `install.sh`
- No GPU/NPU acceleration — all ML runs on CPU
- Shizuku must be re-enabled after each reboot
- WebDAV library scanning can be slow on first run (thumbnail generation for large libraries)

---

## Files

| File | Purpose |
|------|---------|
| `01_setup_postgres.sh` | PostgreSQL 17 + VectorChord inside proot Debian |
| `installdepstermux.sh` | All native Termux dependencies |
| `install.sh` | Full Immich build pipeline with all Android fixes |
| `webdav_patch.sh` | Patches Immich TypeScript source for WebDAV support |
| `webdav_postbuild.sh` | Post-build JS patch (fallback) |
| `start_immich.sh` / `stop_immich.sh` | Service management |
| `env` | Environment configuration template |

---

## Credits

- [arter97/immich-native](https://github.com/arter97/immich-native) — original non-Docker install approach
- [immich-app/immich](https://github.com/immich-app/immich) — the application

---

## License

MIT

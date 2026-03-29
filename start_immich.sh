#!/bin/bash
# =============================================================================
# start_immich.sh
# Esegui in TERMUX per avviare tutti i servizi Immich
# =============================================================================

set -euo pipefail

IMMICH_PATH="$HOME/immich"
APP="$IMMICH_PATH/app"
LOG_DIR="$IMMICH_PATH/logs"
PID_DIR="$IMMICH_PATH/pids"

# --- Percorso della galleria NAS (RSAF/SAF bridge) ---
# Dopo aver configurato RSAF, inserisci qui il percorso POSIX
# che Termux vede per la cartella remota del NAS.
# Esempio: /storage/emulated/0/RSAF/BackupS25/gallery
# o il percorso restituito da termux-saf-managedir
NAS_GALLERY_PATH="${IMMICH_NAS_PATH:-/storage/emulated/0/RSAF/BackupS25/gallery}"

mkdir -p "$LOG_DIR" "$PID_DIR"

# --- Versione PostgreSQL in proot ---
PG_VERSION=$(proot-distro login debian -- \
    pg_lsclusters -h 2>/dev/null | awk '{print $1}' | head -1 || echo "17")

# Fix ownership PostgreSQL data directory (si resetta ad ogni reboot)
echo "[0/4] Fix ownership PostgreSQL..."
proot-distro login debian --user root -- bash -c \
  "chown -R postgres:postgres /var/lib/postgresql/${PG_VERSION}/main" && \
  echo "    ✅ Ownership OK" || echo "    ⚠️ chown fallito, continuo..."

# =============================================================================
echo "[1/4] Avvio PostgreSQL in proot Debian..."
# =============================================================================
proot-distro login debian \
    --bind "$NAS_GALLERY_PATH:/mnt/nas_gallery" \
    -- bash -c "
        su -s /bin/bash postgres -c \
        '/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl \
         -D /var/lib/postgresql/${PG_VERSION}/main \
         -l /var/log/postgresql/immich.log \
         start' 2>/dev/null || true
        tail -f /dev/null
    " >> "$LOG_DIR/proot.log" 2>&1 &

echo $! > "$PID_DIR/proot.pid"

echo "    Attendo PostgreSQL..."
sleep 4

# Verifica connessione
if ! proot-distro login debian -- su -s /bin/bash postgres -c \
    "psql -c 'SELECT 1;' immich" > /dev/null 2>&1; then
    echo "❌ PostgreSQL non raggiungibile. Controlla $LOG_DIR/proot.log"
    exit 1
fi
echo "    ✅ PostgreSQL attivo"

# =============================================================================
echo "[2/4] Avvio Redis..."
# =============================================================================
redis-server --daemonize yes \
    --logfile "$LOG_DIR/redis.log" \
    --pidfile "$PID_DIR/redis.pid"
sleep 1
echo "    ✅ Redis attivo"

# =============================================================================
echo "[3/4] Avvio Immich Machine Learning..."
# =============================================================================
nohup "$APP/machine-learning/start.sh" \
    >> "$LOG_DIR/machine-learning.log" 2>&1 &
echo $! > "$PID_DIR/machine-learning.pid"
sleep 2
echo "    ✅ Machine Learning avviato (PID $(cat $PID_DIR/machine-learning.pid))"

# =============================================================================
echo "[4/4] Avvio Immich Server..."
# =============================================================================
nohup "$APP/start.sh" \
    >> "$LOG_DIR/immich-server.log" 2>&1 &
echo $! > "$PID_DIR/immich-server.pid"
sleep 2
echo "    ✅ Immich Server avviato (PID $(cat $PID_DIR/immich-server.pid))"

# =============================================================================
echo ""
echo "============================================"
echo "🚀 Immich avviato!"
echo ""
echo "  Web UI:  http://$(hostname -I | awk '{print $1}'):2283"
echo "  Log:     $LOG_DIR/"
echo ""
echo "⚠️  Ricorda:"
echo "  - Configura External Library in Admin UI"
echo "    puntando a /mnt/nas_gallery"
echo "  - Per fermare: ./stop_immich.sh"
echo "============================================"

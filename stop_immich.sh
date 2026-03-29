#!/bin/bash
# =============================================================================
# stop_immich.sh
# Ferma tutti i servizi Immich
# =============================================================================

IMMICH_PATH="$HOME/immich"
PID_DIR="$IMMICH_PATH/pids"
PG_VERSION=$(proot-distro login debian -- \
    pg_lsclusters -h 2>/dev/null | awk '{print $1}' | head -1 || echo "17")

echo "[1/4] Stop Immich Server..."
if [ -f "$PID_DIR/immich-server.pid" ]; then
    kill "$(cat $PID_DIR/immich-server.pid)" 2>/dev/null || true
    rm -f "$PID_DIR/immich-server.pid"
fi
echo "    ✅"

echo "[2/4] Stop Machine Learning..."
if [ -f "$PID_DIR/machine-learning.pid" ]; then
    kill "$(cat $PID_DIR/machine-learning.pid)" 2>/dev/null || true
    rm -f "$PID_DIR/machine-learning.pid"
fi
echo "    ✅"

echo "[3/4] Stop Redis..."
redis-cli shutdown 2>/dev/null || true
rm -f "$PID_DIR/redis.pid"
echo "    ✅"

echo "[4/4] Stop PostgreSQL in proot..."
proot-distro login debian -- \
    su -s /bin/bash postgres -c \
    "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl \
     -D /var/lib/postgresql/${PG_VERSION}/main stop" 2>/dev/null || true

if [ -f "$PID_DIR/proot.pid" ]; then
    kill "$(cat $PID_DIR/proot.pid)" 2>/dev/null || true
    rm -f "$PID_DIR/proot.pid"
fi
echo "    ✅"

echo ""
echo "✅ Tutti i servizi fermati."

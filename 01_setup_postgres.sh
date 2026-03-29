#!/bin/bash
# =============================================================================
# 01_setup_postgres.sh
# Esegui DENTRO proot Debian: proot-distro login debian
# Installa PostgreSQL 17 + VectorChord e crea il database Immich
# =============================================================================

set -euo pipefail

echo "==> [1/5] Aggiornamento pacchetti..."
apt-get update

echo "==> [2/5] Installazione PostgreSQL 17..."
apt-get install -y postgresql postgresql-contrib curl gnupg

# Determina la versione PostgreSQL installata
PG_VERSION=$(pg_lsclusters -h | awk '{print $1}' | head -1)
echo "    PostgreSQL versione rilevata: $PG_VERSION"

echo "==> [3/5] Installazione VectorChord..."
# Aggiunge il repo VectorChord
curl -fsSL https://packages.tensorchord.ai/key.gpg \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/vectorchord.gpg

echo "deb [signed-by=/etc/apt/trusted.gpg.d/vectorchord.gpg] \
https://packages.tensorchord.ai/apt/ bookworm main" \
    > /etc/apt/sources.list.d/vectorchord.list

apt-get update
apt-get install -y "postgresql-${PG_VERSION}-vchord" || {
    echo "    ⚠ VectorChord non trovato per PG${PG_VERSION}, provo pgvector come fallback..."
    apt-get install -y "postgresql-${PG_VERSION}-pgvector"
    USE_PGVECTOR=1
}

echo "==> [4/5] Avvio PostgreSQL..."
# In proot non c'è systemd, avvia direttamente
su -s /bin/bash postgres -c \
    "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl \
     -D /var/lib/postgresql/${PG_VERSION}/main \
     -l /var/log/postgresql/proot_startup.log \
     start" || true

sleep 3

echo "==> [5/5] Creazione database e utente Immich..."

# Genera password casuale
DB_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)

su -s /bin/bash postgres -c "psql" <<SQL
CREATE DATABASE immich;
CREATE USER immich WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE immich TO immich;
ALTER DATABASE immich OWNER TO immich;
ALTER USER immich WITH SUPERUSER;
SQL

# Attiva estensione vettoriale nel database immich
if [ "${USE_PGVECTOR:-0}" = "1" ]; then
    su -s /bin/bash postgres -c "psql -d immich" <<SQL
CREATE EXTENSION IF NOT EXISTS vector CASCADE;
SQL
    echo "    Usato pgvector come estensione vettoriale"
else
    su -s /bin/bash postgres -c "psql -d immich" <<SQL
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
SQL
    echo "    Usato VectorChord come estensione vettoriale"
fi

echo ""
echo "============================================"
echo "✅ PostgreSQL pronto."
echo ""
echo "  DB_PASSWORD=${DB_PASSWORD}"
echo ""
echo "⚠️  COPIA QUESTA PASSWORD e inseriscila nel"
echo "   file ~/immich/env prima di proseguire!"
echo "============================================"

# Salva la password in un file temporaneo leggibile da Termux
echo "$DB_PASSWORD" > /sdcard/immich_db_password.tmp
echo "    Password salvata anche in /sdcard/immich_db_password.tmp"

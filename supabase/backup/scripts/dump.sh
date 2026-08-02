#!/usr/bin/env bash
# Refresh this backup from a live database.
#
#   ./supabase/backup/scripts/dump.sh "postgresql://postgres:PASSWORD@HOST:5432/postgres"
#
# Writes:
#   snapshots/<timestamp>-schema.sql   plain-text schema of public + private
#   snapshots/<timestamp>-data.sql     all rows in public
#
# The checked-in schema/ and data/ files are the curated, reviewed version of
# this dump — regenerate those by hand from a snapshot when the schema changes.
# Supabase-managed schemas (auth, storage, realtime, vault) are excluded: the
# platform recreates them on every new project.

set -euo pipefail

DB_URL="${1:-${DATABASE_URL:-}}"

if [[ -z "$DB_URL" ]]; then
    echo "usage: $0 <postgres-connection-url>" >&2
    exit 1
fi

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$BACKUP_DIR/snapshots"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$OUT_DIR"

pg_dump "$DB_URL" \
    --schema-only \
    --no-owner --no-privileges --no-comments=false \
    --schema=public --schema=private \
    --file "$OUT_DIR/$STAMP-schema.sql"

pg_dump "$DB_URL" \
    --data-only \
    --no-owner --no-privileges \
    --schema=public \
    --file "$OUT_DIR/$STAMP-data.sql"

echo "wrote $OUT_DIR/$STAMP-schema.sql"
echo "wrote $OUT_DIR/$STAMP-data.sql"

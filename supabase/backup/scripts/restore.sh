#!/usr/bin/env bash
# Recreate the EBTL database from the committed backup.
#
#   ./supabase/backup/scripts/restore.sh "postgresql://postgres:PASSWORD@HOST:5432/postgres"
#
# Optional second argument selects how much data to load:
#   schema      schema only, no rows
#   reference   schema + catalog/config data (default)
#   full        schema + all data, including customers, orders and credentials
#
# The target database must be empty in the public schema. Supabase-managed
# schemas (auth, storage, realtime) are provisioned by the platform and are not
# part of this backup.

set -euo pipefail

DB_URL="${1:-${DATABASE_URL:-}}"
MODE="${2:-reference}"

if [[ -z "$DB_URL" ]]; then
    echo "usage: $0 <postgres-connection-url> [schema|reference|full]" >&2
    exit 1
fi

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
    echo "==> $(basename "$1")"
    psql "$DB_URL" --set ON_ERROR_STOP=on --quiet --file "$1"
}

for f in "$BACKUP_DIR"/schema/*.sql; do
    run "$f"
done

case "$MODE" in
    schema)
        ;;
    reference)
        run "$BACKUP_DIR/data/01_reference.sql"
        ;;
    full)
        run "$BACKUP_DIR/data/01_reference.sql"
        run "$BACKUP_DIR/data/02_operational.sql"
        ;;
    *)
        echo "unknown mode: $MODE (expected schema, reference or full)" >&2
        exit 1
        ;;
esac

echo "==> done ($MODE)"

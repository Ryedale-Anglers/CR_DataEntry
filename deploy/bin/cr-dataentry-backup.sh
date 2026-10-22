#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/cr-dataentry/backups}"
RETENTION_DAYS=180
DATE=$(date +%Y%m%d_%H%M%S)

# DB_URL (session pooler, port 5432) comes from ~/.config/cr-dataentry/backup.env

mkdir -p "$BACKUP_DIR"

pg_dump "$DB_URL" \
  --schema=public \
  --schema=private \
  -Fc \
  -f "$BACKUP_DIR/cr_dataentry_${DATE}.dump"

# Rotate: delete dumps older than RETENTION_DAYS
find "$BACKUP_DIR" -name "cr_dataentry_*.dump" -mtime +$RETENTION_DAYS -delete

#!/usr/bin/env bash
set -euo pipefail

PD="$HOME/.local/bin/proton-drive"
SRC="${BACKUP_DIR:-$HOME/.local/share/cr-dataentry/backups}"
DEST=/my-files/Backups/cr-dataentry
KEEP_DAYS=213
STATE="$HOME/.local/state/cr-dataentry-offsite/uploaded.tsv"

mkdir -p "$(dirname "$STATE")"
touch "$STATE"
now=$(date +%s)
shopt -s nullglob

# 1. Upload dumps not yet uploaded
for f in "$SRC"/*; do
  [[ -f $f ]] || continue
  name=$(basename "$f")
  cut -f1 "$STATE" | grep -qxF "$name" && continue            # already uploaded
  (( now - $(stat -c %Y "$f") < 600 )) && continue            # still being written
  echo "Uploading $name"
  "$PD" filesystem upload -t --file-conflict-strategy create-new-revision "$f" "$DEST"
  printf '%s\t%s\n' "$name" "$now" >> "$STATE"
done

# 2. Trash remote copies older than KEEP_DAYS
cutoff=$(( now - KEEP_DAYS * 86400 ))
tmp=$(mktemp)
while IFS=$'\t' read -r name uploaded; do
  if (( uploaded < cutoff )); then
    echo "Trashing $name (older than $KEEP_DAYS days)"
    "$PD" filesystem trash "$DEST/$name" && continue          # forget it once trashed
  fi
  printf '%s\t%s\n' "$name" "$uploaded" >> "$tmp"             # otherwise keep tracking it
done < "$STATE"
mv "$tmp" "$STATE"
rclone rc --url http://127.0.0.1:5572 vfs/forget dir=Backups/cr-dataentry >/dev/null 2>&1 || true


# 4. Fail if there's been no new dump in the last 26 hours
if [[ -z $(find "$SRC" -maxdepth 1 -name 'cr_dataentry_*.dump' -mmin -1560 -print -quit) ]]; then
  echo "ERROR: no dump created in the last 26 hours" >&2
  exit 1
fi

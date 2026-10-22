#!/usr/bin/env bash
# Installs the CR_DataEntry scheduled jobs as systemd *user* units (no sudo needed).
#   13:00  cr-dataentry-etl      reservations ETL (run_etl_cron.sh in this repo)
#   15:00  cr-dataentry-backup   pg_dump to ~/.local/share/cr-dataentry/backups
#   15:30  cr-dataentry-offsite  upload new dumps to Proton Drive
# Expects the repo at ~/github/CR_DataEntry (the ETL unit points there).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
ENV_FILE="$HOME/.config/cr-dataentry/backup.env"

mkdir -p "$HOME/.local/bin" "$UNIT_DIR" "$(dirname "$ENV_FILE")"
install -m 0755 "$HERE"/bin/cr-dataentry-*.sh "$HOME/.local/bin/"
install -m 0644 "$HERE"/systemd/cr-dataentry-* "$UNIT_DIR/"

if [[ ! -f $ENV_FILE ]]; then
    install -m 0600 "$HERE/backup.env.example" "$ENV_FILE"
    echo "Created $ENV_FILE from the example: put the real DB_URL in it."
fi

systemctl --user daemon-reload
systemctl --user enable --now cr-dataentry-etl.timer cr-dataentry-backup.timer cr-dataentry-offsite.timer
loginctl enable-linger "$USER"   # timers run without a login session
systemctl --user list-timers 'cr-dataentry-*'

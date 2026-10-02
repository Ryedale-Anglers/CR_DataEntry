#!/bin/bash
# Runs the reservations-only ETL (catch returns now come from index_supabase.html).
# Scheduled via systemd timer: cr-dataentry-etl.timer (daily 13:00, Persistent=true)

set -euo pipefail

REPO_DIR="/home/brian/Documents/github/CR_DataEntry"
LOG_FILE="$REPO_DIR/etl_cron.log"
MAX_WAIT=90
WAITED=0

cd "$REPO_DIR"

{
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') starting scheduled ETL run ====="

    # On resume from suspend, network-online.target can still read as "active"
    # from before sleep even though wifi hasn't reassociated yet, so the
    # systemd dependency alone doesn't guarantee connectivity here. Poll
    # actively instead of trusting target state.
    while ! curl -s --max-time 3 https://supabase.com >/dev/null 2>&1; do
        if [ "$WAITED" -ge "$MAX_WAIT" ]; then
            echo "Network still unreachable after ${MAX_WAIT}s, attempting run anyway..."
            break
        fi
        echo "Network not ready, waiting... (${WAITED}s/${MAX_WAIT}s)"
        sleep 5
        WAITED=$((WAITED + 5))
    done

    "$REPO_DIR/venv/bin/python3" "$REPO_DIR/etl_reservations_only_to_supabase.py"
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') finished scheduled ETL run ====="
} >> "$LOG_FILE" 2>&1

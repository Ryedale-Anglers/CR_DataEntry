#!/bin/bash
# Generates the in-season catch-return compliance report PDF.
# Connects to CLOUD_DB_URL (production) directly - read-only queries only.

set -euo pipefail

REPO_DIR="/home/brian/Documents/github/CR_DataEntry"

cd "$REPO_DIR"
"$REPO_DIR/venv/bin/python3" "$REPO_DIR/generate_in_season_catchreturn_compliance_report.py"

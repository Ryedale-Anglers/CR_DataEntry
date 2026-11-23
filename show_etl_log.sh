#!/bin/bash
# Show the output of the nightly ETL run on GitHub Actions, without a browser.
#
#   ./show_etl_log.sh        output of the latest run
#   ./show_etl_log.sh 3      output of the 3rd most recent run
#   ./show_etl_log.sh -l     list the last 10 runs
#
# Needs the GitHub CLI (gh) logged in: gh auth login

set -euo pipefail

REPO="Ryedale-Anglers/CR_DataEntry"
WORKFLOW="schedule.yml"

if [[ "${1:-}" == "-l" ]]; then
    gh run list -R "$REPO" --workflow "$WORKFLOW" -L 10 \
        --json number,createdAt,event,status,conclusion \
        --jq '.[] | "\(.createdAt | fromdate | strflocaltime("%a %d %b %H:%M"))  \(.event | if . == "schedule" then "nightly" else "manual " end)  \(if .status == "completed" then .conclusion else .status end)"'
    exit 0
fi

N="${1:-1}"
if ! [[ "$N" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 [N | -l]" >&2
    exit 2
fi

RUN=$(gh run list -R "$REPO" --workflow "$WORKFLOW" -L "$N" \
    --json databaseId,createdAt,event,status,conclusion,url --jq ".[$((N - 1))]")
if [[ -z "$RUN" || "$RUN" == "null" ]]; then
    echo "No run found." >&2
    exit 1
fi

ID=$(jq -r .databaseId <<<"$RUN")
STATUS=$(jq -r .status <<<"$RUN")
RESULT=$(jq -r 'if .status == "completed" then .conclusion else .status end' <<<"$RUN")
WHEN=$(jq -r '.createdAt | fromdate | strflocaltime("%a %d %b %Y %H:%M")' <<<"$RUN")
KIND=$(jq -r 'if .event == "schedule" then "nightly" else "manual" end' <<<"$RUN")

echo "Run started $WHEN ($KIND) - result: $RESULT"
echo "$(jq -r .url <<<"$RUN")"
echo "-----------------------------------------------"

if [[ "$STATUS" != "completed" ]]; then
    echo "Still running - the output is available once it finishes."
    exit 0
fi

# Print only the ETL script's own output: skip the step's settings block
# (between ##[group] and ##[endgroup]) and stop at the clean-up steps.
gh run view -R "$REPO" "$ID" --log \
    | cut -f3- \
    | sed -e 's/^\xEF\xBB\xBF//' -e 's/^[0-9T:.-]*Z //' \
    | awk '
        /^##\[group\]Run python etl_/ { inside = 1; header = 1; next }
        inside && header && /^##\[endgroup\]/ { header = 0; next }
        inside && header { next }
        inside && (/^Post job cleanup/ || /^##\[group\]/) { inside = 0; done = 1 }
        done { next }
        inside { sub(/^##\[error\]/, "ERROR: "); print }
    '

[[ "$RESULT" == "success" ]] || exit 1

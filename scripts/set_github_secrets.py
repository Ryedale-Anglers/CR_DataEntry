"""Set the GitHub Actions secrets for Ryedale-Anglers/CR_DataEntry from .env.

Run from the repo folder:  venv/bin/python scripts/set_github_secrets.py

Values are read from .env and passed to `gh secret set` on stdin, so they are
never printed. The CLOUD_DB_URL secret takes the .env CLOUD_DB_URL_POOLER value:
GitHub's runners have no IPv6, so they need Supabase's pooler address.
"""
import subprocess
import sys
from pathlib import Path

from dotenv import dotenv_values

REPO = 'Ryedale-Anglers/CR_DataEntry'
ENV_FILE = Path(__file__).resolve().parent.parent / '.env'

SECRETS = {  # GitHub secret name: .env key
    'CLOUD_DB_URL': 'CLOUD_DB_URL_POOLER',
    # Only needed until cutover (the old ETL reads the Google Sheet); delete afterwards.
    'GOOGLE_SHEETS_ID': 'GOOGLE_SHEETS_ID',
    'IBOOKFISHING_REPORT_PAGE_URL': 'IBOOKFISHING_REPORT_PAGE_URL',
    'IBOOKFISHING_REPORT_SHSEC': 'IBOOKFISHING_REPORT_SHSEC',
    'IBOOKFISHING_REPORT_CALENDAR_ID': 'IBOOKFISHING_REPORT_CALENDAR_ID',
    'IBOOKFISHING_REPORT_S2': 'IBOOKFISHING_REPORT_S2',
}

env = dotenv_values(ENV_FILE)
missing = [key for key in SECRETS.values() if not env.get(key)]
if missing:
    sys.exit(f"Missing or empty in {ENV_FILE}: {', '.join(missing)} - nothing was set.")

for name, key in SECRETS.items():
    subprocess.run(['gh', 'secret', 'set', name, '-R', REPO], input=env[key], text=True, check=True)
    print('set', name)

print()
subprocess.run(['gh', 'secret', 'list', '-R', REPO], check=True)

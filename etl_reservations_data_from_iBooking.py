import requests
import os
import shutil
from datetime import datetime
from dotenv import load_dotenv

# --- Reservations Report page automation URL ---
#URL = "https://www.ibookfishing.com/show-admin-report.php"
URL = os.getenv('IBOOKFISHING_REPORT_PAGE_URL')
IBOOKFISHING_REPORT_SHSEC = os.getenv('IBOOKFISHING_REPORT_SHSEC')
IBOOKFISHING_REPORT_CALENDAR_ID = os.getenv('IBOOKFISHING_REPORT_CALENDAR_ID')
IBOOKFISHING_REPORT_S2 = os.getenv('IBOOKFISHING_REPORT_S2')

# The exact string you type into the browser
thisYear = datetime.now().year
DATE_STR = f"{thisYear}-04-01 to Today"

# Payload built from your screenshots
PAYLOAD = {
    'type': '1',
    'alt_type': '1',
    'download': 'csv',
    'alt_days': DATE_STR,
    'required_status': '4',
    'sort_field': 'name',
    'id': '759',
    'calendar': IBOOKFISHING_REPORT_CALENDAR_ID,
    'shsec': IBOOKFISHING_REPORT_SHSEC,
    's2': IBOOKFISHING_REPORT_S2
}
load_dotenv()

def run_reservations_download():
    # 1. Create a unique filename (e.g., report_2026-04-22.csv)
    datestamp = datetime.now().strftime("%Y%m%d")
    filename = f"./reservations_data/reservations_confirmed_{datestamp}.csv"
    
    print(f"Bypassing the UI to download report for: {DATE_STR}...")

    try:
        # 2. Execute the POST request
        response = requests.post(URL, data=PAYLOAD, timeout=30)
        response.raise_for_status()

        # 3. Save the file locally
        with open(filename, 'wb') as f:
            f.write(response.content)
        
        print(f"Successfully downloaded: {filename}")

        # 4. Trigger your existing DB script
        # Assuming your upload script has a function called 'upload'
        # import your_db_script
        # your_db_script.upload(filename)
        print("Ready for DB upload.")
        return filename

    except requests.exceptions.RequestException as e:
        print(f"Network error: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def process_reservations_file(downloaded_file):
    # The 'static' path your DB script looks for
    target_path = "./reservations_data/reservations_confirmed.csv"
    
    # Ensure the directory exists so the script doesn't crash
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    try:
        # Copy the dated file to the static filename (overwrites if exists)
        shutil.copy2(downloaded_file, target_path)
        print(f"File staged: {downloaded_file} -> {target_path}")
        
    except Exception as e:
        print(f"Error during file processing: {e}")

if __name__ == "__main__":
# 1. Capture the returned string into a variable called 'downloaded_path' 
# to the csv file you just downloaded
    downloaded_path = run_reservations_download()
    
    # 2. Check if the download actually worked before trying to process it
    if downloaded_path:
        process_reservations_file(downloaded_path)
    else:
        print("Download failed, skipping file processing.")
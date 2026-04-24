import os
from dotenv import load_dotenv
from supabase import create_client

# Explicitly load .env
load_dotenv()

url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")

print(f"Checking credentials...")
print(f"URL found: {'Yes' if url else 'No'}")
print(f"Key found: {'Yes' if key else 'No'}")

if url and key:
    try:
        supabase = create_client(url, key)
        print("🚀 Successfully connected to Supabase!")
    except Exception as e:
        print(f"❌ Connection error: {e}")
else:
    print("❌ Error: Could not find SUPABASE_URL or SUPABASE_KEY in .env")
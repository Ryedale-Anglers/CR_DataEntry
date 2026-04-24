#!/bin/bash

# Target the exact project directory
PROJECT_DIR="$HOME/Documents/GitHub/CR_DataEntry"

cd "$PROJECT_DIR" || exit

echo "---------------------------------"
echo " Supabase Manager: CR_DataEntry"
echo "---------------------------------"
echo "1) Start Supabase"
echo "2) Stop Supabase"
echo "3) Check Status"
echo "4) Exit"
echo "---------------------------------"
read -p "Select an option [1-4]: " choice

case $choice in
    1)
        supabase start
        ;;
    2)
        supabase stop
        ;;
    3)
        supabase status
        ;;
    4)
        exit 0
        ;;
    *)
        echo "Invalid option."
        ;;
esac

# Keep the terminal open so you can see the URLs/Keys
echo ""
read -p "Press Enter to close..."

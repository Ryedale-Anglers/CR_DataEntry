#!/bin/bash

# Ensure you are in a directory with a supabase folder
if [ ! -d "supabase" ]; then
    echo "⚠️  Warning: No 'supabase' directory found in the current folder."
    echo "Make sure you are running this from your project root."
fi

show_menu() {
    echo "---------------------------"
    echo "   Supabase Local Manager  "
    echo "---------------------------"
    echo "1) Start Supabase"
    echo "2) Stop Supabase"
    echo "3) Check Status"
    echo "4) Restart Instance"
    echo "5) Exit"
    echo "---------------------------"
    echo -n "Choose an option [1-5]: "
}

while true; do
    show_menu
    read choice
    case $choice in
        1)
            echo "🚀 Starting Supabase..."
            supabase start
            ;;
        2)
            echo "🛑 Stopping Supabase..."
            supabase stop
            ;;
        3)
            echo "📊 Checking Status..."
            supabase status
            ;;
        4)
            echo "🔄 Restarting..."
            supabase stop && supabase start
            ;;
        5)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please try again."
            ;;
    esac
    echo ""
done

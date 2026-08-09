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
    echo "5) Upgrade Supabase CLI (brew)"
    echo "6) Exit"
    echo "---------------------------"
    echo -n "Choose an option [1-6]: "
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
            status_output=$(supabase status 2>&1)
            if [ $? -eq 0 ]; then
                echo "$status_output"
            else
                echo "⏹️  Supabase is stopped."
            fi
            ;;
        4)
            echo "🔄 Restarting..."
            supabase stop && supabase start
            ;;
        5)
            echo "⬆️  Upgrading Supabase CLI..."
            echo "🛑 Stopping Supabase first (avoids running containers on a different CLI version than what's installed)..."
            supabase stop
            brew update && brew upgrade supabase
            echo "✅ Now running:"
            supabase --version
            echo "🚀 Starting Supabase back up..."
            supabase start
            ;;
        6)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please try again."
            ;;
    esac
    echo ""
done

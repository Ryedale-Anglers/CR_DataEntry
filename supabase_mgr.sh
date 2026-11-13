#!/bin/bash

# Docker network that the local Supabase containers join
SUPABASE_NETWORK="local-network"

# Where cr-dataentry-backup.sh (systemd user timer) writes the database dumps
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/cr-dataentry/backups}"

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
    echo "5) Upgrade Supabase CLI (dnf)"
    echo "6) List Available Backups"
    echo "7) Restore local DB from .dump file"
    echo "8) Show Supabase CLI Version"
    echo "9) Exit"
    echo "---------------------------"
    echo -n "Choose an option [1-9]: "
}

while true; do
    show_menu
    read choice
    case $choice in
        1)
            echo "🚀 Starting Supabase..."
            supabase start --network-id "$SUPABASE_NETWORK"
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
            supabase stop && supabase start --network-id "$SUPABASE_NETWORK"
            ;;
        5)
            # Installed from the GitHub release .rpm (not packaged in the
            # Fedora repos, and Homebrew isn't used on this machine).
            echo "⬆️  Checking for a newer Supabase CLI..."
            current=$(rpm -q --qf '%{VERSION}' supabase 2>/dev/null)
            latest=$(gh release view --repo supabase/cli --json tagName --jq .tagName | tr -d v)
            if [ -z "$latest" ]; then
                echo "❌ Couldn't get the latest version from GitHub (check: gh auth status)."
            elif [ "$current" = "$latest" ]; then
                echo "✅ Already on the latest version ($current)."
            else
                echo "Installed: ${current:-none}   Latest: $latest"
                if [ "${current%%.*}" != "${latest%%.*}" ]; then
                    echo "⚠️  This is a major version change - check the release notes first:"
                    echo "   https://github.com/supabase/cli/releases/tag/v$latest"
                fi
                read -r -p "Upgrade to $latest? [y/N] " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    echo "🛑 Stopping Supabase first (avoids running containers on a different CLI version than what's installed)..."
                    supabase stop
                    if sudo dnf install -y "https://github.com/supabase/cli/releases/download/v$latest/supabase_${latest}_linux_amd64.rpm"; then
                        echo "✅ Now running:"
                        supabase --version
                    else
                        echo "❌ Upgrade failed - still on $current."
                    fi
                    echo "🚀 Starting Supabase back up..."
                    supabase start --network-id "$SUPABASE_NETWORK"
                else
                    echo "Upgrade skipped."
                fi
            fi
            ;;
        6)
            # Newest first and capped, so the list isn't scrolled off-screen
            # by the menu being redrawn underneath it.
            mapfile -t dumps < <(ls -t "$BACKUP_DIR"/cr_dataentry_*.dump 2>/dev/null)
            if [ ${#dumps[@]} -eq 0 ]; then
                echo "❌ No backup files found in $BACKUP_DIR"
            else
                echo "🗄️  Backups in $BACKUP_DIR"
                echo "   ${#dumps[@]} dump(s), $(du -sh "$BACKUP_DIR" | cut -f1) total. Newest 15:"
                ls -lht "${dumps[@]:0:15}" | awk '{print "   " $5 "\t" $6 " " $7 " " $8 "\t" $NF}' | sed "s|$BACKUP_DIR/||"
            fi
            read -r -p "Press Enter to return to the menu..."
            ;;
        7)
            echo "🔄 Restoring local DB from a .dump file..."
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            # Newest first; offer the 10 most recent, Enter = latest
            mapfile -t dumps < <(ls -t "$BACKUP_DIR"/cr_dataentry_*.dump 2>/dev/null | head -n 10)
            if [ ${#dumps[@]} -eq 0 ]; then
                echo "❌ No backup files found in $BACKUP_DIR"
            else
                echo "Which backup?"
                for i in "${!dumps[@]}"; do
                    label="$(basename "${dumps[$i]}")"
                    [ "$i" -eq 0 ] && label="$label (latest)"
                    echo "  $((i + 1))) $label"
                done
                read -r -p "Choose [1-${#dumps[@]}, Enter = latest]: " pick
                pick="${pick:-1}"
                if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#dumps[@]} ]; then
                    "$SCRIPT_DIR/sync_prod_to_local.sh" "${dumps[$((pick - 1))]}"
                else
                    echo "❌ Invalid choice. Nothing was run."
                fi
            fi
            ;;
        8)
            # Skip the CLI's own "new version available" notice; option 5 handles upgrades
            echo "ℹ️  Supabase CLI version: $(supabase --version 2>/dev/null | head -n 1)"
            ;;
        9)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please try again."
            ;;
    esac
    echo ""
done

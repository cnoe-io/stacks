#!/usr/bin/env bash
#
# Gitea Webhook Notification Wrapper
# Streams webhook logs from in-cluster receiver and sends desktop notifications
# with clickable links to Gitea commits
#
# Usage: gitea-webhook-notify
#

set -euo pipefail

GITEA_URL="${GITEA_URL:-https://gitea.cnoe.localtest.me:8443}"

# Check for notification support
HAS_NOTIFY=false
if command -v notify-send &>/dev/null; then
    HAS_NOTIFY=true
fi

# Ensure webhook receiver pod exists
ensure_receiver() {
    if ! kubectl get pod webhook-receiver -n gitea &>/dev/null; then
        echo "Deploying webhook receiver pod..."
        kubectl apply -f "${STACKS_DIR:-$PWD}/deployment/webhook-receiver.yaml"
        kubectl wait --for=condition=ready pod/webhook-receiver -n gitea --timeout=60s
    fi
}

# Send desktop notification with clickable action
send_notification() {
    local app="$1"
    local message="$2"
    local commit_url="$3"

    if $HAS_NOTIFY; then
        # notify-send with action to open URL in browser
        # The action callback opens the URL when clicked
        (
            action=$(notify-send \
                --app-name="Gitea" \
                --icon="git" \
                --urgency=low \
                --expire-time=8000 \
                --action="open=View Commit" \
                "📦 $app" \
                "$message" 2>/dev/null)

            if [[ "$action" == "open" ]]; then
                xdg-open "$commit_url" 2>/dev/null &
            fi
        ) &
    fi
}

# Parse log line and extract commit info
# Expected format from webhook-receiver:
#   [HH:MM:SS] app-name (branch)
#   sha1234 commit message
#   by author (+N, ~M files)
#   → https://gitea.../commit/sha
parse_and_notify() {
    local app=""
    local message=""
    local commit_url=""

    while IFS= read -r line; do
        # Print the line as-is
        echo "$line"

        # Strip ANSI codes for parsing
        local clean_line
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\007')

        # Match app header: [HH:MM:SS] app-name (branch)
        # Example: [15:52:05] backstage-namespace (main)
        if [[ "$clean_line" =~ ^\[([0-9]+:[0-9]+:[0-9]+)\][[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            app="${BASH_REMATCH[2]}"
            continue
        fi

        # Match URL line: → https://gitea.../commit/sha
        if [[ "$clean_line" == *"→ https://"* ]]; then
            commit_url=$(echo "$clean_line" | grep -oP 'https://[^\s]+' | head -1)

            # Send notification with the URL
            if [[ -n "$app" && -n "$commit_url" ]]; then
                # Extract short message from previous line context
                send_notification "$app" "New commit pushed" "$commit_url"
            fi
            # Reset for next commit
            commit_url=""
        fi
    done
}

main() {
    echo -e "\033[0;32m\033[1mGitea Webhook Notifications\033[0m"
    echo -e "\033[2mStreaming from in-cluster receiver...\033[0m"
    if $HAS_NOTIFY; then
        echo -e "\033[2mDesktop notifications: enabled\033[0m"
    else
        echo -e "\033[2mDesktop notifications: disabled (install notify-send)\033[0m"
    fi
    echo ""

    ensure_receiver

    # Stream logs and parse for notifications
    kubectl logs -f webhook-receiver -n gitea 2>/dev/null | parse_and_notify
}

main "$@"

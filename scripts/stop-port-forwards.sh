#!/bin/bash
# Stop all port forwards started by port-forward-all.sh

PIDS_FILE="/tmp/port-forwards.pids"

if [ ! -f "$PIDS_FILE" ]; then
    echo "❌ No port forwards found (file $PIDS_FILE does not exist)"
    exit 1
fi

echo "🛑 Stopping all port forwards..."
while read -r pid; do
    if kill "$pid" 2>/dev/null; then
        echo "   ✓ Stopped PID $pid"
    else
        echo "   ⚠ PID $pid already stopped"
    fi
done < "$PIDS_FILE"

rm "$PIDS_FILE"
echo "✅ All port forwards stopped"

#!/usr/bin/env bash
# start.sh — runs the server (foreground, with live console) and playit.gg
# in the background. Detects server type from $SERVER_DIR/.server-type.
# Ctrl+C cleans up playit and the server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/server"
PLAYIT_BIN="$HOME/playit/playit"
HEAP_SIZE="${HEAP_SIZE:-2G}"

# Aikar's flags — well-known good G1GC tuning for Minecraft servers.
JVM_OPTS="${JVM_OPTS:--XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1}"

if [ ! -d "$SERVER_DIR" ]; then
    echo "[start] Server dir not found: $SERVER_DIR. Run scripts/install.sh first." >&2
    exit 1
fi

cd "$SERVER_DIR"
LOG_FILE="$SERVER_DIR/server.log"

# Detect server type
SERVER_TYPE=""
[ -f "$SERVER_DIR/.server-type" ] && SERVER_TYPE=$(cat "$SERVER_DIR/.server-type" || true)

# ---- playit.gg tunnel ------------------------------------------------------
PLAYIT_PID=""
cleanup() {
    if [ -n "$PLAYIT_PID" ] && kill -0 "$PLAYIT_PID" 2>/dev/null; then
        kill -TERM "$PLAYIT_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [ -x "$PLAYIT_BIN" ]; then
    : > "$SERVER_DIR/playit.log"
    "$PLAYIT_BIN" > "$SERVER_DIR/playit.log" 2>&1 &
    PLAYIT_PID=$!
    sleep 3
    echo "================================================================"
    echo "  playit.gg tunnel"
    echo "================================================================"
    sed 's/^/  /' "$SERVER_DIR/playit.log" || true
    echo "================================================================"
    if grep -qi "claim" "$SERVER_DIR/playit.log" 2>/dev/null; then
        echo "  ACTION NEEDED: open the claim URL above in a browser."
    fi
    echo
else
    echo "[start] playit not installed at $PLAYIT_BIN — server will run,"
    echo "[start] but friends can't reach it. Re-run scripts/install.sh."
    echo
fi

# ---- Run server (foreground, with live console) ---------------------------
echo "[start] Server type: ${SERVER_TYPE:-unknown}"
echo "[start] Heap:        $HEAP_SIZE"
echo "[start] Log:         $LOG_FILE"
echo "[start] Type 'stop' to shut down gracefully, Ctrl+C to force-kill."
echo

case "$SERVER_TYPE" in
    forge)
        if [ -x "./run.sh" ]; then
            echo "[start] Using Forge run.sh"
            ./run.sh 2>&1 | tee -a "$LOG_FILE"
        else
            echo "[start] Type is 'forge' but no run.sh in $SERVER_DIR. Re-run install.sh." >&2
            exit 1
        fi
        ;;
    fabric)
        if [ -f "fabric-server-launch.jar" ]; then
            echo "[start] Using Fabric launcher"
            java -Xms"$HEAP_SIZE" -Xmx"$HEAP_SIZE" $JVM_OPTS \
                -jar fabric-server-launch.jar --nogui 2>&1 | tee -a "$LOG_FILE"
        else
            echo "[start] Type is 'fabric' but no fabric-server-launch.jar. Re-run install.sh." >&2
            exit 1
        fi
        ;;
    *)
        # paper, vanilla, purpur, folia: any *.jar that isn't an installer
        SERVER_JAR=$(ls -1 *.jar 2>/dev/null \
            | grep -viE "fabric-installer|forge-installer" \
            | head -n1 || true)
        if [ -z "$SERVER_JAR" ]; then
            echo "[start] No server jar in $SERVER_DIR. Run scripts/install.sh." >&2
            exit 1
        fi
        echo "[start] Using jar: $SERVER_JAR"
        java -Xms"$HEAP_SIZE" -Xmx"$HEAP_SIZE" $JVM_OPTS \
            -jar "$SERVER_JAR" --nogui 2>&1 | tee -a "$LOG_FILE"
        ;;
esac

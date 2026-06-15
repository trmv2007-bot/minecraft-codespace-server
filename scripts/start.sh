#!/usr/bin/env bash
# start.sh — launches the Paper server (foreground, with live console) and
# runs playit.gg in the background. Safe to Ctrl+C: it tears everything down.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/server"
PLAYIT_BIN="$HOME/playit/playit"
HEAP_SIZE="${HEAP_SIZE:-2G}"

# Aikar's flags — well-known good G1GC tuning for Minecraft servers.
JVM_OPTS="${JVM_OPTS:--XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1}"

SERVER_JAR=$(ls -1 "$SERVER_DIR"/paper-*.jar 2>/dev/null | head -n1 || true)
if [ -z "$SERVER_JAR" ]; then
    echo "[start] No paper-*.jar found in $SERVER_DIR." >&2
    echo "[start] Run scripts/install.sh first." >&2
    exit 1
fi

cd "$SERVER_DIR"
LOG_FILE="$SERVER_DIR/server.log"

PLAYIT_PID=""
cleanup() {
    if [ -n "$PLAYIT_PID" ] && kill -0 "$PLAYIT_PID" 2>/dev/null; then
        kill -TERM "$PLAYIT_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# ---- playit.gg tunnel ------------------------------------------------------
if [ -x "$PLAYIT_BIN" ]; then
    : > "$SERVER_DIR/playit.log"
    "$PLAYIT_BIN" > "$SERVER_DIR/playit.log" 2>&1 &
    PLAYIT_PID=$!
    # Give playit a moment to print its claim URL.
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
    echo "[start] playit binary not found at $PLAYIT_BIN — server will run,"
    echo "[start] but friends won't be able to reach it. Re-run scripts/install.sh."
    echo
fi

# ---- Minecraft server ------------------------------------------------------
echo "[start] Minecraft server starting"
echo "[start]   jar:  $SERVER_JAR"
echo "[start]   heap: $HEAP_SIZE"
echo "[start]   log:  $LOG_FILE"
echo "[start] Type 'stop' to shut down gracefully, Ctrl+C to force-kill."
echo

# Foreground pipeline: java writes to its log file via tee, so the user gets
# live output AND the log keeps a record for later debugging.
java -Xms"$HEAP_SIZE" -Xmx"$HEAP_SIZE" $JVM_OPTS -jar "$SERVER_JAR" --nogui \
    2>&1 | tee -a "$LOG_FILE"

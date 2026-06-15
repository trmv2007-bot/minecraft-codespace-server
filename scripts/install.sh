#!/usr/bin/env bash
# install.sh — sets up a Paper Minecraft server and the playit.gg tunnel
# inside a GitHub Codespace. Idempotent: safe to re-run.

set -euo pipefail

# ---- Configuration ---------------------------------------------------------
MC_VERSION="${MC_VERSION:-1.21.4}"            # Minecraft version
HEAP_SIZE="${HEAP_SIZE:-2G}"                  # Default JVM heap (override at start)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/server"
PLAYIT_DIR="$HOME/playit"
PLAYIT_BIN="$PLAYIT_DIR/playit"
# ---------------------------------------------------------------------------

# ---- Helpers ---------------------------------------------------------------
log()  { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
# ---------------------------------------------------------------------------

cat <<'EOF'

  __  __          _ _                      _
 |  \/  | ___  __| (_)___  ___  _ __      | |__  _   _
 | |\/| |/ _ \/ _` | / __|/ _ \| '_ \ ____| '_ \| | | |
 | |  | |  __/ (_| | \__ \ (_) | | | |____| |_) | |_| |
 |_|  |_|\___|\__,_|_|___/\___/|_| |_|    |_.__/ \__, |
                                                 |___/
  Codespace Minecraft server (Paper, online-mode=false)

EOF

need java
need curl
need python3

JAVA_VER=$(java -version 2>&1 | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
JAVA_MAJOR=$(printf '%s' "$JAVA_VER" | cut -d. -f1)
log "Java: $JAVA_VER"
if [ "${JAVA_MAJOR:-0}" -lt 17 ]; then
    err "Java 17+ required for Paper $MC_VERSION. Got $JAVA_VER."
    exit 1
fi

mkdir -p "$SERVER_DIR"

# ---- 1. Paper server jar ---------------------------------------------------
log "Looking up latest Paper build for Minecraft $MC_VERSION..."
BUILDS_JSON=$(curl -fsSL \
    "https://api.papermc.io/v2/projects/paper/versions/$MC_VERSION/builds") \
    || { err "Paper API lookup failed. Check MC_VERSION='$MC_VERSION'."; exit 1; }

LATEST_BUILD=$(printf '%s' "$BUILDS_JSON" | python3 -c '
import sys, json
data = json.load(sys.stdin)
builds = data.get("builds") or []
if not builds:
    sys.exit("no builds for that version")
print(builds[-1]["build"])
') || { err "No builds found for $MC_VERSION. Try MC_VERSION=1.20.4 or 1.21.4."; exit 1; }

JAR_NAME="paper-${MC_VERSION}-${LATEST_BUILD}.jar"
JAR_PATH="$SERVER_DIR/$JAR_NAME"
log "Latest build: $LATEST_BUILD"

if [ -f "$JAR_PATH" ] && [ -s "$JAR_PATH" ]; then
    log "Jar already present, skipping download."
else
    log "Downloading $JAR_NAME..."
    curl -fL --retry 3 --retry-delay 2 -o "$JAR_PATH" \
        "https://api.papermc.io/v2/projects/paper/versions/$MC_VERSION/builds/$LATEST_BUILD/downloads/$JAR_NAME"
    log "Saved $(du -h "$JAR_PATH" | cut -f1) to $JAR_PATH"
fi

# ---- 2. EULA ----------------------------------------------------------------
log "Accepting Mojang EULA"
cat > "$SERVER_DIR/eula.txt" <<EULA
eula=true
#Accepted by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
EULA

# ---- 3. server.properties --------------------------------------------------
# Online-mode is set to false so friends without paid Mojang accounts can
# join using any username. Keep the rest at sane defaults for a small group.
PROPS_FILE="$SERVER_DIR/server.properties"
if [ ! -f "$PROPS_FILE" ] || ! grep -q '^online-mode=' "$PROPS_FILE"; then
    log "Writing server.properties"
    cat > "$PROPS_FILE" <<PROPS
#Minecraft server properties — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
#Tweaked for a friend group on GitHub Codespace.
allow-flight=true
allow-nether=true
broadcast-console-to-ops=true
broadcast-rcon-to-ops=true
difficulty=normal
enable-command-block=false
enable-jmx-monitoring=false
enable-query=true
enable-rcon=false
enable-status=true
enforce-secure-profile=true
entity-broadcast-range-percentage=100
force-gamemode=false
function-permission-level=2
gamemode=survival
generate-structures=true
generator-settings={}
hardcore=false
hide-online-players=false
initial-disabled-packs=
initial-enabled-packs=vanilla
level-name=world
level-seed=
level-type=minecraft\\:normal
max-chained-neighbor-updates=1000000
max-players=20
max-tick-time=60000
max-world-size=29999984
motd=§bFriend Minecraft Server §f§l[Codespace]
network-compression-threshold=256
online-mode=false
op-permission-level=4
player-idle-timeout=0
prevent-proxy-connections=false
pvp=true
query.port=25565
rate-limit=0
rcon.password=
rcon.port=25575
require-resource-pack=false
resource-pack=
resource-pack-prompt=
resource-pack-sha1=
server-ip=
server-port=25565
simulation-distance=8
spawn-animals=true
spawn-monsters=true
spawn-npcs=true
spawn-protection=0
sync-chunk-writes=true
text-filtering-config=
use-native-transport=true
view-distance=10
white-list=false
PROPS
else
    log "server.properties already exists, leaving it alone."
    # Make sure online-mode is false even if user edited it
    if grep -q '^online-mode=true' "$PROPS_FILE"; then
        warn "online-mode=true in server.properties — switching to false for friend access."
        sed -i 's/^online-mode=true/online-mode=false/' "$PROPS_FILE"
    fi
fi

# ---- 4. Empty ops/usercache so the server doesn't choke on first start ----
[ -f "$SERVER_DIR/ops.json" ]    || printf '[]\n' > "$SERVER_DIR/ops.json"
[ -f "$SERVER_DIR/usercache.json" ] || printf '[]\n' > "$SERVER_DIR/usercache.json"
[ -f "$SERVER_DIR/banned-players.json" ] || printf '[]\n' > "$SERVER_DIR/banned-players.json"
[ -f "$SERVER_DIR/banned-ips.json" ]     || printf '[]\n' > "$SERVER_DIR/banned-ips.json"
[ -f "$SERVER_DIR/whitelist.json" ]      || printf '[]\n' > "$SERVER_DIR/whitelist.json"

# ---- 5. playit.gg tunnel ---------------------------------------------------
log "Installing playit.gg tunnel (free, made for game servers)..."
mkdir -p "$PLAYIT_DIR"
if [ -x "$PLAYIT_BIN" ]; then
    log "playit already installed."
else
    log "Downloading playit binary..."
    if ! curl -fL --retry 3 -o "$PLAYIT_BIN" \
            "https://github.com/playit-cloud/playit-minecraft/releases/latest/download/playit-linux-amd64"; then
        warn "playit download failed. The server will still start, but you will need a tunnel."
    else
        chmod +x "$PLAYIT_BIN"
    fi
fi

# ---- Summary ---------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m')=== Setup complete ===$(printf '\033[0m')

  Server jar:  $JAR_PATH
  Server dir:  $SERVER_DIR
  Heap:        $HEAP_SIZE (override with HEAP_SIZE=4G bash scripts/start.sh)
  Playit bin:  $PLAYIT_BIN

  online-mode = false  (any username works — for trusted friends only)

Next steps:
  1) Start the server :  bash scripts/start.sh
  2) Claim the tunnel :  visit the URL playit prints on first start
  3) Share the address:  send your friends the playit host:port

EOF

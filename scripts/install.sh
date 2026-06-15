#!/usr/bin/env bash
# install.sh — installs a Minecraft server of the chosen type and version,
# plus the playit.gg tunnel. Idempotent: safe to re-run.
#
# Supported types: paper, vanilla, purpur, folia, fabric, forge
#
# Configuration (env vars):
#   MC_TYPE     server type  (default: paper)
#   MC_VERSION  MC version   (default: 1.21.4)
#   HEAP_SIZE   JVM heap     (default: 2G, used by start.sh)
#   MC_NONINTERACTIVE=1  skip the interactive menu
#
# Examples:
#   bash scripts/install.sh                                  # interactive menu
#   MC_TYPE=vanilla MC_VERSION=1.20.4 bash scripts/install.sh # vanilla, no menu
#   MC_TYPE=forge MC_VERSION=1.21.4 bash scripts/install.sh   # Forge
#   MC_TYPE=fabric MC_VERSION=1.21.4 bash scripts/install.sh  # Fabric

set -euo pipefail

# ---- Configuration ---------------------------------------------------------
MC_TYPE="${MC_TYPE:-}"
MC_VERSION="${MC_VERSION:-1.21.4}"
HEAP_SIZE="${HEAP_SIZE:-2G}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/server"
PLAYIT_BIN="$HOME/playit/playit"
PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64"

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
  Codespace Minecraft server (multi-type, online-mode=false)
  Supported types: paper, vanilla, purpur, folia, fabric, forge

EOF

need java
need curl
need python3
need tar
need unzip

JAVA_VER=$(java -version 2>&1 | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
JAVA_MAJOR=$(printf '%s' "$JAVA_VER" | cut -d. -f1)
log "Java: $JAVA_VER"
if [ "${JAVA_MAJOR:-0}" -lt 17 ]; then
    err "Java 17+ required. Got $JAVA_VER. The dev container should ship Java 21."
    exit 1
fi

# ---- Interactive menu ------------------------------------------------------
if [ -z "$MC_TYPE" ] && [ -t 0 ] && [ -z "${MC_NONINTERACTIVE:-}" ] && [ -z "${CI:-}" ]; then
    echo "Which server type do you want?"
    PS3="  > "
    select t in paper vanilla purpur folia fabric forge; do
        case "$t" in
            "") echo "  Pick a number 1-6.";;
            *)  MC_TYPE="$t"; break;;
        esac
    done
    echo
    read -r -p "Minecraft version [${MC_VERSION}]: " v
    MC_VERSION="${v:-$MC_VERSION}"
    echo
fi

MC_TYPE="${MC_TYPE:-paper}"
MC_VERSION="${MC_VERSION:-1.21.4}"

case "$MC_TYPE" in
    paper|vanilla|purpur|folia|fabric|forge) ;;
    *) err "Unknown server type: $MC_TYPE (try paper, vanilla, purpur, folia, fabric, forge)"; exit 1;;
esac

log "Selected: type=$MC_TYPE version=$MC_VERSION"

# ---- Clean old install, preserving world data ------------------------------
mkdir -p "$SERVER_DIR"
EXISTING_TYPE=""
[ -f "$SERVER_DIR/.server-type" ] && EXISTING_TYPE=$(cat "$SERVER_DIR/.server-type" || true)
if [ -n "$EXISTING_TYPE" ] && [ "$EXISTING_TYPE" != "$MC_TYPE" ]; then
    warn "Switching server type: $EXISTING_TYPE -> $MC_TYPE"
    warn "Old jar/configs will be removed; world/ data is preserved."
fi
# Remove everything except world dirs, logs, and the .server-type marker
find "$SERVER_DIR" -maxdepth 1 -mindepth 1 \
    ! -name "world" \
    ! -name "world_nether" \
    ! -name "world_the_end" \
    ! -name "logs" \
    ! -name "crash-reports" \
    ! -name ".server-type" \
    -exec rm -rf {} + 2>/dev/null || true

echo "$MC_TYPE" > "$SERVER_DIR/.server-type"

# ---- Generic download helper ----------------------------------------------
download_file() {
    local url="$1" dest="$2"
    if [ -f "$dest" ] && [ -s "$dest" ]; then
        log "Already have $(basename "$dest"), skipping."
        return 0
    fi
    log "Downloading $(basename "$dest")..."
    if ! curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"; then
        err "Download failed: $url"
        return 1
    fi
    log "  saved $(du -h "$dest" | cut -f1)"
}

# ---- Type-specific installers ---------------------------------------------
install_paper() {
    local version="$MC_VERSION"
    log "Looking up Paper $version..."
    local builds_json
    builds_json=$(curl -fsSL "https://api.papermc.io/v2/projects/paper/versions/$version/builds") \
        || { err "Paper API unreachable."; return 1; }
    local build
    build=$(printf '%s' "$builds_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
b = d.get('builds') or []
if not b: sys.exit('no builds for ${version}')
print(b[-1]['build'])
") || { err "No Paper builds for $version. Try 1.21.4, 1.20.4, 1.18.2."; return 1; }
    local jar="paper-${version}-${build}.jar"
    download_file \
        "https://api.papermc.io/v2/projects/paper/versions/$version/builds/$build/downloads/$jar" \
        "$SERVER_DIR/$jar"
}

install_vanilla() {
    local version="$MC_VERSION"
    log "Looking up vanilla $version..."
    local manifest
    manifest=$(curl -fsSL "https://launchermeta.mojang.com/mc/game/version_manifest.json") \
        || { err "Mojang manifest unreachable."; return 1; }
    local version_url
    version_url=$(printf '%s' "$manifest" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for v in d['versions']:
    if v['id'] == '${version}':
        print(v['url']); break
") || true
    if [ -z "$version_url" ]; then
        err "Vanilla $version not in Mojang manifest. Try 1.21.4, 1.20.4, 1.16.5."
        return 1
    fi
    local jar_url
    jar_url=$(curl -fsSL "$version_url" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['downloads']['server']['url'])
")
    download_file "$jar_url" "$SERVER_DIR/server.jar"
}

install_purpur() {
    local version="$MC_VERSION"
    log "Looking up Purpur $version..."
    local data
    data=$(curl -fsSL "https://api.purpurmc.org/v2/purpur/$version") \
        || { err "Purpur API unreachable."; return 1; }
    local build
    build=$(printf '%s' "$data" | python3 -c "import sys, json; print(json.load(sys.stdin)['builds']['latest'])")
    download_file \
        "https://api.purpurmc.org/v2/purpur/$version/$build/download" \
        "$SERVER_DIR/purpur-${version}-${build}.jar"
}

install_folia() {
    local version="$MC_VERSION"
    log "Looking up Folia $version..."
    local builds_json
    builds_json=$(curl -fsSL "https://api.papermc.io/v2/projects/folia/versions/$version/builds") \
        || { err "Folia API unreachable."; return 1; }
    local build
    build=$(printf '%s' "$builds_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
b = d.get('builds') or []
if not b: sys.exit('no builds for ${version}')
print(b[-1]['build'])
") || { err "No Folia builds for $version. Try 1.21.4, 1.20.4."; return 1; }
    local jar="folia-${version}-${build}.jar"
    download_file \
        "https://api.papermc.io/v2/projects/folia/versions/$version/builds/$build/downloads/$jar" \
        "$SERVER_DIR/$jar"
}

install_fabric() {
    local version="$MC_VERSION"
    log "Looking up Fabric installer..."
    local installer_url
    installer_url=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/installer" | python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d[0]['version']
print(f'https://maven.fabricmc.net/net/fabricmc/fabric-installer/{v}/fabric-installer-{v}.jar')
") || { err "Fabric installer lookup failed."; return 1; }
    download_file "$installer_url" "$SERVER_DIR/fabric-installer.jar" || return 1

    log "Running Fabric installer for MC $version (this may take a minute)..."
    ( cd "$SERVER_DIR" && java -jar fabric-installer.jar server \
        -mcversion "$version" -dir "$SERVER_DIR" -download ) \
        || { err "Fabric installer failed."; return 1; }
    rm -f "$SERVER_DIR/fabric-installer.jar"
}

install_forge() {
    local version="$MC_VERSION"
    log "Looking up Forge for MC $version..."
    local metadata
    metadata=$(curl -fsSL "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml") \
        || { err "Forge maven metadata unreachable."; return 1; }
    local forge_version
    forge_version=$(printf '%s' "$metadata" | python3 -c "
import sys, re
content = sys.stdin.read()
prefix = '${version}-'
matches = re.findall(r'<version>' + re.escape(prefix) + r'([^<]+)</version>', content)
if not matches: sys.exit('no forge versions for ${version}')
def parse(v):
    return tuple(int(x) if x.isdigit() else x for x in re.split(r'[.-]', v))
print(prefix + sorted(matches, key=parse)[-1])
") || { err "No Forge build for $version. Try 1.21.4, 1.20.4, 1.16.5."; return 1; }
    log "Forge version: $forge_version"
    local installer_url="https://maven.minecraftforge.net/net/minecraftforge/forge/${forge_version}/forge-${forge_version}-installer.jar"
    download_file "$installer_url" "$SERVER_DIR/forge-installer.jar" || return 1

    log "Running Forge installer (this may take a minute)..."
    ( cd "$SERVER_DIR" && java -jar forge-installer.jar --installServer ) \
        || { err "Forge installer failed."; return 1; }
    rm -f "$SERVER_DIR/forge-installer.jar"
}

# ---- Dispatch --------------------------------------------------------------
case "$MC_TYPE" in
    paper)   install_paper   || { err "Paper install failed.";   exit 1; };;
    vanilla) install_vanilla || { err "Vanilla install failed."; exit 1; };;
    purpur)  install_purpur  || { err "Purpur install failed.";  exit 1; };;
    folia)   install_folia   || { err "Folia install failed.";   exit 1; };;
    fabric)  install_fabric  || { err "Fabric install failed.";  exit 1; };;
    forge)   install_forge   || { err "Forge install failed.";   exit 1; };;
esac

# ---- Common: EULA ----------------------------------------------------------
cat > "$SERVER_DIR/eula.txt" <<EULA
eula=true
#Accepted by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
EULA

# ---- Common: server.properties --------------------------------------------
PROPS_FILE="$SERVER_DIR/server.properties"
if [ ! -f "$PROPS_FILE" ] || ! grep -q '^online-mode=' "$PROPS_FILE"; then
    log "Writing server.properties (online-mode=false)"
    cat > "$PROPS_FILE" <<PROPS
#Minecraft server properties — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
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
    log "server.properties exists, leaving alone (forcing online-mode=false)"
    sed -i 's/^online-mode=true/online-mode=false/' "$PROPS_FILE"
fi

# ---- Common: empty state files so first start doesn't choke ----------------
[ -f "$SERVER_DIR/ops.json" ]              || printf '[]\n' > "$SERVER_DIR/ops.json"
[ -f "$SERVER_DIR/usercache.json" ]        || printf '[]\n' > "$SERVER_DIR/usercache.json"
[ -f "$SERVER_DIR/banned-players.json" ]   || printf '[]\n' > "$SERVER_DIR/banned-players.json"
[ -f "$SERVER_DIR/banned-ips.json" ]       || printf '[]\n' > "$SERVER_DIR/banned-ips.json"
[ -f "$SERVER_DIR/whitelist.json" ]        || printf '[]\n' > "$SERVER_DIR/whitelist.json"

# ---- Common: playit.gg tunnel ---------------------------------------------
log "Installing playit.gg tunnel..."
mkdir -p "$(dirname "$PLAYIT_BIN")"
if [ -x "$PLAYIT_BIN" ]; then
    log "playit already installed."
else
    if curl -fL --retry 3 -o "$PLAYIT_BIN" "$PLAYIT_URL"; then
        chmod +x "$PLAYIT_BIN"
        log "playit installed at $PLAYIT_BIN"
    else
        warn "playit download failed. Server will still start, but you'll need a tunnel."
    fi
fi

# ---- Summary ---------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m')=== Setup complete ===$(printf '\033[0m')

  Type:     $MC_TYPE
  Version:  $MC_VERSION
  Dir:      $SERVER_DIR
  Heap:     $HEAP_SIZE (override with HEAP_SIZE=4G bash scripts/start.sh)
  Playit:   $PLAYIT_BIN
  online-mode = false  (any username — whitelist is your real protection)

Next:
  bash scripts/start.sh
EOF

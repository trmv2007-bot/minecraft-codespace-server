# Minecraft server on GitHub Codespace

A **multi-type** Minecraft server that runs in a GitHub Codespace, with
`online-mode=false` so you and your friends can join using any username
(no paid Mojang account required).

- **Server types supported:** Paper (default), Vanilla, Purpur, Folia,
  Fabric, Forge. Switch any time with one env var.
- Uses the free **[playit.gg](https://playit.gg)** tunnel so the server is
  reachable from the public internet — friends just paste the playit
  address into Minecraft Multiplayer.

---

## 1. Push this repo to GitHub

```bash
cd minecraft-codespace-server
git init
git add .
git commit -m "Initial Minecraft Codespace server"
git branch -M main
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
```

## 2. Open it as a Codespace

- On the GitHub repo page, click **Code → Codespaces → Create codespace on main**.
- Wait for the container to build. The post-create step runs
  `MC_NONINTERACTIVE=1 bash scripts/install.sh`, which uses the defaults
  (Paper 1.21.4).

## 3. Start the server

In the Codespace terminal:

```bash
bash scripts/start.sh
```

You'll see playit print something like:

```
playit v0.15.x
Claim URL: https://playit.gg/claim/XXXX-XXXX-XXXX
Tunnel:    yourserver.playit.gg:25565
```

## 4. Claim the tunnel (one-time per Codespace)

Open the claim URL in any browser, sign in (free), and pick a region.
playit will then print your **permanent** address, e.g.:

```
yourserver.playit.gg:38741
```

**That's the address your friends paste into Minecraft → Multiplayer → Add Server.**

`playit` saves its credentials to `~/playit/.playit/`, so restarts of the
Codespace keep the same address. Rebuilding the Codespace from scratch
makes you claim again — that's a Codespace limitation, not a playit one.

## 5. Become an operator

`online-mode=false` lets anyone in, so the **first thing you should do**
is op yourself and turn on the whitelist:

```text
op YourName
whitelist on
whitelist add Friend1
whitelist add Friend2
```

Anyone not on the whitelist will get "You are not whitelisted" until you
add them.

---

## Switching server type or version

The repo defaults to Paper 1.21.4, but you can install any of the
supported types. **World data is preserved across switches** (it's stored
in `server/world/`, which install.sh leaves alone).

```bash
# Interactive: pick from a menu
bash scripts/install.sh

# Non-interactive: use env vars
MC_TYPE=vanilla  MC_VERSION=1.20.4  bash scripts/install.sh
MC_TYPE=purpur   MC_VERSION=1.21.4  bash scripts/install.sh
MC_TYPE=folia    MC_VERSION=1.21.4  bash scripts/install.sh
MC_TYPE=fabric   MC_VERSION=1.21.4  bash scripts/install.sh
MC_TYPE=forge    MC_VERSION=1.21.4  bash scripts/install.sh
```

`start.sh` reads the type back from `server/.server-type` and runs the
right launcher (Forge's `run.sh`, Fabric's `fabric-server-launch.jar`,
or the server jar directly for Paper/Vanilla/Purpur/Folia).

### Which type should I pick?

| Type       | Best for                                                                 |
|------------|--------------------------------------------------------------------------|
| `paper`    | **Default.** Fast, widely compatible, supports Bukkit/Spigot plugins.    |
| `vanilla`  | Just the base game, no plugins, no optimization. Good for a pure run.    |
| `purpur`   | Paper fork with more configuration options.                             |
| `folia`    | Paper fork for multi-threaded servers. Different chunk format, picky.    |
| `fabric`   | Lightweight mod loader. Use this if your friends want to install mods.   |
| `forge`    | Heavy mod loader, the classic modpack platform. Slower startup, heavier. |

---

## Files

| Path                              | What it does                                                |
|-----------------------------------|-------------------------------------------------------------|
| `.devcontainer/devcontainer.json` | Java 21 base image, ports 25565/tcp, post-create runs install.sh with `MC_NONINTERACTIVE=1` |
| `scripts/install.sh`              | Downloads the chosen server, accepts EULA, writes config, installs playit |
| `scripts/start.sh`                | Runs the server (foreground, with live console) + playit in background |
| `server/`                         | Generated at install time — jar, world, logs              |
| `server/.server-type`             | Marker file so start.sh knows which launcher to invoke      |
| `server/server.properties`        | `online-mode=false`, view-distance 10, motd set            |
| `server/eula.txt`                 | EULA accepted on your behalf                                |

## Useful commands inside the server console

| Command                  | What it does                                |
|--------------------------|---------------------------------------------|
| `op <name>`              | Give a player operator status               |
| `deop <name>`            | Remove operator status                      |
| `whitelist on`           | Enable whitelist (recommended)               |
| `whitelist add <name>`   | Add a friend to the whitelist                |
| `kick <name>`            | Kick a misbehaving player                   |
| `stop`                   | Graceful shutdown                           |
| `say <msg>`              | Broadcast a message to all players          |
| `difficulty hard`        | Set difficulty to hard                      |
| `time set day`           | Set time to day                             |
| `gamemode creative <name>` | Make someone creative (ops only)         |

## Tweaking

```bash
# Use a different Minecraft version
MC_VERSION=1.20.4 bash scripts/install.sh

# Give the server more memory
HEAP_SIZE=4G bash scripts/start.sh
```

If you change memory, make sure your Codespace has enough RAM — the
default GitHub Codespace machine type ships with 4 GB. Bump the machine
type under **Codespaces → machine type** if you go above 3 GB heap.

## Stopping the server

Just type `stop` in the console, or press `Ctrl+C` once. Both terminate
playit along with the server. To stop **only the server** while keeping
the tunnel alive (rare), open a second terminal and run
`pkill -f paper-.*\.jar`.

## Troubleshooting

- **`ModuleNotFoundError: No module named 'json'`** — fixed in the
  latest version of this repo. The Java dev container's `python3-minimal`
  lacks the `_json` C extension, so `install.sh` no longer depends on
  Python — it uses `jq` instead. Pull the latest (`git pull`) and re-run
  `bash scripts/install.sh`; it'll `apt-get install jq` automatically.
- **"No server jar found" / "no run.sh"** — install.sh didn't complete.
  From the Codespace root: `bash scripts/install.sh`. Look at the error
  message; the most common cause is the version not existing for that
  type.
- **`online-mode=true` keeps coming back** — re-run install.sh; it
  forces `online-mode=false` on every run.
- **Friends can't connect** — make sure the playit address in Minecraft
  includes the port, e.g. `yourserver.playit.gg:38741`. Default
  Minecraft port is 25565; playit usually picks a high random port,
  that's normal.
- **"Failed to bind to port 25565"** — wait 10 seconds and try again; the
  container may still be releasing the port from a previous run.
- **Connection drops when Codespace sleeps** — Codespaces sleep after
  30 minutes of inactivity by default; bump this under Codespace
  settings or ask someone to stay in-game.
- **Forge installer complains** — Forge version 1.20.1+ requires Java
  17+, and 1.20.5+ requires Java 21. The dev container ships Java 21, so
  this should not be an issue. If you ever switch to a 1.16.5 server,
  Java 8/11 is needed and the dev container image will need to change.
- **Fabric installer complains** — usually means the version doesn't
  have a published Fabric loader. Pick a different version (1.21.x,
  1.20.x are well-supported).

## ⚠️ Security note

`online-mode=false` means **the server trusts whatever username the
client sends**. This is fine for a trusted friend group but trivially
exploitable by griefers on the open internet. That's why the setup
above turns the whitelist on as a recommended first step. For a public
server, switch back to `online-mode=true` and require your friends to own
a paid Mojang account.

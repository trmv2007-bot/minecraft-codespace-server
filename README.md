# Minecraft server on GitHub Codespace

A one-click **Paper** Minecraft server that runs in a GitHub Codespace, with
`online-mode=false` so you and your friends can join using any username
(no paid Mojang account required).

It uses the free **[playit.gg](https://playit.gg)** tunnel so the server is
reachable from the public internet — friends just paste the playit address
into Minecraft Multiplayer.

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
- Wait for the container to build. The post-create step runs `scripts/install.sh`,
  which downloads the latest Paper jar for Minecraft **1.21.4** (override with
  `MC_VERSION=1.20.4 bash scripts/install.sh`).

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

(`playit` saves its credentials to `~/playit/.playit/`, so restarts of the
Codespace keep the same address. Rebuilding the Codespace from scratch makes
you claim again — that's a Codespace limitation, not a playit one.)

## 5. Become an operator

`online-mode=false` lets anyone in, so the **first thing you should do** is
op yourself and turn on the whitelist:

```text
op YourName
whitelist on
whitelist add Friend1
whitelist add Friend2
```

Anyone not on the whitelist will get "You are not whitelisted" until you
add them.

---

## Files

| Path                         | What it does                                      |
|------------------------------|---------------------------------------------------|
| `.devcontainer/devcontainer.json` | Java 21 base image, ports 25565/tcp, post-create runs install.sh |
| `scripts/install.sh`         | Downloads Paper, accepts EULA, writes config, installs playit |
| `scripts/start.sh`           | Runs the server (foreground, with live console) + playit in background |
| `server/`                    | Generated at install time — jar, world, logs     |
| `server/server.properties`   | `online-mode=false`, view-distance 10, motd set  |
| `server/eula.txt`            | EULA accepted on your behalf                      |

## Useful commands inside the server console

| Command               | What it does                                |
|-----------------------|---------------------------------------------|
| `op <name>`           | Give a player operator status               |
| `deop <name>`         | Remove operator status                      |
| `whitelist on`        | Enable whitelist (recommended)               |
| `whitelist add <name>`| Add a friend to the whitelist                |
| `kick <name>`         | Kick a misbehaving player                   |
| `stop`                | Graceful shutdown                           |
| `say <msg>`           | Broadcast a message to all players          |
| `difficulty hard`     | Set difficulty to hard                      |
| `time set day`        | Set time to day                             |
| `gamemode creative <name>` | Make someone creative (ops only)       |

## Tweaking

```bash
# Use a different Minecraft version
MC_VERSION=1.20.4 bash scripts/install.sh

# Give the server more memory
HEAP_SIZE=4G bash scripts/start.sh
```

If you change memory, make sure your Codespace has enough RAM — the default
GitHub Codespace machine type ships with 4 GB. Bump the machine type under
**Codespaces → machine type** if you go above 3 GB heap.

## Stopping the server

Just type `stop` in the console, or press `Ctrl+C` once. Both terminate playit
along with the server. To stop **only the server** while keeping the tunnel
alive (rare), open a second terminal and run `pkill -f paper-.*\.jar`.

## Troubleshooting

- **"No paper jar found"** — install.sh didn't run. From the Codespace root:
  `bash scripts/install.sh`.
- **Friends can't connect** — make sure the playit address in Minecraft
  includes the port, e.g. `yourserver.playit.gg:38741`. Default Minecraft
  port is 25565; playit usually picks a high random port, that's normal.
- **"Failed to bind to port 25565"** — wait 10 seconds and try again; the
  container may still be releasing the port from a previous run.
- **Connection drops when Codespace sleeps** — Codespaces sleep after 30
  minutes of inactivity by default; bump this under Codespace settings or
  ask someone to stay in-game.
- **`online-mode=true` keeps coming back** — something is overwriting your
  config. Edit `server/server.properties` while the server is stopped, or
  re-run `bash scripts/install.sh` (it will leave existing files alone but
  force `online-mode=false`).

## ⚠️ Security note

`online-mode=false` means **the server trusts whatever username the client
sends**. This is fine for a trusted friend group but trivially exploitable
by griefers on the open internet. That's why the setup above turns the
whitelist on as a recommended first step. For a public server, switch back
to `online-mode=true` and require your friends to own a paid Mojang account.

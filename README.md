# ⛏ MineManager

**A zero-dependency Bash wrapper for managing self-hosted Minecraft servers on Linux.** Start, stop, update, back up, and administer your server — all from a single script, no Docker or third-party tooling required.

> Built for homelabs and self-hosted setups where you want full control without the overhead.

---

## Features

- **Start / Stop** — Launch and gracefully shut down the Minecraft server inside a named `screen` session
- **Automatic Updates** — Fetches the official Mojang version manifest, compares SHA1 hashes, and downloads a new `server.jar` only when needed
- **Specific Version Install** — Install any Minecraft release version by number (e.g. `1.20.4`) directly from Mojang's servers
- **Version Browser** — List the latest N releases or every available release from the version manifest
- **Java Compatibility Check** — Reads the required Java major version from the release manifest and validates it against the installed JDK/JRE before any download
- **Live-Safe Backups** — Creates timestamped `.tar.gz` archives of the world directory; when the server is running it sends `save-off` + `save-all` before archiving, then re-enables saving, so no chunks are lost
- **Admin Command Injection** — Sends any quoted server command via `screen` and captures the server's log response in the terminal
- **Status Check** — Reports whether a server instance is active and which version is running
- **Log Cleanup** — Removes rotated `.log.gz` files from the Java logs directory in one command
- **Permission Management** — Automatically creates the `minecraft` system user (no home, no shell) and sets correct ownership across all server directories on every run
- **EULA Auto-Accept** — Writes `eula=true` on first setup so the server can start without manual intervention
- **Fully Configurable** — All paths, memory limits, usernames, and service names are overridable via `minemg.conf` without editing the script

---

## Requirements

| Dependency | Purpose |
|---|---|
| `bash` | Script runtime |
| `screen` | Runs the Minecraft server in a detached session |
| `curl` | Fetches the Mojang version manifest |
| `wget` | Downloads `server.jar` |
| `jq` | Parses JSON from the version manifest |
| `tar` | Creates world backups |
| `java` (JDK/JRE) | Runs the Minecraft server; headless preferred |

Install on Debian/Ubuntu:

```bash
sudo apt install screen curl wget jq tar default-jre-headless
```

Install on RHEL/Fedora/CentOS:

```bash
sudo dnf install screen curl wget jq tar java-21-openjdk-headless
```

> MineManager checks for all missing dependencies at startup and prints them all at once before aborting, so you won't get hit one at a time.

---

## Directory Layout

By default, MineManager creates and manages this structure under `/opt/minecraft`:

```
/opt/minecraft/
├── server/
│   └── server.jar          ← downloaded Minecraft server JAR
├── java/
│   ├── eula.txt            ← auto-created on first run
│   └── logs/
│       └── latest.log      ← read for command responses and cleanup
└── world/
    └── mc-server/          ← world data (name set by WORLD_NAME)
```

All paths are configurable via `minemg.conf`.

---

## Installation

```bash
# Clone the repository
git clone https://github.com/spacec0rgo/MineManager.git
cd MineManager

# Copy and edit the config (optional but recommended)
nano minemg.conf

# Make the script executable
chmod +x minemg.sh
```

No package installation or compilation needed. The script is self-contained.

---

## Configuration

Place `minemg.conf` in the same directory as `minemg.sh`. Every value has a built-in default so the file is entirely optional — values set here override the script defaults.

```bash
### OPTIONAL CONFIGURATION FILE FOR MINEMANAGER
### THIS WILL OVERWRITE DEFAULTS, EDIT WITH CAUTION

# World configuration
WORLD_NAME="mc-server"

# Server memory resources
INITIAL_MEMORY="1024M"
MAXIMUM_MEMORY="4096M"

# Service configuration
mcServerUser="minecraft"
mcServiceName="minecraft_server"

### DIRECTORIES
# Main server directory
serviceDir="/opt/minecraft"
# Server directories (derived from serviceDir by default)
serverDir="${serviceDir}/server"
serverFile="${serverDir}/server.jar"
javaDir="${serviceDir}/java"
worldDir="${serviceDir}/world"
logFile="${javaDir}/logs/latest.log"

### JAVA
# Java binary path (multi-version environments)
JAVA_BIN="/usr/bin/java"
```

### Configuration reference

| Variable | Default | Description |
|---|---|---|
| `WORLD_NAME` | `mc-server` | Name of the world directory inside `worldDir` |
| `INITIAL_MEMORY` | `1024M` | JVM `-Xms` heap allocation |
| `MAXIMUM_MEMORY` | `4096M` | JVM `-Xmx` heap allocation |
| `mcServerUser` | `minecraft` | System user the server process runs as |
| `mcServiceName` | `minecraft_server` | Name of the `screen` session |
| `serviceDir` | `/opt/minecraft` | Root directory for all server files |
| `serverDir` | `$serviceDir/server` | Directory containing `server.jar` |
| `serverFile` | `$serverDir/server.jar` | Full path to the JAR file |
| `javaDir` | `$serviceDir/java` | Java working directory (logs, eula.txt) |
| `worldDir` | `$serviceDir/world` | Parent directory for world data |
| `logFile` | `$javaDir/logs/latest.log` | Path to the live server log |
| `JAVA_BIN` | `/usr/bin/java` | Path to the Java binary |

---

## Usage

MineManager **must be run as root** (it manages system users, file permissions, and `su` into the server user).

```bash
sudo ./minemg.sh [flags] ...
```

### All flags

```
-h,  --help                          Print the help page
     --start                         Start the Minecraft server
     --stop                          Stop the Minecraft server
-c,  --command <command>             Send a quoted command to the server (e.g. 'say Hello')
-up, --update                        Update server.jar if a newer release is available
     --status                        Check whether the server is running and print its version
-vv, --versions <num|all>            List available Minecraft release versions (N most recent, or all)
-iv, --install-version <version>     Install a specific Minecraft release version (e.g. 1.20.4)
-sku,--skip-up-check                 Skip the Mojang version manifest check on startup
-fd, --force-download                Force re-download of server.jar even if hashes match
-bak,--backup <path>                 Create a world backup archive in the specified directory
-cls,--clean-logs                    Remove rotated .log.gz files from the logs directory
```

---

## Examples

### First-time setup and start

On the very first run, MineManager will fetch the version manifest, verify Java compatibility, download the latest `server.jar`, create the full directory structure, set up the `minecraft` system user, and write `eula.txt` automatically.

```bash
sudo ./minemg.sh --start
```

### Start and stop the server

```bash
sudo ./minemg.sh --start
sudo ./minemg.sh --stop
```

### Check server status

```bash
sudo ./minemg.sh --status
# [+] MC server is up and running
# [+] Server version: 1.21.4
```

### Update to the latest release

```bash
sudo ./minemg.sh --update
```

The script compares the SHA1 hash of the local `server.jar` against the Mojang manifest. If they differ and Java is compatible, the new JAR is downloaded. If they match, nothing is changed.

### Install a specific version

```bash
sudo ./minemg.sh --install-version 1.20.4
```

### Browse available versions

```bash
# Show the 10 most recent releases
sudo ./minemg.sh --versions 10

# Show all available releases
sudo ./minemg.sh --versions all
```

### Send an admin command

```bash
sudo ./minemg.sh --command 'say Server restarting in 5 minutes'
sudo ./minemg.sh --command 'op YourUsername'
sudo ./minemg.sh --command 'list'
```

The command is injected into the `screen` session via timestamped log markers, and the server's response is captured and printed to your terminal.

### Back up the world

```bash
# Works whether the server is online or offline
sudo ./minemg.sh --backup /mnt/backups
```

If the server is running, MineManager will automatically send `save-off` and `save-all` before creating the archive, then re-enable saving after. The backup file is named with a full timestamp, e.g. `2025-04-27_143022000_mc-server_bak.tar.gz` and is automatically assigned to the user defined in `mcServerUser`.

### Clean up old logs

```bash
sudo ./minemg.sh --clean-logs
```

Removes all `.log.gz` rotated log files from the Java logs directory, leaving `latest.log` untouched.

### Skip the version check on startup

```bash
# Start the server without hitting the Mojang API
sudo ./minemg.sh --start --skip-up-check
```

> `--skip-up-check` is incompatible with `--update`, `--force-download`, and `--install-version`. The script will reject these combinations and exit with an error.

### Force re-download the server JAR

```bash
sudo ./minemg.sh --force-download
```

---

## Running as a systemd Service (Optional)

To have the server start automatically on boot, create a systemd unit that calls MineManager:

```ini
# /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server (MineManager)
After=network.target

[Service]
Type=forking
User=root
ExecStart=/<path>/MineManager/minemg.sh --start --skip-up-check
ExecStop=/<path>/MineManager/minemg.sh --stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft
```

---

## Troubleshooting

**`'/run/screen': Permission denied`**

This is a known `screen` permission issue on some systems, which will throw an error when trying to start the server. 

```
Cannot make directory '/run/screen': Permission denied
```

Fix it with:

```bash
sudo /etc/init.d/screen-cleanup start
```

**Server won't start after update**

The Java compatibility check prevents downloading or starting if your installed Java major version is lower than what the release requires. Install a newer JDK, update `JAVA_BIN` in `minemg.conf` if you have multiple Java versions installed, and try again.

**Commands aren't returning output**

The command-response capture reads from `logFile`. Make sure the path in your config points to the live `latest.log` of the running server and that the `minecraft` user has write access to it.

---

## License

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for details.

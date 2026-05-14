<div align="center">

<pre>
██╗  ██╗ █████╗ ███╗   ██╗ ██████╗  █████╗ ██████╗
██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔══██╗██╔══██╗
███████║███████║██╔██╗ ██║██║  ███╗███████║██████╔╝
██╔══██║██╔══██║██║╚██╗██║██║   ██║██╔══██║██╔══██╗
██║  ██║██║  ██║██║ ╚████║╚██████╔╝██║  ██║██║  ██║
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
</pre>

<h3>Preflight your drone dev environment.</h3>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/shell-bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/24.04/)
[![Ubuntu 22.04](https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/22.04/)

</div>

---

**Hangar** is a menu-driven installer that turns a fresh Ubuntu install into a complete drone autonomy development environment in one command. From a clean ISO to flying a simulated drone in SITL with a working Python autonomy stack — typically 30–60 minutes, mostly unattended.

## What it installs

- **System base** — apt updates, build essentials, kernel headers
- **VM guest tools** — auto-detects VMware, VirtualBox, Hyper-V, or KVM
- **Developer tools** — git, vim, htop, tmux, python3 + venv, ssh, rsync
- **Visual Studio Code** — with Python, Ruff, YAML, TOML, and GitLens extensions
- **QGroundControl** — AppImage + Qt runtime deps + desktop launcher
- **Mission Planner** — Mono runtime + Mission Planner with sanitized launch wrapper
- **ArduPilot + SITL** — clones the repo, runs official prereqs, builds SITL ArduCopter
- **Autonomy starter kit** — Python autonomy framework with FC adapter and SITL test scripts
- **Wireshark** — Wireshark + tshark for MAVLink protocol debugging

## Quick start

```bash
git clone https://github.com/RedactedIndustries/Hangar.git
cd Hangar
chmod +x hangar.sh
./hangar.sh
```

Pick option 1 from the menu for a full install. Walk away. Come back to a working dev environment.

To set git identity at install time:

```bash
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./hangar.sh
```

## Requirements

- **Ubuntu 24.04 LTS** (recommended) or **Ubuntu 22.04 LTS**, Desktop edition
- **Sudo access** — prompted once at the start; credentials cached for the run
- **Internet access** — for package downloads and the ArduPilot source clone
- **~10 GB free disk in `$HOME`** — ArduPilot's build artifacts are heavy
- **Bash 4+** — uses associative arrays

## Menu overview

```
Main Menu
─────────────────────────────────────────────────

  1)  Quick install        — run all phases (recommended)
  2)  Custom install       — pick which phases to run
  3)  Run single phase     — pick one phase and run only it
  4)  Show status          — what's been installed already
  5)  Configure settings   — git identity, paths
  6)  View install log     — tail the most recent run
  7)  About                — license, version, attribution

  q)  Quit
```

Phases run in dependency order. Each is independently selectable and individually idempotent — re-running any phase is safe.

| # | Phase | Approximate runtime |
|---|---|---|
| 1 | System Updates | 5–15 min |
| 2 | VM Guest Tools | 1–2 min |
| 3 | Developer Tools | 2–3 min |
| 4 | Visual Studio Code | 2–3 min |
| 5 | QGroundControl | 2–3 min |
| 6 | Mission Planner | 3–5 min |
| 7 | ArduPilot + SITL | 15–25 min |
| 8 | Autonomy Project | 1–2 min |
| 9 | Wireshark | 1–2 min |
| 10 | Finalize | < 1 min |

## Configuration

All optional. Set inline or interactively from the Settings menu (option 5).

| Variable | Default | Purpose |
|---|---|---|
| `GIT_NAME` | _(unset)_ | git user.name to set globally |
| `GIT_EMAIL` | _(unset)_ | git user.email to set globally |
| `ARDUPILOT_DIR` | `$HOME/ardupilot` | Where to clone ArduPilot |
| `TOOLS_DIR` | `$HOME/tools` | Where to install QGC and Mission Planner |
| `PROJECTS_DIR` | `$HOME/projects` | Where to unpack the autonomy starter kit |
| `AUTONOMY_TARBALL` | `$HOME/Downloads/drone-autonomy-starter.tar.gz` | Override tarball path |
| `AUTONOMY_TARBALL_URL` | GitHub raw URL | Override tarball download source |
| `NO_COLOR` | _(unset)_ | Set to disable ANSI color codes |

## State tracking

Hangar tracks completed phases in `~/.hangar-state`. The status screen shows what's done, and the custom-install menu lets you skip installed phases and re-run only what failed.

Every phase is idempotent. Re-running Hangar on a working install is a no-op.

### Recovering from a partial install

```bash
./hangar.sh
# → option 2 (Custom install)
# → press 'u' to unselect installed phases
# → press 'r' to run what remains
```

## Post-install

Two things you should do after Hangar finishes:

1. **Log out and back in.** Required for `dialout` and `wireshark` group membership and for `sim_vehicle.py` to appear on PATH in new shells.
2. **Take a VM snapshot.** Name it "clean dev environment." This is your rollback point if anything ever breaks.

### Verify the install

```bash
# Terminal 1 — start SITL
cd ~/ardupilot
sim_vehicle.py -v ArduCopter --console --map --out=udp:127.0.0.1:14551

# Terminal 2 — run the smoke test
cd ~/projects/drone-autonomy
source .venv/bin/activate
python scripts/sitl_test_takeoff.py
```

If the simulated drone arms, climbs to 10m, hovers, and lands, your environment is fully functional.

## Hardware target

Built for a Raspberry Pi 5 8GB + AI Hat+ companion computer talking to an H7-class ArduCopter flight controller, with SiK telemetry and ELRS RC. The dev environment works equally well for any ArduPilot-supported FC — Pixhawk, CubePilot, Holybro, MicoAir, etc.

## Troubleshooting

**`curl: command not found` during preflight.** Hangar bootstraps curl automatically, but if you hit this on an older version:

```bash
sudo apt update && sudo apt install -y curl wget ca-certificates
./hangar.sh
```

**`sim_vehicle.py: command not found` after install.** Log out and back in, or:

```bash
. ~/.profile
```

**Mission Planner rendering glitches under Mono.** Use the included wrapper:

```bash
~/tools/mission-planner/run-mp.sh
```

**ArduPilot build fails with "submodule not found".** Submodule fetch interrupted. Retry:

```bash
cd ~/ardupilot
git submodule update --init --recursive
./waf configure --board sitl
./waf copter
```

**Logs.** Every run appends to `~/hangar-install.log`. Tail it directly or use option 6 in the menu.

## License

MIT. Copyright © 2026 Redacted Industries LLC.

```
SPDX-License-Identifier: MIT
```

## Why "Hangar"?

A hangar is where you check your aircraft over before flying. Lights on, engines off, walking around with a clipboard. Tightening bolts, topping off fluids, verifying everything is where it should be.

That's what this script does — gets your dev environment thoroughly checked out and ready before you start writing code that flies real hardware.

---

<div align="center">

*Cleared for takeoff. Good luck.*

</div>
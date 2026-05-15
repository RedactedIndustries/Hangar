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

**Hangar** is a menu-driven installer that turns a fresh Ubuntu install into a complete drone autonomy development environment in one command. From a clean ISO to flying a simulated drone in SITL, typically 30 to 60 minutes, mostly unattended.

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
- Sudo access (you'll be prompted at the start)
- Internet connection
- ~10 GB free disk in `$HOME`

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

Phases run in dependency order. Each is independently selectable and individually idempotent. Re-running any phase is safe.

## Configuration

All optional. Set inline or interactively from the Settings menu (option 5).

| Variable | Default | Purpose |
|---|---|---|
| `GIT_NAME` | _(unset)_ | git user.name to set globally |
| `GIT_EMAIL` | _(unset)_ | git user.email to set globally |
| `ARDUPILOT_DIR` | `$HOME/ardupilot` | Where to clone ArduPilot |
| `TOOLS_DIR` | `$HOME/tools` | Where to install QGC and Mission Planner |
| `PROJECTS_DIR` | `$HOME/projects` | Where to unpack the autonomy starter kit |
| `NO_COLOR` | _(unset)_ | Set to disable ANSI color codes |

## State tracking

Hangar tracks completed phases in `~/.hangar-state`. The status screen shows what's done, and the custom-install menu lets you skip installed phases and re-run only what failed.

Every phase is idempotent. Re-running Hangar on a working install is a no-op.

## Post-install

Three things you should do after Hangar finishes:

1. **Open a new terminal** (or `source ~/.bashrc` in your current one) to pick up the ArduPilot PATH updates.
2. **Log out and back in once.** Required for `dialout` and `wireshark` group memberships to take effect.
3. **Take a VM snapshot.** Name it "clean dev environment." This is your rollback point if anything ever breaks.

### Verify the install

```bash
# Terminal 1 — start SITL
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

**`sim_vehicle.py: command not found` after install.** Open a new terminal, or reload bashrc in your current one:

```bash
source ~/.bashrc
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

## License

MIT. Copyright © 2026 Redacted Industries LLC.

```
SPDX-License-Identifier: MIT
```

## Why "Hangar"?

A hangar is where you check your aircraft over before flying. Lights on, engines off, walking around with a clipboard. Tightening bolts, topping off fluids, verifying everything is where it should be.

That's what this script does. It gets your dev environment thoroughly checked out and ready before you start writing code that flies real hardware.

---

<div align="center">

*Cleared for takeoff. Good luck.*

</div>
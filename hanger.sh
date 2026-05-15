#!/usr/bin/env bash
# =============================================================================
#  _   _   _   _   _   _    _
# | | | | / \ | \ | | / ` | / \ | |) |
# | |_| | / _ \ | \| | | (_ | / _ \ | |/ /
# |_| |_|/_/ \_\|_|\_| \___|/_/ \_\|_|\_\
#
#                          H A N G A R
#               preflight your drone dev environment
# =============================================================================
#
# Hangar — Drone development environment installer for Ubuntu.
#
# Sets up a complete drone autonomy development workstation:
# system tooling, IDE, ArduPilot SITL, ground control stations,
# and project scaffolding.
#
# -----------------------------------------------------------------------------
# Copyright (c) 2026 Redacted Industries LLC
#
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# =============================================================================

set -euo pipefail

HANGAR_VERSION="0.3.1"
HANGAR_AUTHOR="Redacted Industries LLC"

# Resolve the directory this script lives in, even if invoked via symlink or
# from another working directory. Used as the primary lookup location for
# bundled files (e.g., the autonomy starter tarball).
HANGAR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Configuration (override via env vars)
# -----------------------------------------------------------------------------
: "${GIT_NAME:=}"
: "${GIT_EMAIL:=}"
: "${ARDUPILOT_DIR:=$HOME/ardupilot}"
: "${TOOLS_DIR:=$HOME/tools}"
: "${PROJECTS_DIR:=$HOME/projects}"
# Tarball lookup is layered: same-dir as script, ~/Downloads, then GitHub.
: "${AUTONOMY_TARBALL:=$HOME/Downloads/drone-autonomy-starter.tar.gz}"
: "${AUTONOMY_TARBALL_URL:=https://raw.githubusercontent.com/RedactedIndustries/Hangar/main/drone-autonomy-starter.tar.gz}"

LOG_FILE="$HOME/hangar-install.log"
STATE_FILE="$HOME/.hangar-state"

# -----------------------------------------------------------------------------
# Colors and styling
# -----------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    WHITE=$'\033[1;37m'
    GRAY=$'\033[0;90m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    RED="" GREEN="" YELLOW="" BLUE="" CYAN=""
    WHITE="" GRAY="" BOLD="" DIM="" NC=""
fi

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log()       { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }
say()       { echo -e "$*" | tee -a "$LOG_FILE"; }
say_quiet() { echo -e "$*"; echo "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"; }
info()      { say "${CYAN}ℹ${NC}  $*"; }
warn()      { say "${YELLOW}⚠${NC}  $*"; }
err()       { say "${RED}✗${NC}  $*" >&2; }
ok()        { say "${GREEN}✓${NC}  $*"; }
step()      { say "${BLUE}▸${NC}  ${BOLD}$*${NC}"; }

# -----------------------------------------------------------------------------
# Phase registry
# -----------------------------------------------------------------------------
# Phase IDs in canonical install order
PHASE_IDS=(
    system_update
    vmtools
    dev_tools
    vscode
    qgc
    mission_planner
    ardupilot
    autonomy_project
    wireshark
    finalize
)

# Friendly names and descriptions for each phase
declare -A PHASE_NAME=(
    [system_update]="System Updates"
    [vmtools]="VM Guest Tools"
    [dev_tools]="Developer Tools"
    [vscode]="Visual Studio Code"
    [qgc]="QGroundControl"
    [mission_planner]="Mission Planner"
    [ardupilot]="ArduPilot + SITL"
    [autonomy_project]="Autonomy Project"
    [wireshark]="Wireshark"
    [finalize]="Finalize"
)

declare -A PHASE_DESC=(
    [system_update]="apt update, full-upgrade, kernel headers, build-essential"
    [vmtools]="VMware/VirtualBox/Hyper-V/KVM guest tools (auto-detect)"
    [dev_tools]="git, vim, htop, tmux, python venv, ssh"
    [vscode]="VS Code + Python/Ruff/YAML/TOML/GitLens extensions"
    [qgc]="QGroundControl AppImage + Qt deps + dialout group"
    [mission_planner]="Mono runtime + Mission Planner (Windows GCS on Linux)"
    [ardupilot]="Clone ArduPilot, install prereqs, build SITL ArduCopter (~15 min)"
    [autonomy_project]="Install drone-autonomy starter kit (bundled or downloaded), create venv"
    [wireshark]="Wireshark + tshark for MAVLink protocol debugging"
    [finalize]="Disable UFW, print version summary"
)

declare -A PHASE_DURATION=(
    [system_update]="5-15 min"
    [vmtools]="1-2 min"
    [dev_tools]="2-3 min"
    [vscode]="2-3 min"
    [qgc]="2-3 min"
    [mission_planner]="3-5 min"
    [ardupilot]="15-25 min"
    [autonomy_project]="1-2 min"
    [wireshark]="1-2 min"
    [finalize]="< 1 min"
)

# Track which phases are selected for the run
declare -A PHASE_SELECTED
for p in "${PHASE_IDS[@]}"; do
    PHASE_SELECTED[$p]=1
done

# -----------------------------------------------------------------------------
# State tracking (which phases have completed successfully on prior runs)
# -----------------------------------------------------------------------------
load_state() {
    declare -gA PHASE_DONE=()
    if [[ -f "$STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            PHASE_DONE[$key]="$value"
        done < "$STATE_FILE"
    fi
}

mark_done() {
    local phase="$1"
    PHASE_DONE[$phase]=$(date +%Y-%m-%dT%H:%M:%S)
    save_state
}

save_state() {
    {
        for key in "${!PHASE_DONE[@]}"; do
            echo "$key=${PHASE_DONE[$key]}"
        done
    } > "$STATE_FILE"
}

# -----------------------------------------------------------------------------
# ASCII art banner
# -----------------------------------------------------------------------------
print_banner() {
    clear
    cat <<EOF
${CYAN}
    ┌─────────────────────────────────────────────────────────────┐
    │${NC}${WHITE}${BOLD}                                                             ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ██╗  ██╗ █████╗ ███╗   ██╗ ██████╗  █████╗ ██████╗     ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔══██╗██╔══██╗    ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ███████║███████║██╔██╗ ██║██║  ███╗███████║██████╔╝    ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ██╔══██║██╔══██║██║╚██╗██║██║   ██║██╔══██║██╔══██╗    ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ██║  ██║██║  ██║██║ ╚████║╚██████╔╝██║  ██║██║  ██║    ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}      ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝    ${CYAN}│${NC}
    ${CYAN}│${NC}${WHITE}${BOLD}                                                             ${CYAN}│${NC}
    ${CYAN}│${NC}${DIM}              preflight your drone dev environment           ${CYAN}│${NC}
    ${CYAN}│${NC}                                                             ${CYAN}│${NC}
    ${CYAN}│${NC}${GRAY}                v${HANGAR_VERSION}  ·  ${HANGAR_AUTHOR}           ${CYAN}│${NC}
    ${CYAN}│${NC}                                                             ${CYAN}│${NC}
    ${CYAN}└─────────────────────────────────────────────────────────────┘${NC}

         ${DIM}A small plane in the corner of a hangar, lights on,${NC}
            ${DIM}engines off, getting checked before it flies.${NC}

EOF
}

# Smaller banner for use mid-flow
print_mini_banner() {
    say ""
    say "${CYAN}┌─[${NC} ${BOLD}HANGAR${NC} ${CYAN}]${NC}${DIM}─────────────────────────────────────────────${NC}"
    say "${CYAN}│${NC}  $*"
    say "${CYAN}└────────────────────────────────────────────────────${NC}"
    say ""
}

# -----------------------------------------------------------------------------
# UI: menus
# -----------------------------------------------------------------------------
press_enter() {
    echo
    read -r -p "  ${DIM}Press Enter to continue…${NC}" _
}

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"
    local hint="[Y/n]"
    [[ "$default" == "n" ]] && hint="[y/N]"

    local response
    read -r -p "  ${BOLD}${prompt}${NC} ${hint} " response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

# Render the main menu and return the user's choice via the global $MENU_CHOICE
show_main_menu() {
    print_banner

    say "${BOLD}${WHITE}Main Menu${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""
    say "  ${CYAN}1${NC})  ${BOLD}Quick install${NC}        ${DIM}— run all phases (recommended)${NC}"
    say "  ${CYAN}2${NC})  ${BOLD}Custom install${NC}       ${DIM}— pick which phases to run${NC}"
    say "  ${CYAN}3${NC})  ${BOLD}Run single phase${NC}     ${DIM}— pick one phase and run only it${NC}"
    say "  ${CYAN}4${NC})  ${BOLD}Show status${NC}          ${DIM}— what's been installed already${NC}"
    say "  ${CYAN}5${NC})  ${BOLD}Configure settings${NC}   ${DIM}— git identity, paths${NC}"
    say "  ${CYAN}6${NC})  ${BOLD}View install log${NC}     ${DIM}— tail the most recent run${NC}"
    say "  ${CYAN}7${NC})  ${BOLD}About${NC}                ${DIM}— license, version, attribution${NC}"
    say ""
    say "  ${CYAN}q${NC})  ${BOLD}Quit${NC}"
    say ""
    say "${DIM}─────────────────────────────────────────────────${NC}"

    local choice
    read -r -p "  Choose: " choice
    MENU_CHOICE="$choice"
}

# Interactive phase picker — toggles selection state
show_phase_picker() {
    while true; do
        print_banner
        say "${BOLD}${WHITE}Custom Install — Select Phases${NC}"
        say "${DIM}─────────────────────────────────────────────────${NC}"
        say ""

        local i=1
        for p in "${PHASE_IDS[@]}"; do
            local mark="${GRAY}[ ]${NC}"
            [[ "${PHASE_SELECTED[$p]}" == "1" ]] && mark="${GREEN}[✓]${NC}"

            local done_mark=""
            if [[ -n "${PHASE_DONE[$p]:-}" ]]; then
                done_mark=" ${DIM}(installed ${PHASE_DONE[$p]:0:10})${NC}"
            fi

            printf "  ${CYAN}%2d${NC}) %b %-22s ${DIM}%s${NC}%b\n" \
                "$i" "$mark" "${PHASE_NAME[$p]}" "${PHASE_DURATION[$p]}" "$done_mark"
            i=$((i + 1))
        done

        say ""
        say "${DIM}─────────────────────────────────────────────────${NC}"
        say "  ${CYAN}a${NC}) Select all   ${CYAN}n${NC}) Select none   ${CYAN}u${NC}) Unselect installed"
        say "  ${CYAN}r${NC}) Run selected phases   ${CYAN}b${NC}) Back to main menu"
        say ""

        local choice
        read -r -p "  Toggle phase number, or letter: " choice

        case "$choice" in
            [0-9]|[0-9][0-9])
                local idx=$((choice - 1))
                if (( idx >= 0 && idx < ${#PHASE_IDS[@]} )); then
                    local p="${PHASE_IDS[$idx]}"
                    if [[ "${PHASE_SELECTED[$p]}" == "1" ]]; then
                        PHASE_SELECTED[$p]=0
                    else
                        PHASE_SELECTED[$p]=1
                    fi
                fi
                ;;
            a|A) for p in "${PHASE_IDS[@]}"; do PHASE_SELECTED[$p]=1; done ;;
            n|N) for p in "${PHASE_IDS[@]}"; do PHASE_SELECTED[$p]=0; done ;;
            u|U)
                for p in "${PHASE_IDS[@]}"; do
                    if [[ -n "${PHASE_DONE[$p]:-}" ]]; then
                        PHASE_SELECTED[$p]=0
                    fi
                done
                ;;
            r|R) return 0 ;;
            b|B) return 1 ;;
            *) ;;
        esac
    done
}

show_single_phase_menu() {
    print_banner
    say "${BOLD}${WHITE}Run Single Phase${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""

    local i=1
    for p in "${PHASE_IDS[@]}"; do
        local done_mark=""
        if [[ -n "${PHASE_DONE[$p]:-}" ]]; then
            done_mark=" ${GREEN}✓${NC}"
        fi
        printf "  ${CYAN}%2d${NC}) %-22s ${DIM}%s${NC}%b\n" \
            "$i" "${PHASE_NAME[$p]}" "${PHASE_DESC[$p]}" "$done_mark"
        i=$((i + 1))
    done

    say ""
    say "  ${CYAN}b${NC}) Back to main menu"
    say ""

    local choice
    read -r -p "  Choose phase: " choice

    case "$choice" in
        [0-9]|[0-9][0-9])
            local idx=$((choice - 1))
            if (( idx >= 0 && idx < ${#PHASE_IDS[@]} )); then
                # Select only that phase
                for p in "${PHASE_IDS[@]}"; do PHASE_SELECTED[$p]=0; done
                PHASE_SELECTED[${PHASE_IDS[$idx]}]=1
                return 0
            fi
            ;;
        b|B) return 1 ;;
    esac
    return 1
}

show_status() {
    print_banner
    say "${BOLD}${WHITE}Installation Status${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""

    local total=0
    local done_count=0
    for p in "${PHASE_IDS[@]}"; do
        total=$((total + 1))
        if [[ -n "${PHASE_DONE[$p]:-}" ]]; then
            say "  ${GREEN}✓${NC} ${BOLD}${PHASE_NAME[$p]}${NC}  ${DIM}— installed ${PHASE_DONE[$p]}${NC}"
            done_count=$((done_count + 1))
        else
            say "  ${GRAY}○${NC} ${PHASE_NAME[$p]}  ${DIM}— not yet installed${NC}"
        fi
    done

    say ""
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say "  Progress: ${BOLD}${done_count}/${total}${NC} phases complete"
    say ""

    # System info
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        say "  System:   ${PRETTY_NAME}"
    fi
    say "  Kernel:   $(uname -r)"
    say "  Shell:    ${SHELL}"
    say "  Log:      ${LOG_FILE}"
    say "  State:    ${STATE_FILE}"
    say ""

    press_enter
}

show_settings() {
    print_banner
    say "${BOLD}${WHITE}Settings${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""
    say "  ${CYAN}1${NC}) Git name              ${DIM}current: ${GIT_NAME:-<unset>}${NC}"
    say "  ${CYAN}2${NC}) Git email             ${DIM}current: ${GIT_EMAIL:-<unset>}${NC}"
    say "  ${CYAN}3${NC}) ArduPilot directory   ${DIM}current: ${ARDUPILOT_DIR}${NC}"
    say "  ${CYAN}4${NC}) Tools directory       ${DIM}current: ${TOOLS_DIR}${NC}"
    say "  ${CYAN}5${NC}) Projects directory    ${DIM}current: ${PROJECTS_DIR}${NC}"
    say "  ${CYAN}6${NC}) Autonomy tarball path ${DIM}current: ${AUTONOMY_TARBALL}${NC}"
    say "  ${CYAN}7${NC}) Autonomy tarball URL  ${DIM}current: ${AUTONOMY_TARBALL_URL}${NC}"
    say ""
    say "  ${CYAN}b${NC}) Back to main menu"
    say ""

    local choice
    read -r -p "  Edit which setting: " choice

    case "$choice" in
        1) read -r -p "  Git name: " GIT_NAME ;;
        2) read -r -p "  Git email: " GIT_EMAIL ;;
        3) read -r -p "  ArduPilot dir: " ARDUPILOT_DIR ;;
        4) read -r -p "  Tools dir: " TOOLS_DIR ;;
        5) read -r -p "  Projects dir: " PROJECTS_DIR ;;
        6) read -r -p "  Tarball path: " AUTONOMY_TARBALL ;;
        7) read -r -p "  Tarball URL: " AUTONOMY_TARBALL_URL ;;
        b|B) return ;;
    esac
    show_settings
}

show_log() {
    print_banner
    say "${BOLD}${WHITE}Install Log — ${LOG_FILE}${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 50 "$LOG_FILE"
    else
        say "${DIM}  No log file yet — run an install phase to generate one.${NC}"
    fi
    say ""
    press_enter
}

show_about() {
    print_banner
    cat <<EOF
${BOLD}${WHITE}About Hangar${NC}
${DIM}─────────────────────────────────────────────────${NC}

  ${BOLD}Hangar${NC} sets up a complete drone autonomy development
  workstation on Ubuntu: system tools, IDE, ArduPilot SITL,
  ground control stations, and project scaffolding.

  ${BOLD}Version:${NC}    ${HANGAR_VERSION}
  ${BOLD}Author:${NC}     ${HANGAR_AUTHOR}
  ${BOLD}License:${NC}    MIT (open, attribution-only)
  ${BOLD}Source:${NC}     this script is self-contained

  ${BOLD}What it installs:${NC}
    ${CYAN}•${NC} Ubuntu base updates and build tools
    ${CYAN}•${NC} VM guest tools (auto-detected hypervisor)
    ${CYAN}•${NC} Developer tools (git, python, vim, tmux, etc.)
    ${CYAN}•${NC} Visual Studio Code + Python extensions
    ${CYAN}•${NC} QGroundControl ground station
    ${CYAN}•${NC} Mission Planner via Mono
    ${CYAN}•${NC} ArduPilot source + SITL ArduCopter build
    ${CYAN}•${NC} Drone autonomy project scaffold (if available)
    ${CYAN}•${NC} Wireshark for MAVLink debugging

  ${BOLD}Designed for:${NC} Ubuntu 24.04 LTS Desktop
  ${BOLD}Also works on:${NC} Ubuntu 22.04 LTS

  ${BOLD}Re-runnable:${NC} all phases are idempotent and tracked
  in ${STATE_FILE}.

${DIM}─────────────────────────────────────────────────${NC}

${DIM}  Copyright (c) 2026 ${HANGAR_AUTHOR}
  Released under the MIT License — see the script header
  for the full license text.${NC}

EOF
    press_enter
}

# -----------------------------------------------------------------------------
# Helpers used by phases
# -----------------------------------------------------------------------------
ensure_apt() {
    local pkg="$1"
    if dpkg -s "$pkg" &>/dev/null; then
        log "  apt: $pkg already installed"
    else
        log "  apt: installing $pkg"
        # shellcheck disable=SC2024
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$LOG_FILE" 2>&1
    fi
}

ensure_apt_many() {
    local pkgs=("$@")
    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "  apt: installing ${missing[*]}"
        # shellcheck disable=SC2024
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >>"$LOG_FILE" 2>&1
    else
        log "  apt: all ${#pkgs[@]} packages already installed"
    fi
}

# Simple progress spinner for long-running commands
spinner() {
    local pid=$1
    local msg="${2:-Working}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${chars:$i:1}${NC} %s   " "$msg"
        i=$(( (i + 1) % ${#chars} ))
        sleep 0.1
    done
    printf "\r                                                              \r"
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
preflight() {
    print_mini_banner "Preflight checks"

    if [[ "$EUID" -eq 0 ]]; then
        err "Do not run as root. Run as your normal user; sudo will be invoked when needed."
        exit 1
    fi

    if [[ ! -f /etc/os-release ]]; then
        err "Cannot determine OS — /etc/os-release missing"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    info "Detected: $PRETTY_NAME"

    if [[ "${ID:-}" != "ubuntu" ]]; then
        err "This script is for Ubuntu. Detected: ${ID:-unknown}"
        exit 1
    fi

    case "${VERSION_ID:-}" in
        24.04|24.10|22.04) ok "Ubuntu version supported" ;;
        *) warn "Untested Ubuntu version: ${VERSION_ID}. Recommended: 24.04 LTS." ;;
    esac

    step "Caching sudo credentials"
    sudo -v
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

    # Bootstrap minimum tools needed by the rest of preflight and by every phase
    # that follows. A fresh Ubuntu Desktop install does not always include curl.
    # We have to do this BEFORE the network check, because the network check
    # uses curl.
    if ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
        step "Bootstrapping required tools (curl, wget, ca-certificates)"
        # apt-get update can briefly need network too — but it works against
        # the configured apt mirrors over the system network stack, not via
        # curl. If apt-get itself fails, the user has no network at all.
        # shellcheck disable=SC2024
        if ! sudo apt-get update >>"$LOG_FILE" 2>&1; then
            err "apt-get update failed. Check your network connection."
            exit 1
        fi
        # shellcheck disable=SC2024
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                curl wget ca-certificates >>"$LOG_FILE" 2>&1; then
            err "Failed to install curl/wget/ca-certificates. Aborting."
            exit 1
        fi
        ok "Bootstrap tools installed"
    fi

    step "Checking internet connectivity"
    if command -v curl &>/dev/null; then
        if ! curl -fsS --max-time 10 https://github.com -o /dev/null; then
            err "Cannot reach github.com. Check your network."
            exit 1
        fi
    elif command -v wget &>/dev/null; then
        if ! wget -q --timeout=10 --tries=1 -O /dev/null https://github.com; then
            err "Cannot reach github.com. Check your network."
            exit 1
        fi
    else
        err "Neither curl nor wget available, and bootstrap failed."
        exit 1
    fi
    ok "Internet OK"

    local free_gb
    free_gb=$(df -BG "$HOME" | awk 'NR==2 {gsub("G","",$4); print $4}')
    info "Free disk in \$HOME: ${free_gb}G"
    if (( free_gb < 10 )); then
        err "Less than 10 GB free in \$HOME. ArduPilot build needs ~8 GB."
        exit 1
    fi

    ok "Preflight complete"
    sleep 1
}

# -----------------------------------------------------------------------------
# Phase implementations
# -----------------------------------------------------------------------------
phase_system_update() {
    step "Updating apt indexes"
    # shellcheck disable=SC2024
    sudo apt-get update >>"$LOG_FILE" 2>&1

    step "Upgrading installed packages"
    # shellcheck disable=SC2024
    sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y >>"$LOG_FILE" 2>&1

    step "Installing kernel headers and build essentials"
    ensure_apt_many \
        build-essential dkms curl wget ca-certificates \
        software-properties-common apt-transport-https gnupg

    # shellcheck disable=SC2024
    sudo apt-get install -y "linux-headers-$(uname -r)" >>"$LOG_FILE" 2>&1 || \
        warn "Kernel headers for $(uname -r) not available; skipping"
}

phase_vmtools() {
    local virt
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    info "Detected virtualization: $virt"

    case "$virt" in
        vmware)
            step "Installing open-vm-tools for VMware"
            ensure_apt_many open-vm-tools open-vm-tools-desktop
            ok "VMware tools installed — reboot recommended after install"
            ;;
        oracle)
            step "Installing VirtualBox guest additions"
            ensure_apt_many virtualbox-guest-utils virtualbox-guest-x11
            ;;
        microsoft|hyperv)
            step "Installing Hyper-V integration tools"
            ensure_apt_many linux-virtual linux-cloud-tools-virtual linux-tools-virtual
            ;;
        kvm|qemu)
            step "Installing qemu-guest-agent"
            ensure_apt qemu-guest-agent
            ;;
        none)
            warn "No hypervisor detected — running on bare metal? Skipping VM tools."
            ;;
        *)
            warn "Unknown hypervisor: $virt. Skipping VM tools."
            ;;
    esac
}

phase_dev_tools() {
    step "Installing core development tools"
    ensure_apt_many \
        git git-lfs vim nano htop tmux tree jq unzip zip net-tools \
        python3 python3-pip python3-venv python3-dev python3-wheel \
        python3-setuptools ssh rsync

    if [[ -n "$GIT_NAME" ]]; then
        git config --global user.name "$GIT_NAME"
        ok "git user.name set to: $GIT_NAME"
    elif ! git config --global user.name &>/dev/null; then
        warn "GIT_NAME unset. Set later with: git config --global user.name 'Your Name'"
    fi

    if [[ -n "$GIT_EMAIL" ]]; then
        git config --global user.email "$GIT_EMAIL"
        ok "git user.email set to: $GIT_EMAIL"
    elif ! git config --global user.email &>/dev/null; then
        warn "GIT_EMAIL unset. Set later with: git config --global user.email 'you@example.com'"
    fi

    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.editor vim
}

phase_vscode() {
    if command -v code &>/dev/null; then
        ok "VS Code already installed: $(code --version | head -n1)"
        return 0
    fi

    step "Adding Microsoft VS Code apt repository"
    local keyring=/etc/apt/keyrings/packages.microsoft.gpg
    sudo install -d -m 0755 /etc/apt/keyrings
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | sudo tee "$keyring" >/dev/null
    echo "deb [arch=amd64,arm64,armhf signed-by=$keyring] https://packages.microsoft.com/repos/code stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

    # shellcheck disable=SC2024
    sudo apt-get update >>"$LOG_FILE" 2>&1
    ensure_apt code

    step "Installing VS Code extensions"
    local extensions=(
        ms-python.python
        ms-python.vscode-pylance
        charliermarsh.ruff
        ms-python.debugpy
        redhat.vscode-yaml
        tamasfe.even-better-toml
        eamodio.gitlens
    )
    for ext in "${extensions[@]}"; do
        if code --install-extension "$ext" --force >>"$LOG_FILE" 2>&1; then
            log "  vscode ext: $ext installed"
        else
            warn "Failed to install VS Code extension: $ext"
        fi
    done
}

phase_qgc() {
    local qgc_dir="$TOOLS_DIR/qgc"
    local qgc_path="$qgc_dir/QGroundControl.AppImage"

    if [[ -x "$qgc_path" ]]; then
        ok "QGroundControl already installed at $qgc_path"
    else
        step "Downloading QGroundControl AppImage"
        mkdir -p "$qgc_dir"
        (
            cd "$qgc_dir"
            wget -q "https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage" \
                -O QGroundControl.AppImage
            chmod +x QGroundControl.AppImage
        )
    fi

    step "Installing QGC runtime dependencies"
    ensure_apt_many libfuse2 libxcb-cursor0 libxcb-xinerama0 \
        libpulse-dev libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 libxkbcommon-x11-0

    if ! groups "$USER" | grep -q '\bdialout\b'; then
        step "Adding $USER to dialout group"
        sudo usermod -a -G dialout "$USER"
        warn "Log out and back in for dialout group to take effect"
    fi

    local desktop_file="$HOME/.local/share/applications/qgroundcontrol.desktop"
    if [[ ! -f "$desktop_file" ]]; then
        mkdir -p "$(dirname "$desktop_file")"
        cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=QGroundControl
Comment=Ground Control Station for drones
Exec=$qgc_path
Icon=applications-electronics
Terminal=false
Type=Application
Categories=Development;Engineering;
EOF
    fi
}

phase_mission_planner() {
    local mp_dir="$TOOLS_DIR/mission-planner"
    local mp_exe="$mp_dir/MissionPlanner.exe"

    if [[ -f "$mp_exe" ]]; then
        ok "Mission Planner already installed at $mp_dir"
        return 0
    fi

    step "Installing Mono runtime"
    ensure_apt mono-complete

    step "Downloading Mission Planner"
    mkdir -p "$mp_dir"
    (
        cd "$mp_dir"
        wget -q "https://firmware.ardupilot.org/Tools/MissionPlanner/MissionPlanner-latest.zip" \
            -O MissionPlanner-latest.zip
        unzip -q -o MissionPlanner-latest.zip
        rm -f MissionPlanner-latest.zip
    )

    if [[ ! -f "$mp_exe" ]]; then
        warn "Mission Planner extraction looked off — MissionPlanner.exe not found"
        return 0
    fi

    local wrapper="$mp_dir/run-mp.sh"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
# Wrapper to launch Mission Planner with sane Mono settings on Linux
export MONO_WINFORMS_XIM_STYLE=disabled
cd "$mp_dir"
exec mono MissionPlanner.exe "\$@"
EOF
    chmod +x "$wrapper"

    cat > "$HOME/.local/share/applications/mission-planner.desktop" <<EOF
[Desktop Entry]
Name=Mission Planner
Comment=ArduPilot Ground Control Station
Exec=$wrapper
Icon=applications-electronics
Terminal=false
Type=Application
Categories=Development;Engineering;
EOF
}

phase_ardupilot() {
    if [[ -d "$ARDUPILOT_DIR/.git" ]]; then
        ok "ArduPilot already cloned at $ARDUPILOT_DIR"
    else
        step "Cloning ArduPilot to $ARDUPILOT_DIR"
        git clone https://github.com/ArduPilot/ardupilot.git "$ARDUPILOT_DIR" >>"$LOG_FILE" 2>&1
        step "Initializing submodules (~5 min)"
        (cd "$ARDUPILOT_DIR" && git submodule update --init --recursive) >>"$LOG_FILE" 2>&1
    fi

    step "Running ArduPilot prereqs install (10-20 min)"
    if [[ ! -x "$ARDUPILOT_DIR/Tools/environment_install/install-prereqs-ubuntu.sh" ]]; then
        err "Cannot find install-prereqs-ubuntu.sh — repo layout may have changed"
        return 1
    fi
    (cd "$ARDUPILOT_DIR" && Tools/environment_install/install-prereqs-ubuntu.sh -y) >>"$LOG_FILE" 2>&1

    # Source the updated profile to pick up PATH changes
    if [[ -f "$HOME/.profile" ]]; then
        set +u
        # shellcheck disable=SC1090,SC1091
        . "$HOME/.profile" || true
        set -u
    fi

    step "Configuring ArduPilot for SITL"
    (cd "$ARDUPILOT_DIR" && ./waf configure --board sitl) >>"$LOG_FILE" 2>&1

    step "Building ArduCopter for SITL (3-8 min)"
    (cd "$ARDUPILOT_DIR" && ./waf copter) >>"$LOG_FILE" 2>&1

    local sitl_binary="$ARDUPILOT_DIR/build/sitl/bin/arducopter"
    if [[ -x "$sitl_binary" ]]; then
        ok "SITL ArduCopter binary built at $sitl_binary"
    else
        err "SITL build appeared to succeed but binary not found"
        return 1
    fi

    # Clean up shell environment so SITL tools work in every terminal.
    #
    # The ArduPilot prereqs installer writes PATH and venv-activation lines to
    # ~/.profile, but Ubuntu GNOME desktops do NOT source .profile in terminals
    # opened from the GUI — only in login shells. The result: users open a
    # terminal after install and `sim_vehicle.py` is "command not found."
    # We fix this by also writing the relevant lines to .bashrc, where every
    # interactive shell will pick them up.
    fix_ardupilot_shell_env
}

# Ensure ArduPilot's PATH is available in every terminal, and clean up the
# noise the installer leaves behind. Idempotent.
fix_ardupilot_shell_env() {
    step "Fixing shell environment for ArduPilot tools"

    local autotest_path="$ARDUPILOT_DIR/Tools/autotest"
    local completion_path="$ARDUPILOT_DIR/Tools/completion/completion.bash"
    local bashrc="$HOME/.bashrc"
    local profile="$HOME/.profile"
    local marker="# >>> Hangar: ArduPilot shell setup >>>"
    local marker_end="# <<< Hangar: ArduPilot shell setup <<<"

    # 1) De-duplicate ~/.profile. The installer can append the same venv-
    #    activation line multiple times if it runs more than once.
    if [[ -f "$profile" ]]; then
        local tmpfile
        tmpfile=$(mktemp)
        awk '!seen[$0]++' "$profile" > "$tmpfile" && mv "$tmpfile" "$profile"
        log "  Deduplicated ~/.profile"
    fi

    # 2) Disable auto-activation of the ArduPilot venv on shell startup.
    #    Having it activate automatically in every terminal interferes with
    #    other Python projects (the user's drone-autonomy venv, for example).
    #    The user can still activate it explicitly when working on ArduPilot
    #    development.
    if [[ -f "$profile" ]] && grep -q "source.*venv-ardupilot/bin/activate" "$profile"; then
        sed -i 's|^source.*venv-ardupilot/bin/activate|# &  # disabled by Hangar — activate manually when needed|' "$profile"
        log "  Disabled auto-activation of venv-ardupilot in ~/.profile"
    fi

    # 3) Make ArduPilot tools available in every interactive shell.
    #    Add a clearly-marked block to ~/.bashrc.
    if [[ ! -f "$bashrc" ]] || ! grep -qF "$marker" "$bashrc"; then
        {
            echo ""
            echo "$marker"
            echo "# Added by Hangar v${HANGAR_VERSION} to ensure ArduPilot tools"
            echo "# are on PATH in every terminal (Ubuntu Desktop does not"
            echo "# source ~/.profile for GUI-launched terminals)."
            echo "if [ -d \"$autotest_path\" ] && [[ \":\$PATH:\" != *\":$autotest_path:\"* ]]; then"
            echo "    export PATH=\"$autotest_path:\$PATH\""
            echo "fi"
            echo "if [ -f \"$completion_path\" ]; then"
            echo "    # shellcheck disable=SC1090"
            echo "    source \"$completion_path\""
            echo "fi"
            echo "$marker_end"
        } >> "$bashrc"
        ok "Added ArduPilot PATH to ~/.bashrc"
    else
        log "  ArduPilot PATH already present in ~/.bashrc"
    fi
}

phase_autonomy_project() {
    mkdir -p "$PROJECTS_DIR"
    local project_dir="$PROJECTS_DIR/drone-autonomy"

    if [[ -d "$project_dir" ]]; then
        ok "drone-autonomy project already exists at $project_dir"
    else
        # Locate the tarball. Lookup order:
        #   1. Same directory as this script (works when user cloned the repo)
        #   2. The $AUTONOMY_TARBALL path (typically ~/Downloads, for backward compat)
        #   3. Download from $AUTONOMY_TARBALL_URL as a last resort
        local bundled_tarball="$HANGAR_SCRIPT_DIR/drone-autonomy-starter.tar.gz"
        local effective_tarball=""

        if [[ -f "$bundled_tarball" ]]; then
            info "Found bundled tarball next to script: $bundled_tarball"
            effective_tarball="$bundled_tarball"
        elif [[ -f "$AUTONOMY_TARBALL" ]]; then
            info "Using tarball at: $AUTONOMY_TARBALL"
            effective_tarball="$AUTONOMY_TARBALL"
        else
            step "No local tarball found, downloading from GitHub"
            info "Source: $AUTONOMY_TARBALL_URL"
            mkdir -p "$(dirname "$AUTONOMY_TARBALL")"

            local download_ok=0
            if command -v curl &>/dev/null; then
                # shellcheck disable=SC2024
                if curl -fsSL --retry 3 --max-time 60 \
                        -o "$AUTONOMY_TARBALL" "$AUTONOMY_TARBALL_URL" \
                        >>"$LOG_FILE" 2>&1; then
                    download_ok=1
                fi
            fi
            if [[ "$download_ok" -eq 0 ]] && command -v wget &>/dev/null; then
                # shellcheck disable=SC2024
                if wget -q --tries=3 --timeout=60 \
                        -O "$AUTONOMY_TARBALL" "$AUTONOMY_TARBALL_URL" \
                        >>"$LOG_FILE" 2>&1; then
                    download_ok=1
                fi
            fi

            if [[ "$download_ok" -ne 0 ]] && [[ -s "$AUTONOMY_TARBALL" ]]; then
                ok "Downloaded to $AUTONOMY_TARBALL"
                effective_tarball="$AUTONOMY_TARBALL"
            else
                rm -f "$AUTONOMY_TARBALL"
                warn "Failed to download starter kit. Skipping autonomy project setup."
                warn "  - Check the URL: $AUTONOMY_TARBALL_URL"
                warn "  - Or place the tarball next to hangar.sh and re-run this phase."
                return 0
            fi
        fi

        # Validate the tarball before unpacking — catches HTML 404 pages
        # that got saved as if they were tarballs.
        if ! tar -tzf "$effective_tarball" >/dev/null 2>&1; then
            err "File at $effective_tarball is not a valid gzipped tar archive."
            err "Inspect it manually — it may be an HTML error page."
            return 1
        fi

        step "Unpacking $effective_tarball to $PROJECTS_DIR"
        tar xzf "$effective_tarball" -C "$PROJECTS_DIR"

        if [[ ! -d "$project_dir" ]]; then
            err "Tarball extracted but $project_dir not found."
            err "The archive may have a different layout than expected."
            return 1
        fi
    fi

    if [[ ! -d "$project_dir/.venv" ]]; then
        step "Creating Python virtual environment"
        python3 -m venv "$project_dir/.venv"
    fi

    step "Installing project dependencies"
    set +u
    # shellcheck disable=SC1091
    source "$project_dir/.venv/bin/activate"
    set -u
    pip install --quiet --upgrade pip >>"$LOG_FILE" 2>&1
    (cd "$project_dir" && pip install --quiet -e ".[dev]") >>"$LOG_FILE" 2>&1
    set +u
    deactivate
    set -u

    step "Running test suite"
    if (cd "$project_dir" && .venv/bin/python -m pytest -q) >>"$LOG_FILE" 2>&1; then
        ok "Tests pass"
    else
        warn "Tests failed — see $LOG_FILE"
    fi
}

phase_wireshark() {
    step "Installing Wireshark"
    echo "wireshark-common wireshark-common/install-setuid boolean true" | \
        sudo debconf-set-selections
    # shellcheck disable=SC2024
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wireshark tshark >>"$LOG_FILE" 2>&1

    if ! groups "$USER" | grep -q '\bwireshark\b'; then
        step "Adding $USER to wireshark group"
        sudo usermod -a -G wireshark "$USER"
        warn "Log out and back in for wireshark group to take effect"
    fi
}

phase_finalize() {
    step "Disabling UFW firewall (not needed on dev VM)"
    # shellcheck disable=SC2024
    sudo ufw disable >>"$LOG_FILE" 2>&1 || true

    print_mini_banner "Installed versions"
    {
        say "  ${BOLD}Ubuntu:${NC}    $(lsb_release -ds 2>/dev/null || echo 'unknown')"
        say "  ${BOLD}Kernel:${NC}    $(uname -r)"
        say "  ${BOLD}Python:${NC}    $(python3 --version)"
        say "  ${BOLD}Git:${NC}       $(git --version)"
        command -v code &>/dev/null && say "  ${BOLD}VS Code:${NC}   $(code --version | head -n1)"
        command -v mono &>/dev/null && say "  ${BOLD}Mono:${NC}      $(mono --version | head -n1)"
        [[ -x "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]] && \
            say "  ${BOLD}SITL:${NC}      $ARDUPILOT_DIR/build/sitl/bin/arducopter"
        [[ -x "$TOOLS_DIR/qgc/QGroundControl.AppImage" ]] && \
            say "  ${BOLD}QGC:${NC}       $TOOLS_DIR/qgc/QGroundControl.AppImage"
        [[ -f "$TOOLS_DIR/mission-planner/MissionPlanner.exe" ]] && \
            say "  ${BOLD}MP:${NC}        $TOOLS_DIR/mission-planner/run-mp.sh"
    }
}

# -----------------------------------------------------------------------------
# Phase runner
# -----------------------------------------------------------------------------
run_selected_phases() {
    # Build list of phases to run
    local to_run=()
    for p in "${PHASE_IDS[@]}"; do
        [[ "${PHASE_SELECTED[$p]}" == "1" ]] && to_run+=("$p")
    done

    if (( ${#to_run[@]} == 0 )); then
        print_mini_banner "Nothing selected"
        warn "No phases selected. Returning to menu."
        press_enter
        return
    fi

    print_banner
    say "${BOLD}${WHITE}Ready to install${NC}"
    say "${DIM}─────────────────────────────────────────────────${NC}"
    say ""
    say "  Phases that will run:"
    for p in "${to_run[@]}"; do
        local done_mark=""
        [[ -n "${PHASE_DONE[$p]:-}" ]] && done_mark=" ${YELLOW}(reinstall)${NC}"
        say "    ${CYAN}•${NC} ${BOLD}${PHASE_NAME[$p]}${NC}${done_mark}"
    done
    say ""
    say "  Log file:  ${LOG_FILE}"
    say ""

    if ! confirm "Proceed?"; then
        return
    fi

    preflight

    local failed=()
    for p in "${to_run[@]}"; do
        print_mini_banner "Phase: ${PHASE_NAME[$p]}"
        if "phase_$p"; then
            mark_done "$p"
            ok "Phase '${PHASE_NAME[$p]}' complete"
        else
            failed+=("$p")
            err "Phase '${PHASE_NAME[$p]}' failed — see $LOG_FILE"
        fi
        sleep 1
    done

    print_banner
    if (( ${#failed[@]} == 0 )); then
        say "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        say "${BOLD}${GREEN}║                                                           ║${NC}"
        say "${BOLD}${GREEN}║       All selected phases completed successfully!         ║${NC}"
        say "${BOLD}${GREEN}║                                                           ║${NC}"
        say "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        say ""
        say "  ${BOLD}Next steps:${NC}"
        say "    ${CYAN}1.${NC} Open a ${BOLD}new terminal${NC} (or run ${DIM}source ~/.bashrc${NC}) to pick up PATH updates"
        say "    ${CYAN}2.${NC} Log out and back in once (for ${DIM}dialout${NC} and ${DIM}wireshark${NC} group memberships)"
        say "    ${CYAN}3.${NC} Take a VM snapshot (call it 'clean dev environment')"
        say "    ${CYAN}4.${NC} Launch SITL: ${DIM}sim_vehicle.py -v ArduCopter --console --map --out=udp:127.0.0.1:14551${NC}"
        say "    ${CYAN}5.${NC} Run the smoke test: ${DIM}cd $PROJECTS_DIR/drone-autonomy && source .venv/bin/activate && python scripts/sitl_test_takeoff.py${NC}"
    else
        say "${BOLD}${YELLOW}Completed with errors${NC}"
        say ""
        say "  Failed phases:"
        for p in "${failed[@]}"; do
            say "    ${RED}✗${NC} ${PHASE_NAME[$p]}"
        done
        say ""
        say "  Check the log for details: ${LOG_FILE}"
    fi
    say ""
    press_enter
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------
init_log() {
    {
        echo "================================================================"
        echo "Hangar v${HANGAR_VERSION} run started: $(date)"
        echo "  User:        $USER"
        echo "  Host:        $(hostname)"
        echo "  Pwd:         $(pwd)"
        echo "================================================================"
    } >> "$LOG_FILE"
}

main() {
    init_log
    load_state

    while true; do
        show_main_menu
        case "${MENU_CHOICE,,}" in
            1)
                # Quick install — everything
                for p in "${PHASE_IDS[@]}"; do PHASE_SELECTED[$p]=1; done
                run_selected_phases
                ;;
            2)
                # Custom — pick phases
                if show_phase_picker; then
                    run_selected_phases
                fi
                ;;
            3)
                # Single phase
                if show_single_phase_menu; then
                    run_selected_phases
                fi
                ;;
            4) show_status ;;
            5) show_settings ;;
            6) show_log ;;
            7) show_about ;;
            q|quit|exit)
                print_banner
                say "${DIM}  Cleared for takeoff. Good luck.${NC}"
                say ""
                exit 0
                ;;
            *)
                # Unknown choice; loop back
                ;;
        esac
    done
}

main "$@"
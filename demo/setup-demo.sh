#!/usr/bin/env bash
# Demo version of setup.sh — uses real gum prompts with stubbed installs.
# Keep in sync with setup.sh when prompts or options change.
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

spinner() {
    local msg="$1" duration="${2:-0.8}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local end=$((SECONDS + ${duration%.*} + 1))
    while [ $SECONDS -lt $end ]; do
        for (( i=0; i<${#chars}; i++ )); do
            printf "\r  ${CYAN}${chars:$i:1}${RESET} %s" "$msg"
            sleep 0.08
        done
    done
}

# --- Simulated install phase ---
clear
echo -e "> curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/SquareBox/main/install.sh | bash"
echo
echo "Cloning squarebox..."
sleep 0.4
echo -e "${BOLD}Building image...${RESET}"
sleep 0.5
for i in 1 2 3 4 5 6 7; do
    echo "Step ${i}/7 : ✓"
    sleep 0.2
done
echo
echo -e "${GREEN}✓ Image built successfully${RESET}"
sleep 0.2
echo -e "${GREEN}✓ Container created${RESET}"
sleep 0.3
echo "Entering container..."
sleep 0.6

# --- Real setup.sh UI (gum prompts) ---
echo

# Header — exact same command as setup.sh
gum style --border double --padding "0 2" --border-foreground 208 "squarebox setup"
echo

# Git identity (pre-filled)
sleep 0.3
echo -e "Git name: ${BOLD}dev${RESET}"
sleep 0.2
echo -e "Git email: ${BOLD}dev@example.com${RESET}"
echo

# GitHub CLI (already authenticated)
sleep 0.3
echo "GitHub CLI: already authenticated"

# AI assistant — real gum choose (same as setup.sh)
echo
ai_label=$(gum choose --header "Choose your AI coding assistant:" \
    --cursor.foreground 208 --header.foreground 208 --selected.foreground 208 \
    "Claude Code" "OpenCode" "Both") || true

echo "Installing Claude Code..."
spinner "Downloading claude..." 1
printf "\r  ${GREEN}✓${RESET} Claude Code installed      \n"
sleep 0.3

# Editors — real gum choose (same as setup.sh)
echo
echo "Nano is always available as the default editor."
selected=$(gum choose --no-limit \
    --header "Select text editors to install (space=toggle, enter=confirm):" \
    --cursor.foreground 208 --header.foreground 208 --selected.foreground 208 \
    "micro  — modern, intuitive terminal editor" \
    "edit   — terminal text editor (Microsoft)" \
    "fresh  — modern terminal text editor" \
    "helix  — modal editor (Kakoune-inspired)" \
    "nvim   — Neovim") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    echo "Installing ${name}..."
    sleep 0.2
    echo -e "  ${GREEN}✓${RESET} ${name} installed"
    sleep 0.15
done <<< "$selected"
sleep 0.3

# Terminal multiplexer — real gum choose (same as setup.sh)
echo
selected=$(gum choose --no-limit \
    --header "Select terminal multiplexer (space=toggle, enter=confirm, or enter to skip):" \
    --cursor.foreground 208 --header.foreground 208 --selected.foreground 208 \
    "tmux    — classic terminal multiplexer" \
    "zellij  — friendly terminal workspace") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    echo "Installing ${name}..."
    spinner "Installing ${name}..." 0.8
    printf "\r  ${GREEN}✓${RESET} ${name} installed            \n"
    sleep 0.15
done <<< "$selected"
sleep 0.3

# SDKs — real gum choose (same as setup.sh)
echo
selected=$(gum choose --no-limit \
    --header "Select SDKs to install (space=toggle, enter=confirm):" \
    --cursor.foreground 208 --header.foreground 208 --selected.foreground 208 \
    "Node.js" "Python" "Go" ".NET") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        "Node.js")
            echo "Installing Node.js (via nvm)..."
            spinner "Installing Node.js LTS..." 1
            printf "\r  ${GREEN}✓${RESET} Node.js v22 (LTS) installed\n"
            ;;
        "Python")
            echo "Installing Python (via uv)..."
            spinner "Installing uv..." 0.8
            printf "\r  ${GREEN}✓${RESET} uv installed                \n"
            ;;
        "Go")
            echo "Installing Go..."
            spinner "Installing Go..." 0.8
            printf "\r  ${GREEN}✓${RESET} Go installed                \n"
            ;;
        ".NET")
            echo "Installing .NET..."
            spinner "Installing .NET..." 0.8
            printf "\r  ${GREEN}✓${RESET} .NET installed              \n"
            ;;
    esac
    sleep 0.15
done <<< "$selected"

echo
echo "🟧📦 You're in the box."

# MOTD
echo
printf '\e[1;38;5;208m'
toilet -f smblock --metal "squarebox"
printf '\e[0m'
printf '\e[38;5;172m  %s\e[0m\n\n' "$(date '+%A, %B %d %Y  %H:%M')  |  Node 22.16.0, Python 3.12.3"

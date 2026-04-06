#!/usr/bin/env bash
# Simulates the SquareBox install + first-run experience for VHS recording.
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# Clear screen and re-print the curl command as if it was typed
clear
echo -e "> curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/SquareBox/main/install.sh | bash"

# --- Install phase ---
echo
echo -e "${BOLD}Cloning SquareBox...${RESET}"
sleep 0.6
echo "Cloning into ~/squarebox..."
sleep 0.5
echo -e "${BOLD}Building Docker image...${RESET}"
sleep 0.7

for i in 1 2 3 4 5 6 7; do
    echo "Step ${i}/7 : ✓"
    sleep 0.35
done

echo
echo -e "${GREEN}✓ Image built successfully${RESET}"
sleep 0.3
echo -e "${GREEN}✓ Container created${RESET}"
echo
echo -e "${BOLD}Aliases added:${RESET}  sqrbx  sqrbx-rebuild"
sleep 0.6
echo "Entering container..."
sleep 1.0

# --- First-run setup phase ---
echo

echo -e "${MAGENTA}╔════════════════════╗${RESET}"
echo -e "${MAGENTA}║${RESET}  ${BOLD}SquareBox Setup${RESET}  ${MAGENTA}║${RESET}"
echo -e "${MAGENTA}╚════════════════════╝${RESET}"
echo

sleep 0.6
echo -e "Git name: ${BOLD}dev${RESET}"
sleep 0.5
echo -e "Git email: ${BOLD}dev@example.com${RESET}"
echo

sleep 0.6
echo "Logging into GitHub..."
sleep 0.8
echo -e "${GREEN}✓${RESET} Logged in to github.com as ${BOLD}dev${RESET}"
echo

# AI assistant
sleep 0.7
echo -e "${DIM}Choose your AI coding assistant:${RESET}"
sleep 0.5
echo -e "  ${BOLD}${GREEN}> Claude Code${RESET}"
echo -e "  ${DIM}  OpenCode${RESET}"
echo -e "  ${DIM}  Both${RESET}"
sleep 1.0
echo
echo "Installing Claude Code..."
sleep 0.4

chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
for i in $(seq 1 12); do
    idx=$(( (i - 1) % ${#chars} ))
    printf "\r  ${CYAN}${chars:$idx:1}${RESET} Downloading claude..."
    sleep 0.12
done
printf "\r  ${GREEN}✓${RESET} Claude Code installed      \n"
sleep 0.5

# Editors
echo
echo -e "${DIM}Nano is always available as the default editor.${RESET}"
echo -e "${DIM}Select text editors to install (space=toggle, enter=confirm):${RESET}"
sleep 0.5
echo -e "  ${GREEN}✓${RESET} ${BOLD}micro${RESET}  — modern, intuitive terminal editor"
echo -e "  ${GREEN}✓${RESET} ${BOLD}helix${RESET}  — modal editor (Kakoune-inspired)"
echo -e "    ${DIM}edit   — terminal text editor (Microsoft)${RESET}"
echo -e "    ${DIM}fresh  — modern terminal text editor${RESET}"
echo -e "    ${DIM}nvim   — Neovim${RESET}"
sleep 1.0
echo
echo "Installing Micro v2.0.15..."
sleep 0.35
echo -e "  ${GREEN}✓${RESET} Micro installed"
sleep 0.3
echo "Installing Helix v25.07.1..."
sleep 0.35
echo -e "  ${GREEN}✓${RESET} Helix installed"
sleep 0.5

# SDKs
echo
echo -e "${DIM}Select SDKs to install (space=toggle, enter=confirm):${RESET}"
sleep 0.5
echo -e "  ${GREEN}✓${RESET} ${BOLD}Node.js${RESET}"
echo -e "  ${GREEN}✓${RESET} ${BOLD}Python${RESET}"
echo -e "    ${DIM}Go${RESET}"
echo -e "    ${DIM}.NET${RESET}"
sleep 1.0
echo
echo "Installing Node.js (via nvm v0.40.3)..."
sleep 0.3
for i in $(seq 1 8); do
    idx=$(( (i - 1) % ${#chars} ))
    printf "\r  ${CYAN}${chars:$idx:1}${RESET} Installing Node.js LTS..."
    sleep 0.12
done
printf "\r  ${GREEN}✓${RESET} Node.js v22 (LTS) installed\n"
sleep 0.3
echo "Installing Python (via uv)..."
sleep 0.3
for i in $(seq 1 6); do
    idx=$(( (i - 1) % ${#chars} ))
    printf "\r  ${CYAN}${chars:$idx:1}${RESET} Installing uv..."
    sleep 0.12
done
printf "\r  ${GREEN}✓${RESET} uv installed                \n"
sleep 0.5

echo
echo -e "${GREEN}${BOLD}Done. Ready to go.${RESET}"

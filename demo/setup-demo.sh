#!/usr/bin/env bash
# Demo version of setup.sh — uses real gum prompts with stubbed installs.
# Keep in sync with setup.sh when prompts or options change.
set -euo pipefail

# Simulated run_with_spinner: shows gum spinner briefly, then green checkmark
run_with_spinner() {
    local title="$1"
    local duration="${2:-0.8}"
    gum spin --spinner dot --title "$title" -- sleep "$duration"
    gum style --foreground 2 "✓ ${title%...}"
}

section_header() {
    gum style --foreground 212 --bold "$1"
}

# --- Simulated container creation ---
clear
echo "Creating container..."
sleep 0.5

# --- Header ---
echo
gum style --border double --padding "0 2" --border-foreground 208 "squarebox setup"
echo

# GitHub CLI (already authenticated)
sleep 0.3
echo "GitHub CLI: already authenticated"

# AI assistant — real gum choose (same as setup.sh)
echo
section_header "AI Coding Assistants"
selected=$(gum choose --no-limit \
    --header "Select AI coding assistants (space=toggle, enter=confirm):" \
    "Claude Code" "GitHub Copilot CLI" "Google Gemini CLI" \
    "OpenAI Codex CLI" "OpenCode") || true

node_installed=false
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        "Claude Code")
            run_with_spinner "Installing Claude Code..." 0.8
            ;;
        "GitHub Copilot CLI"|"Google Gemini CLI"|"OpenAI Codex CLI")
            if ! $node_installed; then
                run_with_spinner "Installing Node.js (via nvm v0.40.3)..." 1
                node_installed=true
            fi
            run_with_spinner "Installing ${line}..." 0.8
            ;;
        "OpenCode")
            run_with_spinner "Installing OpenCode v1.3.15..." 0.8
            ;;
    esac
done <<< "$selected"

# Editors — real gum choose (same as setup.sh)
echo
section_header "Text Editors"
echo "Nano is always available as the default editor."
selected=$(gum choose --no-limit \
    --header "Select text editors to install:" \
    "micro" "edit" "fresh" "helix" "nvim") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        micro) run_with_spinner "Installing Micro v2.0.15..." 0.6 ;;
        edit)  run_with_spinner "Installing Edit v1.2.1..." 0.6 ;;
        fresh) run_with_spinner "Installing Fresh v0.2.21..." 0.6 ;;
        helix) run_with_spinner "Installing Helix v25.07.1..." 0.6 ;;
        nvim)  run_with_spinner "Installing Neovim v0.12.0..." 0.6 ;;
    esac
done <<< "$selected"

# Terminal multiplexer — real gum choose (same as setup.sh)
echo
section_header "Terminal Multiplexer"
selected=$(gum choose --no-limit \
    --header "Select terminal multiplexer:" \
    "tmux" "zellij") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        tmux)   run_with_spinner "Installing tmux..." 0.6 ;;
        zellij) run_with_spinner "Installing Zellij v0.44.0..." 0.6 ;;
    esac
done <<< "$selected"

# SDKs — real gum choose (same as setup.sh)
echo
section_header "SDKs"
selected=$(gum choose --no-limit \
    --header "Select SDKs to install:" \
    "Node.js" "Python" "Go" ".NET") || true

while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        "Node.js")
            if $node_installed; then
                echo "Node.js already installed, skipping."
            else
                run_with_spinner "Installing Node.js (via nvm v0.40.3)..." 1
                node_installed=true
            fi
            ;;
        "Python") run_with_spinner "Installing Python (via uv)..." 0.8 ;;
        "Go")     run_with_spinner "Installing Go go1.26.1..." 0.8 ;;
        ".NET")   run_with_spinner "Installing .NET..." 0.8 ;;
    esac
done <<< "$selected"

echo
gum style --border double --padding "0 2" --border-foreground 212 "🟧📦 You're in the box."

# MOTD
echo
printf '\e[1;38;5;208m'
toilet -f smblock --metal "squarebox"
printf '\e[0m'
printf '\e[38;5;172m  %s\e[0m\n' "$(date '+%A, %B %d %Y  %H:%M')"
printf '\e[38;5;172m  Node 24.14.1 ◆ Python uv 0.11.3\e[0m\n'
printf '\e[38;5;172m  Go 1.26.1 ◆ .NET 10.0.201\e[0m\n'

#!/usr/bin/env bash
# Self-playing squarebox loop for the website card — no input required.
# Recorded in cool-retro-term by demo/record-website.sh; runnable on its own
# in any terminal to preview. Sized for a ~46x22 terminal.
#
# SQUAREBOX_DEMO_LOOPS  number of loops to play (default 1, 0 = forever)
# SQUAREBOX_DEMO_MARK   file that receives a timestamp at each loop start,
#                       used by the recorder to cut exactly one cycle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

loops="${SQUAREBOX_DEMO_LOOPS:-1}"
mark="${SQUAREBOX_DEMO_MARK:-}"
version="${SQUAREBOX_DEMO_VERSION:-$(
    git -C "$REPO_DIR" tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null |
        grep -v -- - | head -n1
)}"

host_prompt() {
    printf '\e[38;5;245m~/projects\e[0m \e[1m$\e[0m '
}

type_out() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        printf '%s' "${text:i:1}"
        sleep 0.08
    done
}

section() {
    gum style --foreground 208 --bold "$1"
}

# Simulated install: brief spinner, then a checkmark line in its place.
installed() {
    gum spin --spinner dot --title "$1" -- sleep "${2:-0.25}"
    printf '\e[32m✓\e[0m %s\n' "$1"
}

boxed() {
    gum style --border double --padding "0 2" --border-foreground 208 "$1"
}

play_once() {
    host_prompt
    sleep 0.8
    type_out "squarebox"
    sleep 0.3
    echo

    boxed "squarebox setup"
    sleep 0.3
    section "AI assistants"
    installed "Claude Code" 0.35
    installed "OpenAI Codex CLI"
    section "Editors"
    installed "Helix"
    installed "Neovim (LazyVim)"
    section "TUI tools"
    installed "lazygit"
    installed "yazi"
    section "SDKs (via mise)"
    installed "Node.js" 0.35
    installed "Python"
    boxed "All boxed up"
    sleep 0.9

    # MOTD, as motd.sh prints it inside the Box, centred vertically. The
    # "future" font reads better than motd.sh's smblock through the CRT shader.
    clear
    local pad=$((($(tput lines) - 10) / 2)) i
    for ((i = 0; i < pad; i++)); do echo; done
    printf '\e[1;38;5;208m'
    toilet -f future --metal "squarebox" | sed 's/^/  /'
    printf '\e[0m'
    printf "\e[38;5;208m  You're in the box.\e[0m"
    [ -n "$version" ] && printf '\e[38;5;245m  (%s)\e[0m' "$version"
    echo
    printf '\e[38;5;245m  Node 22 ◆ Python 3.13 ◆ Go 1.25\e[0m\n'
    printf '\e[38;5;208m  ✦ sqrbx-help\e[0m\e[38;5;245m — commands, shortcuts\e[0m\n'
    echo
    printf '\e[1;36m/workspace\e[0m on \e[1;35mmain\e[0m\n'
    printf '\e[1;32m❯\e[0m '
    sleep 2.4
    type_out "exit"
    sleep 0.3
    clear
}

printf '\e[?25h'
clear
n=0
while [ "$loops" -eq 0 ] || [ "$n" -lt "$loops" ]; do
    # Each cycle starts and ends on the same frame: a cleared screen with the
    # host prompt, so one cycle loops seamlessly.
    [ -n "$mark" ] && date +%s.%N >> "$mark"
    play_once
    n=$((n + 1))
done
host_prompt

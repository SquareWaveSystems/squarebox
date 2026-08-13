#!/usr/bin/env bash
set -euo pipefail

# sqrbx-help — list squarebox commands and handy keyboard shortcuts.
#
# Usage:
#   sqrbx-help        Show this overview

# Colors (ANSI-C quoting embeds real ESC bytes so heredocs render them)
BOLD=$'\033[1m'
DIM=$'\033[2m'
ORANGE=$'\033[38;5;208m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

# Print a command row only if the command is on PATH.
cmd_row() {
	local name="$1" desc="$2"
	if command -v "$name" >/dev/null 2>&1; then
		printf "  ${CYAN}%-14s${RESET} %s\n" "$name" "$desc"
	fi
}

cat <<-EOF

	${ORANGE}${BOLD}🟧📦 squarebox${RESET} — containerized dev environment

	${BOLD}Commands:${RESET}
EOF

	cmd_row sqrbx-setup  "Re-run the setup wizard to add/change tools (--list, --help)"
	cmd_row sqrbx-update "Update installed tool binaries in-place from upstream"
	cmd_row sqrbx-help   "Show this overview"

cat <<-EOF

	${BOLD}Keyboard shortcuts (Bash):${RESET}
	  ${CYAN}Ctrl+R${RESET}         Fuzzy-search command history (fzf)
	  ${CYAN}Ctrl+T${RESET}         Fuzzy-find a file/dir, paste path on the command line (fzf)
	  ${CYAN}Alt+C${RESET}          Fuzzy-find a subdirectory and cd into it (fzf)
	  ${CYAN}**<Tab>${RESET}        Fuzzy-complete the current word, e.g. \`vim **<Tab>\` (fzf)

	${BOLD}Navigation:${RESET}
	  ${CYAN}z <part>${RESET}       Jump to a frecent directory by partial name (zoxide)
	  ${CYAN}zi <part>${RESET}      Same, but pick interactively from matches (zoxide)
	  ${CYAN}.. ... ....${RESET}    Up one / two / three directories

	${BOLD}Aliases:${RESET}
	  ${CYAN}ls ll lt${RESET}       Listings via eza (icons, tree, git)
	  ${CYAN}cat${RESET}            Syntax-highlighted output via bat
	  ${CYAN}ff / eff${RESET}       fzf file picker / open the picked file in \$EDITOR
	  ${CYAN}g gcm gcam${RESET}     git / git commit -m / git commit -a -m

	${DIM}Docs: https://github.com/SquareWaveSystems/squarebox${RESET}

EOF

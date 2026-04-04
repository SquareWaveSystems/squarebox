#!/usr/bin/env bash
set -euo pipefail

echo "=== TUI Devbox First-Run Setup ==="
echo

# Git identity
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
	read -rp "Git name: " name
	git config --global user.name "$name"
fi

if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
	read -rp "Git email: " email
	git config --global user.email "$email"
fi

# GitHub CLI
if ! gh auth status &>/dev/null; then
	echo
	echo "Logging into GitHub..."
	gh auth login
fi

echo
echo "Done. Ready to go."

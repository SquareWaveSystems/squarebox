#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
assert() { if "$@"; then ok "$*"; else not_ok "$*"; fi; }

assert grep -q 'npm install -g --silent @github/copilot' "$ROOT/setup.sh"
assert grep -q 'ensure_node_major_for_npm 22' "$ROOT/setup.sh"
if grep -Eq '@githubnext|github-copilot-cli' "$ROOT/setup.sh"; then
	not_ok "deprecated Copilot package and command are absent"
else
	ok "deprecated Copilot package and command are absent"
fi

assert grep -q 'sudo -n apt-mark hold tzdata' "$ROOT/setup.sh"
assert grep -q 'sudo -n apt-get update' "$ROOT/setup.sh"
assert grep -q 'DEBIAN_FRONTEND=noninteractive sudo -n apt-get install' "$ROOT/setup.sh"
assert grep -q '/usr/bin/apt-mark' "$ROOT/Dockerfile"
assert grep -q 'env_keep += "DEBIAN_FRONTEND"' "$ROOT/Dockerfile"
assert grep -Fq $'\ttzdata \\' "$ROOT/Dockerfile"
assert grep -Fq $'\txz-utils \\' "$ROOT/Dockerfile"
assert grep -Fq '/usr/bin/mv ^-fT -- /usr/local/bin/\.' "$ROOT/Dockerfile"
assert grep -Fq '/usr/bin/rm ^-f -- /usr/local/bin/\.' "$ROOT/Dockerfile"
assert grep -q 'visudo -cf /etc/sudoers.d/dev' "$ROOT/Dockerfile"
assert grep -q 'rm -f /etc/apt/sources.list.d/github-cli.list' "$ROOT/Dockerfile"
assert grep -q 'COPY checksums.txt /usr/local/lib/squarebox/checksums.txt' "$ROOT/Dockerfile"

if grep -Eq 'sqrbx-learn|sqrbx-agent-tool-log|should_run learn' "$ROOT/Dockerfile" "$ROOT/setup.sh" "$ROOT/dotfiles/bashrc"; then
	not_ok "disabled learn command and hook are absent from the default image/setup path"
else
	ok "disabled learn command and hook are absent from the default image/setup path"
fi

assert grep -q '\$HOME/.squarebox-gh-skip' "$ROOT/scripts/squarebox-setup.sh"
assert grep -q -- '--reconcile-box' "$ROOT/scripts/squarebox-entrypoint.sh"
assert grep -q 'SQUAREBOX_STATE_DIR' "$ROOT/setup.sh"
assert grep -q 'install_helix' "$ROOT/setup.sh"
assert grep -Fq 'installed_editors+=("hx")' "$ROOT/setup.sh"
assert grep -Fq 'committed_editors+=("helix")' "$ROOT/setup.sh"
fallback_editor_text='Nano is always available and remains the fallback default unless you choose an installed editor instead.'
if [ "$(grep -Fc "$fallback_editor_text" "$ROOT/setup.sh")" -eq 2 ] \
	&& grep -Fq "$fallback_editor_text" "$ROOT/demo/setup-demo.sh" \
	&& ! grep -Fq 'Nano is always available as the default editor.' \
		"$ROOT/setup.sh" "$ROOT/demo/setup-demo.sh"; then
	ok "setup and demo describe Nano as the fallback default"
else
	not_ok "setup and demo describe Nano as the fallback default"
fi

# Regression: the configured git identity must stay visible after gh auth
# setup-git creates ~/.gitconfig — `git config --global` stops consulting the
# XDG file once ~/.gitconfig exists, so every identity reader needs the
# explicit XDG-file fallback.
assert grep -Fq 'git config --file "$HOME/.config/git/config" user.name' "$ROOT/scripts/squarebox-setup.sh"
assert grep -Fq 'git config --file "$HOME/.config/git/config" user.email' "$ROOT/scripts/squarebox-setup.sh"
assert grep -Fq 'git config --file "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" user.name' "$ROOT/install.sh"
_id_fn=$(sed -n '/^current_git_identity() {/,/^}/p' "$ROOT/setup.sh")
_id_home=$(mktemp -d)
mkdir -p "$_id_home/.config/git"
printf '[user]\n\tname = XDG Name\n' >"$_id_home/.config/git/config"
printf '[credential]\n\thelper = x\n' >"$_id_home/.gitconfig"
if [ -n "$_id_fn" ] \
	&& [ "$(env -u XDG_CONFIG_HOME HOME="$_id_home" bash -c "$_id_fn"$'\ncurrent_git_identity user.name')" = "XDG Name" ]; then
	ok "setup identity read survives a credential-only ~/.gitconfig"
else
	not_ok "setup identity read survives a credential-only ~/.gitconfig"
fi
rm -rf "$_id_home"

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]

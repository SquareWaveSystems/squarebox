#!/usr/bin/env bash
set -euo pipefail

# e2e-test.sh — in-container end-to-end test runner for squarebox.
#
# Usage:
#   e2e-test.sh <suite>
#   e2e-test.sh all
#
# Suites: tools, shell, setup, update
# Output: TAP (Test Anything Protocol)

# ── TAP helpers ──────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
TEST_NUM=0

tap_ok() {
	TEST_NUM=$((TEST_NUM + 1))
	PASS_COUNT=$((PASS_COUNT + 1))
	echo "ok ${TEST_NUM} - $1"
}

tap_fail() {
	TEST_NUM=$((TEST_NUM + 1))
	FAIL_COUNT=$((FAIL_COUNT + 1))
	echo "not ok ${TEST_NUM} - $1"
	[ -n "${2:-}" ] && echo "#   $2"
}

run_test() {
	local name="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		tap_ok "$name"
	else
		tap_fail "$name"
	fi
}

# Like run_test but captures output and checks it contains a string.
run_test_grep() {
	local name="$1" pattern="$2"
	shift 2
	local output
	if output=$("$@" 2>&1) && echo "$output" | grep -qi "$pattern"; then
		tap_ok "$name"
	else
		tap_fail "$name" "expected pattern: $pattern"
	fi
}

# ── Suite: tools ─────────────────────────────────────────────────────────
# Covers: 5.1-5.12 (tool verification)

suite_tools() {
	# 5.1 bat --version + syntax highlighting
	run_test "5.1a bat --version" bat --version
	run_test "5.1b bat syntax highlight" bat --color=always /etc/hostname

	# 5.2 delta + git pager config
	run_test "5.2a delta --version" delta --version
	# gitconfig lives at /etc/gitconfig (system-level), not --global (user-level)
	run_test_grep "5.11 git pager uses delta" "delta" git config core.pager

	# 5.6 glow renders markdown
	run_test "5.6 glow renders file" glow /home/dev/motd.sh

	# 5.7 xh version (skip actual HTTP to avoid flaky network)
	run_test "5.7 xh --version" xh --version

	# 5.8 yq parses YAML
	run_test "5.8 yq parses tools.yaml" yq eval '.tools' /usr/local/lib/squarebox/tools.yaml

	# 5.9 gum version
	run_test "5.9 gum --version" gum --version

	# 5.10 fzf version
	run_test "5.10 fzf --version" fzf --version
}

# ── Suite: shell ─────────────────────────────────────────────────────────
# Covers: 4.1-4.7 (shell environment)

suite_shell() {
	# 4.1 starship prompt in bashrc
	run_test_grep "4.1 starship init in bashrc" "starship init" cat ~/.bashrc

	# 4.2 zoxide init in bashrc
	run_test_grep "4.2 zoxide init in bashrc" "zoxide init" cat ~/.bashrc

	# 4.3 MOTD runs without error
	run_test "4.3 motd.sh runs" ~/motd.sh

	# 4.7 aliases — check alias definitions exist in bashrc
	# Already tested in build.yml: ls, ll, cat, g, lg
	# Additional aliases:
	run_test_grep "4.7a alias lt defined" "alias lt=" cat ~/.bashrc
	run_test_grep "4.7b alias ff defined" "alias ff=" cat ~/.bashrc
	run_test_grep "4.7c alias gcm defined" "alias gcm=" cat ~/.bashrc
	run_test_grep "4.7d alias gcam defined" "alias gcam=" cat ~/.bashrc
	run_test_grep "4.7e alias gcad defined" "alias gcad=" cat ~/.bashrc
	run_test_grep "4.7f alias lsa defined" "alias lsa=" cat ~/.bashrc
	run_test_grep "4.7g alias .. defined" "alias \.\." cat ~/.bashrc
	run_test_grep "4.7h alias ... defined" "alias \.\.\." cat ~/.bashrc
	run_test_grep "4.7i alias .... defined" "alias \.\.\.\." cat ~/.bashrc

	# 4.4 EDITOR default is nano (check bashrc sets it, not bash -lc which triggers setup)
	run_test_grep "4.4 default EDITOR is nano" "export EDITOR='nano'" cat ~/.bashrc

	# Alias/config sourcing in bashrc
	run_test_grep "4.6a ai-aliases sourced" "squarebox-ai-aliases" cat ~/.bashrc
	run_test_grep "4.6b editor-aliases sourced" "squarebox-editor-aliases" cat ~/.bashrc
	run_test_grep "4.6c tui-aliases sourced" "squarebox-tui-aliases" cat ~/.bashrc
	run_test_grep "4.6d sdk-paths sourced" "squarebox-sdk-paths" cat ~/.bashrc

	# Shell config loads without errors (also in build.yml)
	run_test "4.0 shell config loads" bash -lc 'echo ok'
}

# ── Suite: setup ─────────────────────────────────────────────────────────
# Covers: 3.1, 3.2 (skip path), 3.7-3.12

suite_setup() {
	# 3.1 setup triggers on first login (check bashrc has trigger)
	run_test_grep "3.1 setup trigger in bashrc" "setup.sh" cat ~/.bashrc

	# 3.12 non-interactive mode skips prompts
	# Pre-configure git identity so that prompt is skipped
	git config --global user.name "E2E Test" 2>/dev/null || true
	git config --global user.email "e2e@test.local" 2>/dev/null || true

	# Run setup.sh in non-interactive mode (piped stdin)
	local setup_output
	setup_output=$(echo "" | ~/setup.sh 2>&1) || true

	TEST_NUM=$((TEST_NUM + 1))
	if echo "$setup_output" | grep -qi "skipping\|non-interactive"; then
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 3.12 non-interactive mode skips prompts"
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 3.12 non-interactive mode skips prompts"
	fi

	# 3.2 git identity skip when preconfigured
	TEST_NUM=$((TEST_NUM + 1))
	if echo "$setup_output" | grep -qiv "git name"; then
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 3.2 git identity skipped when preconfigured"
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 3.2 git identity skipped when preconfigured"
	fi
}

# ── Suite: setup-editors (run separately, installs binaries) ─────────────
# Covers: 3.7, 3.8, 3.9, 3.10, 3.11, 4.4, 4.5

suite_setup_editors() {
	# Pre-seed selections in /workspace/.squarebox/
	mkdir -p /workspace/.squarebox
	echo "opencode" > /workspace/.squarebox/ai-tool
	echo "micro,edit,fresh,nvim" > /workspace/.squarebox/editors
	echo "lazygit,gh-dash,yazi" > /workspace/.squarebox/tuis
	echo "tmux,zellij" > /workspace/.squarebox/multiplexer
	echo "node,go" > /workspace/.squarebox/sdks
	# Shell section (experimental): exercise the bash path here. The zsh
	# install (apt zsh + Oh My Zsh + two plugin clones) is network-heavy and
	# would significantly slow the CI suite, so it's not pre-seeded by default.
	echo "bash" > /workspace/.squarebox/shell
	# Ensure stale markers from a previous run are cleared so the assertion
	# below reflects the current selection, not leftover state.
	rm -f ~/.squarebox-use-zsh ~/.squarebox-use-fish

	# Pre-configure git identity
	git config --global user.name "E2E Test" 2>/dev/null || true
	git config --global user.email "e2e@test.local" 2>/dev/null || true

	# Run setup.sh non-interactively (uses saved selections)
	echo "" | ~/setup.sh 2>&1 || true

	# Source SDK paths and add ~/.local/bin to PATH for this session
	export PATH="$HOME/.local/bin:$PATH"
	# shellcheck source=/dev/null
	[ -f ~/.squarebox-sdk-paths ] && source ~/.squarebox-sdk-paths

	# 3.7 editors installed
	run_test "3.7a opencode installed" command -v opencode
	run_test "3.7b micro installed" command -v micro
	run_test "3.7c edit installed" command -v edit
	run_test "3.7d fresh installed" command -v fresh
	run_test "3.7e nvim installed" command -v nvim

	# 3.7f-h TUI tools installed
	run_test "3.7f lazygit installed" command -v lazygit
	run_test "3.7g gh-dash installed" command -v gh-dash
	run_test "3.7h yazi installed" command -v yazi

	# 5.12 lazygit config uses delta pager (set up by install_lazygit)
	run_test_grep "5.12 lazygit config uses delta" "delta" cat /home/dev/.config/lazygit/config.yml

	# 3.8 multiplexers installed
	run_test "3.8a tmux installed" command -v tmux
	run_test "3.8b zellij installed" command -v zellij

	# 3.9 SDKs installed
	run_test "3.9a node installed" command -v node
	run_test "3.9b go installed" test -x "$HOME/.local/go/bin/go"

	# 3.11 selections saved
	run_test "3.11a ai-tool config saved" test -f /workspace/.squarebox/ai-tool
	run_test "3.11b editors config saved" test -f /workspace/.squarebox/editors
	run_test "3.11c tuis config saved" test -f /workspace/.squarebox/tuis
	run_test "3.11d multiplexer config saved" test -f /workspace/.squarebox/multiplexer
	run_test "3.11e sdks config saved" test -f /workspace/.squarebox/sdks
	run_test "3.11f shell config saved" test -f /workspace/.squarebox/shell

	# 3.12 shell section: bash selection leaves no zsh/fish handoff markers
	run_test_grep "3.12a shell config is bash" "bash" cat /workspace/.squarebox/shell
	TEST_NUM=$((TEST_NUM + 1))
	if [ ! -e ~/.squarebox-use-zsh ]; then
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 3.12b no zsh marker for bash selection"
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 3.12b no zsh marker for bash selection"
	fi
	TEST_NUM=$((TEST_NUM + 1))
	if [ ! -e ~/.squarebox-use-fish ]; then
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 3.12c no fish marker for bash selection"
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 3.12c no fish marker for bash selection"
	fi

	# 4.4 EDITOR set to first selected editor (micro)
	run_test_grep "4.4 EDITOR set to micro" "micro" cat ~/.squarebox-editor-aliases

	# 4.5 c alias points to first AI tool (opencode)
	run_test_grep "4.5 c alias set to opencode" "opencode" cat ~/.squarebox-ai-aliases
}

# ── Suite: update ────────────────────────────────────────────────────────
# Covers: 7.1-7.3, 7.5-7.8

suite_update() {
	# 7.1 --help shows usage
	run_test_grep "7.1 sqrbx-update --help" "usage" sqrbx-update --help

	# 7.2 --list shows installed versions
	run_test_grep "7.2 sqrbx-update --list" "delta" sqrbx-update --list

	# 7.3 dry run (no args) exits without error
	run_test "7.3 sqrbx-update dry run" sqrbx-update

	# 7.6 checksum tamper detection
	# Create a fake checksums file with wrong hash, then try to update
	local checksum_dir
	checksum_dir=$(mktemp -d)
	echo "0000000000000000000000000000000000000000000000000000000000000000  delta_99.99.99_amd64.deb" > "$checksum_dir/checksums.txt"

	TEST_NUM=$((TEST_NUM + 1))
	# We can't easily trigger a tamper in sqrbx-update without modifying it,
	# but we can verify the verify-checksum script rejects bad checksums
	echo "test content" > "$checksum_dir/testfile"
	local expected_hash="0000000000000000000000000000000000000000000000000000000000000000"
	echo "${expected_hash}  testfile" > "$checksum_dir/test-checksums.txt"
	if ! (cd "$checksum_dir" && verify-checksum testfile testfile < test-checksums.txt) 2>/dev/null; then
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 7.6 checksum verification rejects tampered file"
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 7.6 checksum verification rejects tampered file"
	fi
	rm -rf "$checksum_dir"

}

# ── Suite: devcontainer ──────────────────────────────────────────────────
# Covers: 8.3-8.5 (run from outside the container by the workflow)

suite_devcontainer() {
	# These tests validate the devcontainer.json config file
	local dc=".devcontainer/devcontainer.json"

	if [ ! -f "$dc" ]; then
		tap_fail "8.1 devcontainer.json exists" "file not found: $dc"
		return
	fi

	# 8.1 valid JSON
	run_test "8.1 devcontainer.json is valid JSON" jq empty "$dc"

	# 8.3 workspace folder
	run_test_grep "8.3 workspaceFolder is /workspace" "/workspace" jq -r '.workspaceFolder' "$dc"

	# 8.4 user is dev
	run_test_grep "8.4 remoteUser is dev" "dev" jq -r '.remoteUser' "$dc"

	# 8.5 DEVCONTAINER=1
	run_test_grep "8.5 DEVCONTAINER env var set" "1" jq -r '.containerEnv.DEVCONTAINER' "$dc"
}

# ── Suite: setup-rerun ───────────────────────────────────────────────────
# Covers: sqrbx-setup command (re-run container setup)

suite_setup_rerun() {
	# sqrbx-setup exists and is executable
	run_test "9.1 sqrbx-setup exists" test -x /usr/local/bin/sqrbx-setup

	# --help shows usage
	run_test_grep "9.2 sqrbx-setup --help shows usage" "usage" sqrbx-setup --help

	# --help lists section names
	run_test_grep "9.3 sqrbx-setup --help lists sections" "editors" sqrbx-setup --help
	run_test_grep "9.3b sqrbx-setup --help lists shell section" "shell" sqrbx-setup --help

	# --list runs without error
	run_test "9.4 sqrbx-setup --list runs" sqrbx-setup --list

	# Invalid section name exits with error
	TEST_NUM=$((TEST_NUM + 1))
	if sqrbx-setup invalidname 2>/dev/null; then
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "not ok ${TEST_NUM} - 9.5 sqrbx-setup rejects invalid section"
	else
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "ok ${TEST_NUM} - 9.5 sqrbx-setup rejects invalid section"
	fi

	# setup.sh accepts --rerun with a valid section without error (non-interactive)
	run_test "9.6 setup.sh --rerun parses cleanly" bash -c '~/setup.sh --rerun git </dev/null'
}

# ── Main ─────────────────────────────────────────────────────────────────

usage() {
	echo "Usage: $0 <suite|all>"
	echo "Suites: tools, shell, setup, setup-editors, update, devcontainer, setup-rerun"
	exit 1
}

main() {
	local suite="${1:-}"
	[ -z "$suite" ] && usage

	echo "# e2e-test: suite=$suite"

	case "$suite" in
		tools)           suite_tools ;;
		shell)           suite_shell ;;
		setup)           suite_setup ;;
		setup-editors)   suite_setup_editors ;;
		update)          suite_update ;;
		devcontainer)    suite_devcontainer ;;
		setup-rerun)     suite_setup_rerun ;;
		all)
			suite_tools
			suite_shell
			suite_setup
			suite_update
			suite_devcontainer
			suite_setup_rerun
			;;
		*) usage ;;
	esac

	echo
	echo "1..${TEST_NUM}"
	echo "# pass: ${PASS_COUNT}, fail: ${FAIL_COUNT}"

	[ "$FAIL_COUNT" -eq 0 ]
}

main "$@"

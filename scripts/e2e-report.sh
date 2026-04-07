#!/usr/bin/env bash
set -euo pipefail

# e2e-report.sh — Generate a markdown report mapping e2e job results
# to UAT checklist items.
#
# Expects environment variables set by the e2e.yml workflow:
#   BUILD_AMD64, BUILD_ARM64, HOST_INSTALL, TOOLS_VERIFICATION,
#   SHELL_ENVIRONMENT, SETUP_NONINTERACTIVE, SETUP_EDITORS_SDKS,
#   CONTAINER_LIFECYCLE, SQRBX_UPDATE, DEVCONTAINER
#
# Each variable is "success", "failure", "cancelled", or "skipped".

status_icon() {
	case "${1:-unknown}" in
		success)   echo "PASS" ;;
		failure)   echo "FAIL" ;;
		cancelled) echo "SKIP" ;;
		skipped)   echo "SKIP" ;;
		*)         echo "????" ;;
	esac
}

# Map job results to individual checklist items
# Format: item_number | section | description | job_var_or_MANUAL
ITEMS=(
	"1.1|Host Install|install.sh completes without errors|HOST_INSTALL"
	"1.2|Host Install|Docker image builds successfully|BUILD_AMD64"
	"1.3|Host Install|~/squarebox/workspace directory created|HOST_INSTALL"
	"1.4|Host Install|Shell aliases added|HOST_INSTALL"
	"1.5|Host Install|sqrbx launches container and drops into shell|MANUAL"
	"1.6|Host Install|Host configs seeded|HOST_INSTALL"
	"2.1|Docker Build|docker build succeeds (amd64)|BUILD_AMD64"
	"2.2|Docker Build|docker build succeeds (arm64)|BUILD_ARM64"
	"2.3|Docker Build|All base tools present|BUILD_AMD64"
	"2.4|Docker Build|All binary tools present|TOOLS_VERIFICATION"
	"2.5|Docker Build|Checksum verification passes|BUILD_AMD64"
	"3.1|First-Run Setup|Setup triggers on first login|SETUP_NONINTERACTIVE"
	"3.2|First-Run Setup|Git identity prompt skips if preconfigured|SETUP_NONINTERACTIVE"
	"3.3|First-Run Setup|GitHub CLI auth flow works|MANUAL"
	"3.4|First-Run Setup|GH auth persists|MANUAL"
	"3.5|First-Run Setup|Claude Code installs and runs|MANUAL"
	"3.6|First-Run Setup|Copilot / Gemini / Codex install via npm|MANUAL"
	"3.7|First-Run Setup|OpenCode installs from binary|SETUP_EDITORS_SDKS"
	"3.8|First-Run Setup|Editors install cleanly|SETUP_EDITORS_SDKS"
	"3.9|First-Run Setup|Multiplexers install|SETUP_EDITORS_SDKS"
	"3.10|First-Run Setup|SDKs install|SETUP_EDITORS_SDKS"
	"3.11|First-Run Setup|Selections saved and reused|SETUP_EDITORS_SDKS"
	"3.12|First-Run Setup|Non-interactive mode skips prompts|SETUP_NONINTERACTIVE"
	"4.1|Shell Environment|Starship prompt initialized|SHELL_ENVIRONMENT"
	"4.2|Shell Environment|Zoxide initialized|SHELL_ENVIRONMENT"
	"4.3|Shell Environment|MOTD banner displays|SHELL_ENVIRONMENT"
	"4.4|Shell Environment|EDITOR set to first selected editor|SETUP_EDITORS_SDKS"
	"4.5|Shell Environment|c alias points to first AI tool|SETUP_EDITORS_SDKS"
	"4.6|Shell Environment|SDK paths sourced|SETUP_EDITORS_SDKS"
	"4.7|Shell Environment|Key aliases work|SHELL_ENVIRONMENT"
	"5.1|Tools Verification|bat version + syntax highlighting|TOOLS_VERIFICATION"
	"5.2|Tools Verification|delta + git diff colored output|TOOLS_VERIFICATION"
	"5.3|Tools Verification|lazygit TUI launches|MANUAL"
	"5.4|Tools Verification|yazi TUI launches|MANUAL"
	"5.5|Tools Verification|gh-dash TUI launches|MANUAL"
	"5.6|Tools Verification|glow renders markdown|TOOLS_VERIFICATION"
	"5.7|Tools Verification|xh HTTP client|TOOLS_VERIFICATION"
	"5.8|Tools Verification|yq parses YAML|TOOLS_VERIFICATION"
	"5.9|Tools Verification|gum interactive prompts|MANUAL"
	"5.10|Tools Verification|fzf fuzzy search|MANUAL"
	"5.11|Tools Verification|Git pager uses delta|TOOLS_VERIFICATION"
	"5.12|Tools Verification|Lazygit uses delta pager|TOOLS_VERIFICATION"
	"6.1|Container Lifecycle|exit suspends container|CONTAINER_LIFECYCLE"
	"6.2|Container Lifecycle|docker start resumes with state|CONTAINER_LIFECYCLE"
	"6.3|Container Lifecycle|Files in /workspace persist|CONTAINER_LIFECYCLE"
	"6.4|Container Lifecycle|Files outside /workspace persist|CONTAINER_LIFECYCLE"
	"6.5|Container Lifecycle|sqrbx-rebuild rebuilds|MANUAL"
	"6.6|Container Lifecycle|After rebuild: workspace preserved|MANUAL"
	"6.7|Container Lifecycle|After rebuild: selections reused|MANUAL"
	"6.8|Container Lifecycle|After rebuild: GH CLI stays auth'd|MANUAL"
	"6.9|Container Lifecycle|Volume mounts work|CONTAINER_LIFECYCLE"
	"7.1|sqrbx-update|--help shows usage|SQRBX_UPDATE"
	"7.2|sqrbx-update|--list shows installed versions|SQRBX_UPDATE"
	"7.3|sqrbx-update|Dry run shows available updates|SQRBX_UPDATE"
	"7.4|sqrbx-update|--apply downloads and installs|SQRBX_UPDATE"
	"7.5|sqrbx-update|Single tool update works|SQRBX_UPDATE"
	"7.6|sqrbx-update|Checksum verification blocks tampered downloads|SQRBX_UPDATE"
	"7.7|sqrbx-update|Rate limit warning shown|SQRBX_UPDATE"
	"7.8|sqrbx-update|GITHUB_TOKEN increases rate limit|SQRBX_UPDATE"
	"8.1|Dev Container|devcontainer.json is valid JSON|DEVCONTAINER"
	"8.2|Dev Container|VS Code Reopen in Container builds|MANUAL"
	"8.3|Dev Container|Workspace folder is /workspace|DEVCONTAINER"
	"8.4|Dev Container|User is dev|DEVCONTAINER"
	"8.5|Dev Container|DEVCONTAINER=1 skips setup|DEVCONTAINER"
	"8.6|Dev Container|Manual setup.sh works|MANUAL"
	"9.1|CI Pipeline|Push to main triggers workflow|BUILD_AMD64"
	"9.2|CI Pipeline|PR to main triggers workflow|BUILD_AMD64"
	"9.3|CI Pipeline|Image builds with buildx|BUILD_AMD64"
	"9.4|CI Pipeline|Binary presence checks pass|TOOLS_VERIFICATION"
	"9.5|CI Pipeline|Alias resolution tests pass|SHELL_ENVIRONMENT"
	"9.6|CI Pipeline|Container persistence test passes|CONTAINER_LIFECYCLE"
)

# Count results
e2e_total=0
e2e_pass=0
e2e_fail=0
e2e_skip=0
manual_total=0

for item in "${ITEMS[@]}"; do
	IFS='|' read -r num section desc job_var <<< "$item"
	if [ "$job_var" = "MANUAL" ]; then
		manual_total=$((manual_total + 1))
	else
		e2e_total=$((e2e_total + 1))
		result="${!job_var:-unknown}"
		case "$result" in
			success)   e2e_pass=$((e2e_pass + 1)) ;;
			failure)   e2e_fail=$((e2e_fail + 1)) ;;
			*)         e2e_skip=$((e2e_skip + 1)) ;;
		esac
	fi
done

total=${#ITEMS[@]}

# Generate report
cat <<EOF
# E2E / UAT Report

**Date**: $(date -u +%Y-%m-%d)
**Commit**: ${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}

## Summary

- **Total items**: ${total}
- **Automated (e2e)**: ${e2e_total} — ${e2e_pass} passed, ${e2e_fail} failed, ${e2e_skip} skipped
- **Manual (uat)**: ${manual_total}

## Results

| # | Section | Item | Status |
|---|---------|------|--------|
EOF

for item in "${ITEMS[@]}"; do
	IFS='|' read -r num section desc job_var <<< "$item"
	if [ "$job_var" = "MANUAL" ]; then
		status="uat MANUAL"
	else
		result="${!job_var:-unknown}"
		status="e2e $(status_icon "$result")"
	fi
	echo "| ${num} | ${section} | ${desc} | ${status} |"
done

echo
echo "---"
echo "*Generated by [e2e.yml](/.github/workflows/e2e.yml)*"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

if grep -E '(@githubnext/github-copilot-cli|github-copilot-cli)' \
	setup.sh README.md CLAUDE.md Dockerfile >/dev/null; then
	fail "production surfaces still reference deprecated Copilot CLI"
fi

if grep -Eqi 'paseo' setup.sh README.md CLAUDE.md uat-checklist.md \
	demo/setup-demo.sh scripts/squarebox-setup.sh scripts/e2e-test.sh; then
	fail "current product surfaces still reference removed Paseo support"
fi

if grep -F 'COPY scripts/sqrbx-learn' Dockerfile >/dev/null \
	|| grep -F 'COPY scripts/sqrbx-agent-tool-log' Dockerfile >/dev/null; then
	fail "disabled learn implementation is still shipped"
fi

test "$(jq -r .workspaceFolder .devcontainer/devcontainer.json)" = /workspace \
	|| fail "Dev Container Workspace differs from setup state"
jq -r .workspaceMount .devcontainer/devcontainer.json | grep -Fq 'target=/workspace' \
	|| fail "Dev Container mount does not target /workspace"

if grep -E '(USER_HOME|\$HOME|USERPROFILE).*[.]config/git' \
	install.sh install.ps1 docker-compose.yml >/dev/null; then
	fail "host real Git config is still referenced"
fi

for ignored in '.squarebox/' 'workspace/' '.config/' '.env.*' 'credentials.json'; do
	grep -Fqx "$ignored" .dockerignore || fail ".dockerignore misses $ignored"
done

grep -Fq 'uninstall.ps1' .github/workflows/e2e.yml \
	|| fail "PowerShell uninstaller is missing from release assets"
grep -Fq 'release.json' .github/workflows/e2e.yml \
	|| fail "release identity is missing from publication"
grep -Fq 'env SQUAREBOX_AI=' README.md \
	|| fail "noninteractive installer example does not pass variables to Bash"
if grep -Eq '~370 MB|docker build.+reproducible' README.md SECURITY.md; then
	fail "stale image-size/reproducibility claim remains"
fi

grep -Fq 'cross-adapter state consumption is rejected' README.md \
	|| fail "README promises no Windows lifecycle-adapter boundary"
grep -Fq 'adapter may consume that state' CLAUDE.md \
	|| fail "agent guidance does not enforce adapter-native lifecycle state"
grep -Fq 'are not cross-consumed' docs/releases/v1.1.0.md \
	|| fail "migration guide implies PowerShell/Git Bash state interchange"
grep -Fq 'does not claim `SSH_AUTH_SOCK` forwarding' uat-checklist.md \
	|| fail "PowerShell UAT still overclaims SSH-agent forwarding"
if grep -Fq 'Bash and PowerShell lifecycle state must remain compatible' \
	README.md CLAUDE.md docs/releases/v1.1.0.md uat-checklist.md; then
	fail "docs still promise unsupported cross-adapter lifecycle state"
fi

grep -Fq 'Keyboard shortcuts (Bash)' scripts/squarebox-help.sh \
	|| fail "fzf keybinding help is not scoped to Bash"
grep -Fq 'Bash-only contract' CLAUDE.md \
	|| fail "shell contract overclaims Bash-specific fzf bindings"
if grep -Fq "source ~/.bashrc" scripts/squarebox-setup.sh; then
	fail "setup wrapper gives Bash-only reload advice to every shell"
fi

while IFS=$'\t' read -r id _description; do
	[ -z "$id" ] && continue
	[[ "$id" == \#* ]] && continue
	grep -Fq "$id" .github/workflows/e2e.yml scripts/e2e-test.sh \
		|| fail "required Evidence id has no exact producer: $id"
done < scripts/e2e-required.tsv

echo "PASS: repository docs, release assets, and required Evidence stay aligned"

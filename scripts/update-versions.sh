#!/usr/bin/env bash
set -euo pipefail

# Fetch latest versions of all pinned tools, download artifacts for both
# architectures, compute SHA256 checksums, and update checksums.txt,
# setup-checksums.txt, Dockerfile, and setup.sh.
#
# Set GITHUB_TOKEN to avoid the 60 req/hr unauthenticated rate limit.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
	AUTH_HEADER=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# Pre-flight: check remaining GitHub API rate limit
_rate_info=$(curl -fsSL "${AUTH_HEADER[@]}" "https://api.github.com/rate_limit" 2>/dev/null) || true
_rate_remaining=$(echo "$_rate_info" | jq -r '.rate.remaining' 2>/dev/null) || true
_rate_limit=$(echo "$_rate_info" | jq -r '.rate.limit' 2>/dev/null) || true
if [[ "${_rate_remaining:-0}" =~ ^[0-9]+$ ]] && [ "$_rate_remaining" -lt 20 ]; then
	echo "Error: Only ${_rate_remaining}/${_rate_limit} GitHub API requests remaining." >&2
	if [ -z "${GITHUB_TOKEN:-}" ]; then
		echo "Set GITHUB_TOKEN to authenticate (5000 req/hr instead of 60)." >&2
	fi
	exit 1
fi

gh_latest_tag() {
	local repo="$1"
	local response http_code body
	response=$(curl -fsSL -w '\n%{http_code}' "${AUTH_HEADER[@]}" \
		"https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || true
	http_code=$(echo "$response" | tail -1)
	body=$(echo "$response" | sed '$d')
	if [ "$http_code" = "403" ]; then
		echo "Error: GitHub API rate limit exceeded (${repo})." >&2
		echo "Set GITHUB_TOKEN to authenticate (5000 req/hr instead of 60)." >&2
		exit 1
	elif [ "$http_code" != "200" ]; then
		echo "Error: GitHub API returned HTTP ${http_code} for ${repo}." >&2
		exit 1
	fi
	echo "$body" | jq -r '.tag_name'
}

# Strip leading 'v' from a tag
strip_v() { echo "${1#v}"; }

download_and_hash() {
	local url="$1" name="$2"
	curl -fsSLo "${WORK}/${name}" "$url"
	sha256sum "${WORK}/${name}" | awk '{print $1}'
}

echo "Fetching latest versions..."

# --- Dockerfile tools ---

DELTA_TAG=$(gh_latest_tag dandavison/delta)
# Delta tags don't have a 'v' prefix
DELTA_VERSION="${DELTA_TAG}"

YQ_TAG=$(gh_latest_tag mikefarah/yq)
YQ_VERSION=$(strip_v "$YQ_TAG")

LAZYGIT_TAG=$(gh_latest_tag jesseduffield/lazygit)
LAZYGIT_VERSION=$(strip_v "$LAZYGIT_TAG")

XH_TAG=$(gh_latest_tag ducaale/xh)
XH_VERSION=$(strip_v "$XH_TAG")

YAZI_TAG=$(gh_latest_tag sxyazi/yazi)
YAZI_VERSION=$(strip_v "$YAZI_TAG")

STARSHIP_TAG=$(gh_latest_tag starship/starship)
STARSHIP_VERSION=$(strip_v "$STARSHIP_TAG")

GH_DASH_TAG=$(gh_latest_tag dlvhdr/gh-dash)
GH_DASH_VERSION=$(strip_v "$GH_DASH_TAG")

GLOW_TAG=$(gh_latest_tag charmbracelet/glow)
GLOW_VERSION=$(strip_v "$GLOW_TAG")

GUM_TAG=$(gh_latest_tag charmbracelet/gum)
GUM_VERSION=$(strip_v "$GUM_TAG")

# --- setup.sh tools ---

OPENCODE_TAG=$(gh_latest_tag anomalyco/opencode)
OPENCODE_VERSION=$(strip_v "$OPENCODE_TAG")

GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)

NVM_TAG=$(gh_latest_tag nvm-sh/nvm)
NVM_VERSION=$(strip_v "$NVM_TAG")

MICRO_TAG=$(gh_latest_tag micro-editor/micro)
MICRO_VERSION=$(strip_v "$MICRO_TAG")

FRESH_TAG=$(gh_latest_tag sinelaw/fresh)
FRESH_VERSION=$(strip_v "$FRESH_TAG")

EDIT_TAG=$(gh_latest_tag microsoft/edit)
EDIT_VERSION=$(strip_v "$EDIT_TAG")
# Edit has a known issue: asset version may differ from tag. Extract actual asset name.
_edit_response=$(curl -fsSL -w '\n%{http_code}' "${AUTH_HEADER[@]}" \
	"https://api.github.com/repos/microsoft/edit/releases/latest" 2>/dev/null) || true
_edit_http=$(echo "$_edit_response" | tail -1)
if [ "$_edit_http" = "403" ]; then
	echo "Error: GitHub API rate limit exceeded (microsoft/edit assets)." >&2
	echo "Set GITHUB_TOKEN to authenticate (5000 req/hr instead of 60)." >&2
	exit 1
elif [ "$_edit_http" != "200" ]; then
	echo "Error: GitHub API returned HTTP ${_edit_http} for microsoft/edit assets." >&2
	exit 1
fi
_edit_body=$(echo "$_edit_response" | sed '$d')
EDIT_ASSET_X86=$(echo "$_edit_body" | jq -r '.assets[].name' | grep 'x86_64-linux-gnu')
EDIT_ASSET_ARM=$(echo "$_edit_body" | jq -r '.assets[].name' | grep 'aarch64-linux-gnu')
EDIT_ASSET_VERSION=$(echo "$EDIT_ASSET_X86" | sed -E 's/^edit-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')

HELIX_TAG=$(gh_latest_tag helix-editor/helix)
HELIX_VERSION="$HELIX_TAG"

NVIM_TAG=$(gh_latest_tag neovim/neovim)
NVIM_VERSION=$(strip_v "$NVIM_TAG")

echo
echo "Versions:"
echo "  Delta:    ${DELTA_VERSION}"
echo "  Yq:       ${YQ_VERSION}"
echo "  Lazygit:  ${LAZYGIT_VERSION}"
echo "  xh:       ${XH_VERSION}"
echo "  Yazi:     ${YAZI_VERSION}"
echo "  Starship: ${STARSHIP_VERSION}"
echo "  gh-dash:  ${GH_DASH_VERSION}"
echo "  Glow:     ${GLOW_VERSION}"
echo "  Gum:      ${GUM_VERSION}"
echo "  OpenCode: ${OPENCODE_VERSION}"
echo "  Go:       ${GO_VERSION}"
echo "  NVM:      ${NVM_VERSION}"
echo "  Micro:    ${MICRO_VERSION}"
echo "  Fresh:    ${FRESH_VERSION}"
echo "  Edit:     ${EDIT_VERSION} (asset: ${EDIT_ASSET_VERSION})"
echo "  Helix:    ${HELIX_VERSION}"
echo "  Neovim:   ${NVIM_VERSION}"
echo

echo "Downloading artifacts and computing checksums..."

# --- checksums.txt (Dockerfile) ---

cat > "${REPO_ROOT}/checksums.txt" << HEADER
# SHA256 checksums for Dockerfile binary tool downloads.
# Format: sha256  filename
# Generated by scripts/update-versions.sh — do not edit manually.
#
HEADER

emit() {
	local label="$1" url="$2" name="$3"
	local hash
	hash=$(download_and_hash "$url" "$name")
	echo "${hash}  ${name}" >> "${REPO_ROOT}/checksums.txt"
	echo "  ${label}: ${hash}  ${name}"
}

emit_setup() {
	local label="$1" url="$2" name="$3"
	local hash
	hash=$(download_and_hash "$url" "$name")
	echo "${hash}  ${name}" >> "${REPO_ROOT}/setup-checksums.txt"
	echo "  ${label}: ${hash}  ${name}"
}

echo "# Delta ${DELTA_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "delta amd64" "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_amd64.deb" "git-delta_${DELTA_VERSION}_amd64.deb"
emit "delta arm64" "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_arm64.deb" "git-delta_${DELTA_VERSION}_arm64.deb"

echo "# Yq ${YQ_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "yq amd64" "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" "yq_linux_amd64"
emit "yq arm64" "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_arm64" "yq_linux_arm64"

echo "# Lazygit ${LAZYGIT_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "lazygit x86_64" "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" "lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
emit "lazygit arm64" "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz" "lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz"

echo "# xh ${XH_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "xh x86_64" "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-x86_64-unknown-linux-musl.tar.gz" "xh-v${XH_VERSION}-x86_64-unknown-linux-musl.tar.gz"
emit "xh aarch64" "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-aarch64-unknown-linux-musl.tar.gz" "xh-v${XH_VERSION}-aarch64-unknown-linux-musl.tar.gz"

echo "# Yazi ${YAZI_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "yazi x86_64" "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-musl.zip" "yazi-x86_64-unknown-linux-musl.zip"
emit "yazi aarch64" "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-aarch64-unknown-linux-musl.zip" "yazi-aarch64-unknown-linux-musl.zip"

echo "# Starship ${STARSHIP_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "starship x86_64" "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" "starship-x86_64-unknown-linux-musl.tar.gz"
emit "starship aarch64" "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-aarch64-unknown-linux-musl.tar.gz" "starship-aarch64-unknown-linux-musl.tar.gz"

echo "# gh-dash ${GH_DASH_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "gh-dash amd64" "https://github.com/dlvhdr/gh-dash/releases/download/v${GH_DASH_VERSION}/gh-dash_v${GH_DASH_VERSION}_linux-amd64" "gh-dash_v${GH_DASH_VERSION}_linux-amd64"
emit "gh-dash arm64" "https://github.com/dlvhdr/gh-dash/releases/download/v${GH_DASH_VERSION}/gh-dash_v${GH_DASH_VERSION}_linux-arm64" "gh-dash_v${GH_DASH_VERSION}_linux-arm64"

echo "# Glow ${GLOW_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "glow x86_64" "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz" "glow_${GLOW_VERSION}_Linux_x86_64.tar.gz"
emit "glow arm64" "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_arm64.tar.gz" "glow_${GLOW_VERSION}_Linux_arm64.tar.gz"

echo "# Gum ${GUM_VERSION}" >> "${REPO_ROOT}/checksums.txt"
emit "gum x86_64" "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" "gum_${GUM_VERSION}_Linux_x86_64.tar.gz"
emit "gum arm64" "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_arm64.tar.gz" "gum_${GUM_VERSION}_Linux_arm64.tar.gz"

# --- setup-checksums.txt ---

cat > "${REPO_ROOT}/setup-checksums.txt" << HEADER
# SHA256 checksums for setup.sh downloads.
# Format: sha256  filename
# Generated by scripts/update-versions.sh — do not edit manually.
#
HEADER

echo "# OpenCode ${OPENCODE_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "opencode x64" "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" "opencode-linux-x64.tar.gz"
emit_setup "opencode arm64" "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-arm64.tar.gz" "opencode-linux-arm64.tar.gz"

echo "# NVM install script v${NVM_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "nvm script" "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" "nvm-install-v${NVM_VERSION}.sh"

echo "# Go ${GO_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "go amd64" "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" "${GO_VERSION}.linux-amd64.tar.gz"
emit_setup "go arm64" "https://go.dev/dl/${GO_VERSION}.linux-arm64.tar.gz" "${GO_VERSION}.linux-arm64.tar.gz"

echo "# Micro ${MICRO_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "micro linux64" "https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux64.tar.gz" "micro-${MICRO_VERSION}-linux64.tar.gz"
emit_setup "micro arm64" "https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux-arm64.tar.gz" "micro-${MICRO_VERSION}-linux-arm64.tar.gz"

echo "# Edit ${EDIT_VERSION} (asset version ${EDIT_ASSET_VERSION})" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "edit x86_64" "https://github.com/microsoft/edit/releases/download/v${EDIT_VERSION}/${EDIT_ASSET_X86}" "${EDIT_ASSET_X86}"
emit_setup "edit aarch64" "https://github.com/microsoft/edit/releases/download/v${EDIT_VERSION}/${EDIT_ASSET_ARM}" "${EDIT_ASSET_ARM}"

echo "# Fresh ${FRESH_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "fresh x86_64" "https://github.com/sinelaw/fresh/releases/download/v${FRESH_VERSION}/fresh-editor-x86_64-unknown-linux-musl.tar.gz" "fresh-editor-x86_64-unknown-linux-musl.tar.gz"
emit_setup "fresh aarch64" "https://github.com/sinelaw/fresh/releases/download/v${FRESH_VERSION}/fresh-editor-aarch64-unknown-linux-musl.tar.gz" "fresh-editor-aarch64-unknown-linux-musl.tar.gz"

echo "# Helix ${HELIX_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "helix x86_64" "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-x86_64-linux.tar.xz" "helix-${HELIX_VERSION}-x86_64-linux.tar.xz"
emit_setup "helix aarch64" "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-aarch64-linux.tar.xz" "helix-${HELIX_VERSION}-aarch64-linux.tar.xz"

echo "# Neovim ${NVIM_VERSION}" >> "${REPO_ROOT}/setup-checksums.txt"
emit_setup "nvim x86_64" "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" "nvim-linux-x86_64.tar.gz"
emit_setup "nvim arm64" "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-arm64.tar.gz" "nvim-linux-arm64.tar.gz"

# --- Update Dockerfile ARGs ---

echo
echo "Updating Dockerfile..."

update_arg() {
	local name="$1" value="$2"
	sed -i "s|^ARG ${name}=.*|ARG ${name}=${value}|" "${REPO_ROOT}/Dockerfile"
}

update_arg DELTA_VERSION "$DELTA_VERSION"
update_arg YQ_VERSION "$YQ_VERSION"
update_arg LAZYGIT_VERSION "$LAZYGIT_VERSION"
update_arg XH_VERSION "$XH_VERSION"
update_arg YAZI_VERSION "$YAZI_VERSION"
update_arg STARSHIP_VERSION "$STARSHIP_VERSION"
update_arg GH_DASH_VERSION "$GH_DASH_VERSION"
update_arg GLOW_VERSION "$GLOW_VERSION"
update_arg GUM_VERSION "$GUM_VERSION"

# --- Update setup.sh versions ---

echo "Updating setup.sh..."

sed -i "s|^OPENCODE_VERSION=.*|OPENCODE_VERSION=\"${OPENCODE_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^GO_VERSION=.*|GO_VERSION=\"${GO_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^NVM_VERSION=.*|NVM_VERSION=\"${NVM_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^MICRO_VERSION=.*|MICRO_VERSION=\"${MICRO_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^EDIT_VERSION=.*|EDIT_VERSION=\"${EDIT_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^EDIT_ASSET_VERSION=.*|EDIT_ASSET_VERSION=\"${EDIT_ASSET_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^FRESH_VERSION=.*|FRESH_VERSION=\"${FRESH_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^HELIX_VERSION=.*|HELIX_VERSION=\"${HELIX_VERSION}\"|" "${REPO_ROOT}/setup.sh"
sed -i "s|^NVIM_VERSION=.*|NVIM_VERSION=\"${NVIM_VERSION}\"|" "${REPO_ROOT}/setup.sh"

echo
echo "Done. Review changes with: git diff"

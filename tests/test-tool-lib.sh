#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export SB_GH_METADATA_CACHE_DIR="$TMP/default-metadata-cache"
mkdir -p "$SB_GH_METADATA_CACHE_DIR"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
assert_eq() {
	local expected=$1 actual=$2 message=$3
	if [ "$expected" = "$actual" ]; then ok "$message"; else
		not_ok "$message (expected '$expected', got '$actual')"
	fi
}
assert_file_content() {
	local expected=$1 file=$2 message=$3 actual
	actual=$(<"$file")
	assert_eq "$expected" "$actual" "$message"
}

REGISTRY="$TMP/tools.yaml"
cat > "$REGISTRY" <<'YAML'
tools:
  sample:
    repo: example/sample
    version_prefix: v
    artifact: sample-{version}-{dpkg_arch}
    method: binary
    binaries: sample
    dest: user
    group: setup
    verification: github-release-digest
  packed:
    repo: example/packed
    version_prefix: v
    artifact: packed-{version}-{dpkg_arch}.tar.gz
    method: tar.gz
    binaries: packed
    tar_extract: packed
    dest: user
    group: setup
    verification: github-release-digest
  pinned:
    repo: example/pinned
    version_prefix: v
    artifact: pinned-{version}-{dpkg_arch}
    method: binary
    binaries: pinned
    dest: system
    group: dockerfile
    verification: sha256
    docker_arg: PINNED_VERSION
  helixish:
    repo: example/helixish
    version_prefix: ""
    artifact: helixish-{version}-{zarch}.tar.xz
    method: tar.xz
    binaries: hx
    find_binary: true
    post_install: helix_runtime
    dest: user
    group: setup
    verification: github-release-digest
  zipper:
    repo: example/zipper
    version_prefix: v
    artifact: zipper-{version}-{zarch}.zip
    method: zip
    binaries: zipper,zip-helper
    zip_subdir: zipper-{zarch}
    dest: user
    group: setup
    verification: github-release-digest
  treeish:
    repo: example/treeish
    version_prefix: v
    artifact: treeish-{version}-{zarch}.tar.gz
    method: tar.gz-tree
    binaries: treeish
    tree_name: treeish-{zarch}
    tree_dest: ~/.local/treeish
    symlink: ~/.local/treeish/bin/treeish
    dest: user
    group: setup
    verification: github-release-digest
YAML

PAYLOAD="$TMP/payload"
cat > "$PAYLOAD" <<'SH'
#!/usr/bin/env bash
echo "sample 2.0.0"
SH
chmod +x "$PAYLOAD"

run_install_case() {
	local case_name=$1 body=$2
	local case_dir="$TMP/$case_name"
	mkdir -p "$case_dir/home"
	(
		export HOME="$case_dir/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64 PAYLOAD
		# shellcheck source=scripts/lib/tool-lib.sh
		source "$REPO_ROOT/scripts/lib/tool-lib.sh"
		# Most cases below exercise staging/commit behavior at the public
		# sb_install interface. Release metadata integrity has dedicated cases,
		# so these install fixtures provide that preceding trusted seam.
		sb_prepare_release_asset() {
			SB_RESOLVED_VERSION=${2:-1.0.0}
			[ "$SB_RESOLVED_VERSION" != latest ] || SB_RESOLVED_VERSION=1.0.0
			SB_RESOLVED_TAG="v$SB_RESOLVED_VERSION"
			SB_RESOLVED_ARTIFACT=$(sb_artifact "$1" "$SB_RESOLVED_VERSION")
			SB_RESOLVED_URL="https://artifacts.test/$SB_RESOLVED_ARTIFACT"
			SB_EXPECTED_ASSET_SHA256=$(printf fixture | sha256sum | awk '{print $1}')
		}
		sb_verify() { return 0; }
		eval "$body"
	)
}

if (
	export SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_validate_registry
); then ok "valid registry passes complete metadata validation"; else not_ok "valid registry passes complete metadata validation"; fi

UNSUPPORTED_ARCH_ERR="$TMP/unsupported-arch.err"
if (
	export SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=riscv64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh" 2>"$UNSUPPORTED_ARCH_ERR"
); then
	not_ok "unsupported architecture fails while initializing artifact management"
elif grep -q 'unsupported architecture: riscv64' "$UNSUPPORTED_ARCH_ERR"; then
	ok "unsupported architecture fails while initializing artifact management"
else
	not_ok "unsupported architecture fails while initializing artifact management with a clear diagnostic"
fi

SETUP_SYSTEM_REGISTRY="$TMP/setup-system-tools.yaml"
cp "$REGISTRY" "$SETUP_SYSTEM_REGISTRY"
sed -i '0,/dest: user/s//dest: system/' "$SETUP_SYSTEM_REGISTRY"
if (
	export SB_TOOLS_YAML="$SETUP_SYSTEM_REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_validate_registry >/dev/null 2>&1
); then not_ok "setup-tier registry entry cannot target the system destination"; else ok "setup-tier registry entry cannot target the system destination"; fi

IMAGE_USER_REGISTRY="$TMP/image-user-tools.yaml"
# Replace pinned's first destination without depending on registry order.
awk '
	$0 == "  pinned:" { in_pinned=1 }
	in_pinned && $0 == "    dest: system" { print "    dest: user"; in_pinned=0; next }
	{ print }
' "$REGISTRY" > "$IMAGE_USER_REGISTRY"
if (
	export SB_TOOLS_YAML="$IMAGE_USER_REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_validate_registry >/dev/null 2>&1
); then not_ok "Dockerfile-tier registry entry cannot target the user destination"; else ok "Dockerfile-tier registry entry cannot target the user destination"; fi

SYSTEM_MULTI_REGISTRY="$TMP/system-multi-tools.yaml"
awk '
	$0 == "  packed:" { in_packed=1 }
	in_packed && $0 == "    binaries: packed" { print "    binaries: packed,helper"; next }
	in_packed && $0 == "    dest: user" { print "    dest: system"; next }
	in_packed && $0 == "    group: setup" { print "    group: dockerfile"; next }
	in_packed && $0 == "    verification: github-release-digest" {
		print "    verification: sha256"; print "    docker_arg: PACKED_VERSION"; in_packed=0; next
	}
	{ print }
' "$REGISTRY" > "$SYSTEM_MULTI_REGISTRY"
if (
	export SB_TOOLS_YAML="$SYSTEM_MULTI_REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_validate_registry >/dev/null 2>&1
); then not_ok "system-destination archive cannot declare multiple non-transactional outputs"; else ok "system-destination archive cannot declare multiple non-transactional outputs"; fi

UNCHECKED_REGISTRY="$TMP/unchecked-tools.yaml"
cp "$REGISTRY" "$UNCHECKED_REGISTRY"
sed -i '0,/verification: github-release-digest/s//verification: unchecked/' "$UNCHECKED_REGISTRY"
if (
	export SB_TOOLS_YAML="$UNCHECKED_REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_validate_registry >/dev/null 2>&1
); then not_ok "setup-tier unchecked verification is rejected by registry validation"; else ok "setup-tier unchecked verification is rejected by registry validation"; fi

run_github_digest_case() {
	local name=$1 requested=$2 metadata=$3 api_status=${4:-200}
	local case_dir="$TMP/$name"
	mkdir -p "$case_dir/home" "$case_dir/cache"
	(
		export HOME="$case_dir/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
		export SB_GITHUB_API_BASE=https://api.test SB_GH_METADATA_CACHE_DIR="$case_dir/cache"
		export CASE_METADATA="$metadata" CASE_API_STATUS="$api_status" CASE_DIR="$case_dir"
		source "$REPO_ROOT/scripts/lib/tool-lib.sh"
		curl() {
			local output="" url=""
			while [ "$#" -gt 0 ]; do
				case "$1" in
					-w) shift 2 ;;
					-o) output=$2; shift 2 ;;
					-*o) output=$2; shift 2 ;;
					-*) shift ;;
					*) url=$1; shift ;;
				esac
			done
			printf '%s\n' "$url" >> "$CASE_DIR/curl.log"
			if [[ "$url" == https://api.test/* ]]; then
				printf '%s\n%s\n' "$CASE_METADATA" "$CASE_API_STATUS"
			else
				cp "$PAYLOAD" "$output"
			fi
		}
		set +e
		sb_install sample "$requested" >"$case_dir/out" 2>"$case_dir/err"
		printf '%s\n' "$?" > "$case_dir/rc"
		set -e
	)
}

DIGEST_CASE="$TMP/missing-digest"
mkdir -p "$DIGEST_CASE/home"
if (
	export HOME="$DIGEST_CASE/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	export SB_GITHUB_API_BASE=https://api.test
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	curl() {
		local output="" url=""
		while [ "$#" -gt 0 ]; do
			case "$1" in
				-w) shift 2 ;;
				-o) output=$2; shift 2 ;;
				-*o) output=$2; shift 2 ;;
				-*) shift ;;
				*) url=$1; shift ;;
			esac
		done
		if [[ "$url" == */repos/example/sample/releases/tags/v1.0.0 ]]; then
			printf '{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-amd64"}]}\n200\n'
		else
			: > "$DIGEST_CASE/artifact-download-attempted"
			cp "$PAYLOAD" "$output"
		fi
	}
	set +e
	sb_install sample 1.0.0 >"$DIGEST_CASE/out" 2>"$DIGEST_CASE/err"
	rc=$?
	set -e
	[ "$rc" -ne 0 ] \
		&& grep -q 'missing.*SHA-256 digest' "$DIGEST_CASE/err" \
		&& [ ! -e "$DIGEST_CASE/artifact-download-attempted" ] \
		&& [ ! -e "$HOME/.local/bin/sample" ]
); then ok "missing GitHub asset digest fails before download or destination mutation"; else not_ok "missing GitHub asset digest fails before download or destination mutation"; fi

PAYLOAD_HASH=$(sha256sum "$PAYLOAD" | awk '{print $1}')
WRONG_HASH=$(printf wrong | sha256sum | awk '{print $1}')
run_github_digest_case wrong-digest 1.0.0 \
	'{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-amd64","digest":"sha256:'"$WRONG_HASH"'"}]}'
if [ "$(<"$TMP/wrong-digest/rc")" -ne 0 ] \
	&& grep -q 'CHECKSUM MISMATCH' "$TMP/wrong-digest/err" \
	&& [ ! -e "$TMP/wrong-digest/home/.local/bin/sample" ]; then
	ok "wrong GitHub asset digest rejects downloaded bytes before destination mutation"
else
	not_ok "wrong GitHub asset digest rejects downloaded bytes before destination mutation"
fi

if (
	export SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	SB_RESOLVED_TOOL=sample
	SB_RESOLVED_ARTIFACT=sample-1.0.0-amd64
	SB_EXPECTED_ASSET_SHA256=$PAYLOAD_HASH
	! sb_verify "$PAYLOAD" "$SB_RESOLVED_ARTIFACT" packed >/dev/null 2>&1
); then ok "prepared release-asset digest is bound to the resolved tool identity"; else not_ok "prepared release-asset digest is bound to the resolved tool identity"; fi

run_github_digest_case exact-asset 1.0.0 \
	'{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-arm64","digest":"sha256:'"$WRONG_HASH"'"},{"name":"sample-1.0.0-amd64","digest":"sha256:'"$PAYLOAD_HASH"'"}]}'
if [ "$(<"$TMP/exact-asset/rc")" -eq 0 ] \
	&& [ "$("$TMP/exact-asset/home/.local/bin/sample")" = 'sample 2.0.0' ] \
	&& grep -q '/releases/download/v1.0.0/sample-1.0.0-amd64$' "$TMP/exact-asset/curl.log"; then
	ok "exact release tag and exact asset name select the authoritative digest"
else
	not_ok "exact release tag and exact asset name select the authoritative digest"
fi

run_github_digest_case duplicate-asset 1.0.0 \
	'{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-amd64","digest":"sha256:'"$PAYLOAD_HASH"'"},{"name":"sample-1.0.0-amd64","digest":"sha256:'"$PAYLOAD_HASH"'"}]}'
if [ "$(<"$TMP/duplicate-asset/rc")" -ne 0 ] \
	&& grep -q 'expected exactly one release asset' "$TMP/duplicate-asset/err" \
	&& ! grep -q '/releases/download/' "$TMP/duplicate-asset/curl.log"; then
	ok "duplicate exact asset metadata fails before artifact download"
else
	not_ok "duplicate exact asset metadata fails before artifact download"
fi

run_github_digest_case missing-exact-asset 1.0.0 \
	'{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-arm64","digest":"sha256:'"$PAYLOAD_HASH"'"}]}'
if [ "$(<"$TMP/missing-exact-asset/rc")" -ne 0 ] \
	&& grep -q 'expected exactly one release asset named sample-1.0.0-amd64' "$TMP/missing-exact-asset/err" \
	&& ! grep -q '/releases/download/' "$TMP/missing-exact-asset/curl.log"; then
	ok "missing exact asset name fails before artifact download"
else
	not_ok "missing exact asset name fails before artifact download"
fi

run_github_digest_case malformed-digest 1.0.0 \
	'{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-amd64","digest":"sha256:not-a-digest"}]}'
if [ "$(<"$TMP/malformed-digest/rc")" -ne 0 ] \
	&& grep -q 'malformed.*SHA-256 digest' "$TMP/malformed-digest/err" \
	&& ! grep -q '/releases/download/' "$TMP/malformed-digest/curl.log"; then
	ok "malformed GitHub asset digest fails before artifact download"
else
	not_ok "malformed GitHub asset digest fails before artifact download"
fi

run_github_digest_case api-failure 1.0.0 '{"message":"synthetic failure"}' 500
if [ "$(<"$TMP/api-failure/rc")" -ne 0 ] \
	&& grep -q 'HTTP 500' "$TMP/api-failure/err" \
	&& ! grep -q '/releases/download/' "$TMP/api-failure/curl.log" \
	&& [ ! -e "$TMP/api-failure/home/.local/bin/sample" ]; then
	ok "GitHub release metadata API failure prevents artifact download and mutation"
else
	not_ok "GitHub release metadata API failure prevents artifact download and mutation"
fi

FAILURE_CACHE_CASE="$TMP/failure-cache-symlink"
mkdir -p "$FAILURE_CACHE_CASE/home" "$FAILURE_CACHE_CASE/cache"
printf 'preserve me\n' > "$FAILURE_CACHE_CASE/victim"
if (
	export HOME="$FAILURE_CACHE_CASE/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	export SB_GITHUB_API_BASE=https://api.test SB_GH_METADATA_CACHE_DIR="$FAILURE_CACHE_CASE/cache"
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	url=https://api.test/repos/example/sample/releases/latest
	marker=$(_sb_gh_disk_cache_path "$url" failed)
	ln -s "$FAILURE_CACHE_CASE/victim" "$marker"
	curl() { printf '{"message":"synthetic failure"}\n500\n'; }
	set +e; sb_gh_latest_tag example/sample >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] \
		&& [ "$(<"$FAILURE_CACHE_CASE/victim")" = 'preserve me' ] \
		&& [ -f "$marker" ] && [ ! -L "$marker" ]
); then ok "GitHub metadata failure publication replaces a cache symlink without truncating its target"; else not_ok "GitHub metadata failure publication replaces a cache symlink without truncating its target"; fi

run_github_digest_case explicit-tag-mismatch 1.0.0 \
	'{"tag_name":"v1.0.1","assets":[{"name":"sample-1.0.0-amd64","digest":"sha256:'"$PAYLOAD_HASH"'"}]}'
if [ "$(<"$TMP/explicit-tag-mismatch/rc")" -ne 0 ] \
	&& grep -q 'release tag mismatch.*expected v1.0.0, got v1.0.1' "$TMP/explicit-tag-mismatch/err" \
	&& ! grep -q '/releases/download/' "$TMP/explicit-tag-mismatch/curl.log"; then
	ok "explicit version install rejects metadata for a different release tag"
else
	not_ok "explicit version install rejects metadata for a different release tag"
fi

CACHE_CASE="$TMP/metadata-cache"
mkdir -p "$CACHE_CASE/home" "$CACHE_CASE/cache"
if (
	export HOME="$CACHE_CASE/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	export SB_GITHUB_API_BASE=https://api.test SB_GH_METADATA_CACHE_DIR="$CACHE_CASE/cache"
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	curl() {
		local output="" url=""
		while [ "$#" -gt 0 ]; do
			case "$1" in
				-w) shift 2 ;;
				-o) output=$2; shift 2 ;;
				-*o) output=$2; shift 2 ;;
				-*) shift ;;
				*) url=$1; shift ;;
			esac
		done
		printf '%s\n' "$url" >> "$CACHE_CASE/curl.log"
		if [[ "$url" == https://api.test/* ]]; then
			printf '{"tag_name":"v1.0.0","assets":[{"name":"sample-1.0.0-amd64","digest":"sha256:%s"}]}\n200\n' "$PAYLOAD_HASH"
		else
			cp "$PAYLOAD" "$output"
		fi
	}
	version=$(sb_latest_version sample)
	[ "$version" = 1.0.0 ]
	sb_install sample "$version" >/dev/null
	[ "$(grep -c 'api.test/' "$CACHE_CASE/curl.log")" -eq 1 ]
); then ok "release metadata cache survives command substitution and exact-version install"; else not_ok "release metadata cache survives command substitution and exact-version install"; fi

BAD_REGISTRY="$TMP/bad-tools.yaml"
cp "$REGISTRY" "$BAD_REGISTRY"
sed -i '0,/method: binary/s//method: shell-pipe/' "$BAD_REGISTRY"
MARKER="$TMP/network-called"
if run_install_case invalid_metadata '
	SB_TOOLS_YAML="'$BAD_REGISTRY'"
	curl() { : > "'$MARKER'"; return 0; }
	set +e; sb_install sample 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ ! -e "'$MARKER'" ]
'; then ok "invalid method metadata fails before network activity"; else not_ok "invalid method metadata fails before network activity"; fi

VERIFY_DEST="$TMP/verify_reject/home/.local/bin/sample"
mkdir -p "$(dirname "$VERIFY_DEST")"
printf 'old' > "$VERIFY_DEST"
if run_install_case verify_reject '
	curl() { cp "$PAYLOAD" "$2"; }
	sb_verify() { return 42; }
	set +e; sb_install sample 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 42 ] && [ "$(<"$HOME/.local/bin/sample")" = old ]
'; then ok "verification rejection preserves its status and existing destination"; else not_ok "verification rejection preserves its status and existing destination"; fi

if run_install_case verify_no_dest '
	curl() { cp "$PAYLOAD" "$2"; }
	sb_verify() { return 17; }
	set +e; sb_install sample 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 17 ] && [ ! -e "$HOME/.local" ]
'; then ok "verification failure causes no destination mutation"; else not_ok "verification failure causes no destination mutation"; fi

DOWNLOAD_DEST="$TMP/download_fail/home/.local/bin/sample"
mkdir -p "$(dirname "$DOWNLOAD_DEST")"; printf 'old' > "$DOWNLOAD_DEST"
if run_install_case download_fail '
	curl() { return 23; }
	set +e; sb_install sample 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 23 ] && [ "$(<"$HOME/.local/bin/sample")" = old ]
'; then ok "download failure is authoritative and leaves destination unchanged"; else not_ok "download failure is authoritative and leaves destination unchanged"; fi

INSTALL_DEST="$TMP/install_fail/home/.local/bin/sample"
mkdir -p "$(dirname "$INSTALL_DEST")"; printf 'old' > "$INSTALL_DEST"
if run_install_case install_fail '
	curl() { cp "$PAYLOAD" "$2"; }
	install() { return 31; }
	set +e; sb_install sample 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 31 ] && [ "$(<"$HOME/.local/bin/sample")" = old ]
'; then ok "install staging failure preserves status and previous executable"; else not_ok "install staging failure preserves status and previous executable"; fi

if run_install_case successful_install '
	curl() { cp "$PAYLOAD" "$2"; }
	sb_install sample 1.0.0 >/dev/null 2>&1
	[ -x "$HOME/.local/bin/sample" ] && [ "$($HOME/.local/bin/sample)" = "sample 2.0.0" ]
'; then ok "verified and staged binary replaces destination successfully"; else not_ok "verified and staged binary replaces destination successfully"; fi

if run_install_case missing_verifier '
	curl() { cp "$PAYLOAD" "$2"; }
	sb_verify() { return 1; }
	set +e; sb_install pinned 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ ! -e "$HOME/.local/bin/pinned" ]
'; then ok "SHA256 policy fails closed without an authoritative verifier"; else not_ok "SHA256 policy fails closed without an authoritative verifier"; fi

JUNK="$TMP/not-an-archive"; printf 'not a tar archive' > "$JUNK"
EXTRACT_DEST="$TMP/extract_fail/home/.local/bin/packed"
mkdir -p "$(dirname "$EXTRACT_DEST")"; printf 'old' > "$EXTRACT_DEST"
if run_install_case extract_fail '
	curl() { cp "'$JUNK'" "$2"; }
	set +e; sb_install packed 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ "$(<"$HOME/.local/bin/packed")" = old ]
'; then ok "archive read failure prevents destination replacement"; else not_ok "archive read failure prevents destination replacement"; fi

GOOD_TAR_DIR="$TMP/good-tar-source"; mkdir -p "$GOOD_TAR_DIR"
printf '#!/usr/bin/env bash\necho "packed 2.0.0"\n' > "$GOOD_TAR_DIR/packed"; chmod +x "$GOOD_TAR_DIR/packed"
GOOD_TAR="$TMP/good.tar.gz"; tar czf "$GOOD_TAR" -C "$GOOD_TAR_DIR" packed
if run_install_case archive_success '
	curl() { cp "'$GOOD_TAR'" "$2"; }
	sb_install packed 1.0.0 >/dev/null 2>&1
	[ -x "$HOME/.local/bin/packed" ] && [ "$($HOME/.local/bin/packed)" = "packed 2.0.0" ]
'; then ok "verified tar extraction stages and installs its selected executable"; else not_ok "verified tar extraction stages and installs its selected executable"; fi

AMBIG_REGISTRY="$TMP/ambiguous-tools.yaml"
awk '
	$0 == "    tar_extract: packed" { print "    find_binary: true"; next }
	{ print }
' "$REGISTRY" > "$AMBIG_REGISTRY"
AMBIG_ROOT="$TMP/ambiguous-root"
mkdir -p "$AMBIG_ROOT/a" "$AMBIG_ROOT/b"
printf '#!/usr/bin/env bash\necho a\n' > "$AMBIG_ROOT/a/packed"
printf '#!/usr/bin/env bash\necho b\n' > "$AMBIG_ROOT/b/packed"
chmod +x "$AMBIG_ROOT/a/packed" "$AMBIG_ROOT/b/packed"
AMBIG_TAR="$TMP/ambiguous.tar.gz"
tar czf "$AMBIG_TAR" -C "$AMBIG_ROOT" a b
if run_install_case ambiguous_binary '
	SB_TOOLS_YAML="'$AMBIG_REGISTRY'"
	curl() { cp "'$AMBIG_TAR'" "$2"; }
	set +e; sb_install packed 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ ! -e "$HOME/.local/bin/packed" ]
'; then ok "archive with multiple executable matches fails before destination mutation"; else not_ok "archive with multiple executable matches fails before destination mutation"; fi

HELIX_TREE="$TMP/helix-tree/helix-1.0-x86_64-linux"
mkdir -p "$HELIX_TREE/runtime/themes"
printf '#!/usr/bin/env bash\necho "helix 1.0.0"\n' > "$HELIX_TREE/hx"; chmod +x "$HELIX_TREE/hx"
printf 'theme' > "$HELIX_TREE/runtime/themes/test.toml"
HELIX_TAR="$TMP/helix.tar.xz"; tar cJf "$HELIX_TAR" -C "$TMP/helix-tree" helix-1.0-x86_64-linux
if run_install_case tar_xz_success '
	curl() { cp "'$HELIX_TAR'" "$2"; }
	sb_install helixish 1.0.0 >/dev/null 2>&1
	[ "$($HOME/.local/bin/hx)" = "helix 1.0.0" ] && [ "$(<"$HOME/.config/helix/runtime/themes/test.toml")" = theme ]
'; then ok "tar.xz install commits both executable and managed runtime tree"; else not_ok "tar.xz install commits both executable and managed runtime tree"; fi

HELIX_ROLLBACK_HOME="$TMP/helix_runtime_promotion/home"
mkdir -p "$HELIX_ROLLBACK_HOME/.local/bin" "$HELIX_ROLLBACK_HOME/.config/helix/runtime/themes"
printf '#!/usr/bin/env bash\necho old-helix\n' > "$HELIX_ROLLBACK_HOME/.local/bin/hx"
printf 'old-theme\n' > "$HELIX_ROLLBACK_HOME/.config/helix/runtime/themes/test.toml"
chmod +x "$HELIX_ROLLBACK_HOME/.local/bin/hx"
cp -a "$HELIX_ROLLBACK_HOME/.local/bin/hx" "$TMP/helix-hx.before"
cp -a "$HELIX_ROLLBACK_HOME/.config/helix/runtime" "$TMP/helix-runtime.before"
if run_install_case helix_runtime_promotion '
	curl() { cp "'$HELIX_TAR'" "$2"; }
	mv() {
		local last=${!#}
		if [ "$last" = "$HOME/.config/helix/runtime" ] && [ ! -e "$HOME/.helix-promotion-failed" ]; then
			: > "$HOME/.helix-promotion-failed"
			return 57
		fi
		/bin/mv "$@"
	}
	set +e; sb_install helixish 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 57 ] \
		&& cmp -s "'$TMP'/helix-hx.before" "$HOME/.local/bin/hx" \
		&& diff -r "'$TMP'/helix-runtime.before" "$HOME/.config/helix/runtime" >/dev/null
'; then ok "Helix runtime promotion failure restores prior executable and runtime tree"; else not_ok "Helix runtime promotion failure restores prior executable and runtime tree"; fi

ZIP_ROOT="$TMP/zip-root"; mkdir -p "$ZIP_ROOT/zipper-x86_64"
printf '#!/usr/bin/env bash\necho zipper\n' > "$ZIP_ROOT/zipper-x86_64/zipper"
printf '#!/usr/bin/env bash\necho helper\n' > "$ZIP_ROOT/zipper-x86_64/zip-helper"
chmod +x "$ZIP_ROOT/zipper-x86_64/zipper" "$ZIP_ROOT/zipper-x86_64/zip-helper"
ZIP_ARCHIVE="$TMP/zipper.zip"; (cd "$ZIP_ROOT" && zip -qr "$ZIP_ARCHIVE" zipper-x86_64)
if run_install_case zip_success '
	curl() { cp "'$ZIP_ARCHIVE'" "$2"; }
	sb_install zipper 1.0.0 >/dev/null 2>&1
	[ "$($HOME/.local/bin/zipper)" = zipper ] && [ "$($HOME/.local/bin/zip-helper)" = helper ]
'; then ok "zip install validates all selected binaries before committing them"; else not_ok "zip install validates all selected binaries before committing them"; fi

if run_install_case zip_directory_collision '
	mkdir -p "$HOME/.local/bin/zip-helper/keep"
	printf "user data\n" > "$HOME/.local/bin/zip-helper/keep/marker"
	curl() { cp "'$ZIP_ARCHIVE'" "$2"; }
	set +e; sb_install zipper 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] \
		&& [ ! -e "$HOME/.local/bin/zipper" ] \
		&& [ "$(<"$HOME/.local/bin/zip-helper/keep/marker")" = "user data" ]
'; then ok "file-output install refuses a directory collision without deleting user data"; else not_ok "file-output install refuses a directory collision without deleting user data"; fi

ZIP_ROLLBACK_HOME="$TMP/zip_second_promotion/home/.local/bin"
mkdir -p "$ZIP_ROLLBACK_HOME"
printf '#!/usr/bin/env bash\necho old-zipper\n' > "$ZIP_ROLLBACK_HOME/zipper"
printf '#!/usr/bin/env bash\necho old-helper\n' > "$ZIP_ROLLBACK_HOME/zip-helper"
chmod +x "$ZIP_ROLLBACK_HOME/zipper" "$ZIP_ROLLBACK_HOME/zip-helper"
cp -a "$ZIP_ROLLBACK_HOME/zipper" "$TMP/zipper.before"
cp -a "$ZIP_ROLLBACK_HOME/zip-helper" "$TMP/zip-helper.before"
if run_install_case zip_second_promotion '
	curl() { cp "'$ZIP_ARCHIVE'" "$2"; }
	mv() {
		local last=${!#}
		if [ "$last" = "$HOME/.local/bin/zip-helper" ] && [ ! -e "$HOME/.zip-promotion-failed" ]; then
			: > "$HOME/.zip-promotion-failed"
			return 55
		fi
		/bin/mv "$@"
	}
	set +e; sb_install zipper 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 55 ] \
		&& cmp -s "'$TMP'/zipper.before" "$HOME/.local/bin/zipper" \
		&& cmp -s "'$TMP'/zip-helper.before" "$HOME/.local/bin/zip-helper"
'; then ok "second zip output promotion failure restores every prior executable"; else not_ok "second zip output promotion failure restores every prior executable"; fi

CONCURRENT_ROOT="$TMP/concurrent-zip"
mkdir -p "$CONCURRENT_ROOT/a/zipper-x86_64" "$CONCURRENT_ROOT/b/zipper-x86_64" \
	"$CONCURRENT_ROOT/home" "$CONCURRENT_ROOT/barrier"
printf '#!/usr/bin/env bash\necho a\n' > "$CONCURRENT_ROOT/a/zipper-x86_64/zipper"
printf '#!/usr/bin/env bash\necho a\n' > "$CONCURRENT_ROOT/a/zipper-x86_64/zip-helper"
printf '#!/usr/bin/env bash\necho b\n' > "$CONCURRENT_ROOT/b/zipper-x86_64/zipper"
printf '#!/usr/bin/env bash\necho b\n' > "$CONCURRENT_ROOT/b/zipper-x86_64/zip-helper"
chmod +x "$CONCURRENT_ROOT"/{a,b}/zipper-x86_64/{zipper,zip-helper}
(cd "$CONCURRENT_ROOT/a" && zip -qr "$CONCURRENT_ROOT/a.zip" zipper-x86_64)
(cd "$CONCURRENT_ROOT/b" && zip -qr "$CONCURRENT_ROOT/b.zip" zipper-x86_64)
concurrent_zip_install() (
	local role=$1 archive=$2
	export HOME="$CONCURRENT_ROOT/home" SB_TOOLS_YAML="$REGISTRY" SB_DPKG_ARCH=amd64
	export SB_GH_METADATA_CACHE_DIR="$CONCURRENT_ROOT/cache-$role"
	source "$REPO_ROOT/scripts/lib/tool-lib.sh"
	sb_prepare_release_asset() {
		SB_RESOLVED_VERSION=1.0.0
		SB_RESOLVED_TAG=v1.0.0
		SB_RESOLVED_ARTIFACT=$(sb_artifact zipper 1.0.0)
		SB_RESOLVED_URL=https://artifacts.test/zipper.zip
		SB_EXPECTED_ASSET_SHA256=$(printf fixture | sha256sum | awk '{print $1}')
	}
	sb_verify() { return 0; }
	curl() { cp "$archive" "$2"; }
	if [ "$role" = a ]; then
		mv() {
			local last=${!#}
			/bin/mv "$@" || return $?
			if [ "$last" = "$HOME/.local/bin/zipper" ]; then
				: > "$CONCURRENT_ROOT/barrier/a-first"
				while [ ! -e "$CONCURRENT_ROOT/barrier/b-started" ]; do sleep 0.01; done
				local attempts=0
				while [ ! -e "$CONCURRENT_ROOT/barrier/b-done" ] && [ "$attempts" -lt 100 ]; do
					sleep 0.01; attempts=$((attempts + 1))
				done
			fi
		}
		sb_install zipper 1.0.0 >/dev/null 2>&1
	else
		while [ ! -e "$CONCURRENT_ROOT/barrier/a-first" ]; do sleep 0.01; done
		: > "$CONCURRENT_ROOT/barrier/b-started"
		sb_install zipper 1.0.0 >/dev/null 2>&1 || return $?
		: > "$CONCURRENT_ROOT/barrier/b-done"
	fi
)
concurrent_zip_install a "$CONCURRENT_ROOT/a.zip" & CONCURRENT_A=$!
concurrent_zip_install b "$CONCURRENT_ROOT/b.zip" & CONCURRENT_B=$!
if wait "$CONCURRENT_A" && wait "$CONCURRENT_B" \
	&& [ "$("$CONCURRENT_ROOT/home/.local/bin/zipper")" = \
		"$("$CONCURRENT_ROOT/home/.local/bin/zip-helper")" ]; then
	ok "concurrent multi-output installs serialize and cannot publish mixed releases"
else
	not_ok "concurrent multi-output installs serialize and cannot publish mixed releases"
fi

TREE_ROOT="$TMP/tree-root/treeish-x86_64/bin"; mkdir -p "$TREE_ROOT"
printf '#!/usr/bin/env bash\necho treeish\n' > "$TREE_ROOT/treeish"; chmod +x "$TREE_ROOT/treeish"
TREE_ARCHIVE="$TMP/treeish.tar.gz"; tar czf "$TREE_ARCHIVE" -C "$TMP/tree-root" treeish-x86_64
if run_install_case tree_success '
	curl() { cp "'$TREE_ARCHIVE'" "$2"; }
	sb_install treeish 1.0.0 >/dev/null 2>&1
	[ -L "$HOME/.local/bin/treeish" ] && [ "$($HOME/.local/bin/treeish)" = treeish ]
'; then ok "tree install transaction replaces its managed tree and entry symlink"; else not_ok "tree install transaction replaces its managed tree and entry symlink"; fi

UNSAFE_TREE_ROOT="$TMP/unsafe-tree-root/treeish-x86_64/bin"
mkdir -p "$UNSAFE_TREE_ROOT"
cp "$TREE_ROOT/treeish" "$UNSAFE_TREE_ROOT/treeish"
ln -s /tmp/squarebox-outside "$TMP/unsafe-tree-root/treeish-x86_64/outside-link"
UNSAFE_TREE_ARCHIVE="$TMP/unsafe-treeish.tar.gz"
tar czf "$UNSAFE_TREE_ARCHIVE" -C "$TMP/unsafe-tree-root" treeish-x86_64
if run_install_case unsafe_tree_link '
	curl() { cp "'$UNSAFE_TREE_ARCHIVE'" "$2"; }
	set +e; sb_install treeish 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ ! -e "$HOME/.local/treeish" ] && [ ! -e "$HOME/.local/bin/treeish" ]
'; then ok "archive tree with an escaping symlink fails before destination mutation"; else not_ok "archive tree with an escaping symlink fails before destination mutation"; fi

TREE_ROLLBACK_HOME="$TMP/tree_symlink_promotion/home"
mkdir -p "$TREE_ROLLBACK_HOME/.local/treeish/bin" "$TREE_ROLLBACK_HOME/.local/bin"
printf '#!/usr/bin/env bash\necho old-treeish\n' > "$TREE_ROLLBACK_HOME/.local/treeish/bin/treeish"
printf 'prior-tree\n' > "$TREE_ROLLBACK_HOME/.local/treeish/prior-marker"
chmod +x "$TREE_ROLLBACK_HOME/.local/treeish/bin/treeish"
ln -s "$TREE_ROLLBACK_HOME/.local/treeish/bin/treeish" "$TREE_ROLLBACK_HOME/.local/bin/treeish"
cp -a "$TREE_ROLLBACK_HOME/.local/treeish" "$TMP/treeish.before"
if run_install_case tree_symlink_promotion '
	curl() { cp "'$TREE_ARCHIVE'" "$2"; }
	prior_link=$(readlink "$HOME/.local/bin/treeish")
	mv() {
		local last=${!#}
		if [ "$last" = "$HOME/.local/bin/treeish" ] && [ ! -e "$HOME/.tree-link-promotion-failed" ]; then
			: > "$HOME/.tree-link-promotion-failed"
			return 59
		fi
		/bin/mv "$@"
	}
	set +e; sb_install treeish 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -eq 59 ] \
		&& diff -r "'$TMP'/treeish.before" "$HOME/.local/treeish" >/dev/null \
		&& [ "$(readlink "$HOME/.local/bin/treeish")" = "$prior_link" ]
'; then ok "tree entry-symlink promotion failure restores prior tree and link"; else not_ok "tree entry-symlink promotion failure restores prior tree and link"; fi

TRAVERSAL_DIR="$TMP/traversal-source"; mkdir -p "$TRAVERSAL_DIR"; printf '#!/bin/sh\n' > "$TRAVERSAL_DIR/packed"; chmod +x "$TRAVERSAL_DIR/packed"
TRAVERSAL_TAR="$TMP/traversal.tar.gz"
tar czf "$TRAVERSAL_TAR" --transform='s|^|../|' -C "$TRAVERSAL_DIR" packed 2>/dev/null
if run_install_case traversal '
	curl() { cp "'$TRAVERSAL_TAR'" "$2"; }
	set +e; sb_install packed 1.0.0 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] && [ ! -e "$HOME/.local/bin/packed" ] && [ ! -e "'$TMP'/packed" ]
'; then ok "archive parent traversal is rejected before extraction"; else not_ok "archive parent traversal is rejected before extraction"; fi

VERIFY_FILE="$TMP/verify-file"; printf 'contents' > "$VERIFY_FILE"
VERIFY_NAME='artifact[1].bin'
VERIFY_HASH=$(sha256sum "$VERIFY_FILE" | awk '{print $1}')
VERIFY_MANIFEST="$TMP/checksums.txt"
printf '%s  %s\n' "$VERIFY_HASH" "$VERIFY_NAME" > "$VERIFY_MANIFEST"
if "$REPO_ROOT/scripts/verify-checksum.sh" "$VERIFY_FILE" "$VERIFY_NAME" "$VERIFY_MANIFEST"; then
	ok "checksum lookup compares artifact names as fixed fields"
else not_ok "checksum lookup compares artifact names as fixed fields"; fi

MISSING_ERR="$TMP/missing.err"
if "$REPO_ROOT/scripts/verify-checksum.sh" "$VERIFY_FILE" absent.bin "$VERIFY_MANIFEST" 2>"$MISSING_ERR"; then
	not_ok "missing checksum is rejected with the intended diagnostic"
elif grep -Fq "No checksum entry found for 'absent.bin'" "$MISSING_ERR"; then
	ok "missing checksum is rejected with the intended diagnostic"
else not_ok "missing checksum is rejected with the intended diagnostic"; fi

printf '%s  %s\n' "$VERIFY_HASH" "$VERIFY_NAME" >> "$VERIFY_MANIFEST"
if "$REPO_ROOT/scripts/verify-checksum.sh" "$VERIFY_FILE" "$VERIFY_NAME" "$VERIFY_MANIFEST" >/dev/null 2>&1; then
	not_ok "duplicate checksum entries are rejected as ambiguous"
else ok "duplicate checksum entries are rejected as ambiguous"; fi

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]

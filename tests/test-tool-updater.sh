#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPDATER="$REPO_ROOT/scripts/squarebox-update.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
assert_true() { if eval "$1"; then ok "$2"; else not_ok "$2"; fi; }

REGISTRY="$TMP/tools.yaml"
cat > "$REGISTRY" <<'YAML'
tools:
  yq:
    repo: example/yq
    version_prefix: v
    artifact: yq-{version}-{dpkg_arch}
    method: binary
    binaries: yq
    dest: user
    group: setup
    verification: github-release-digest
  delta:
    repo: example/delta
    version_prefix: ""
    artifact: delta-{version}-{dpkg_arch}
    method: binary
    binaries: delta
    dest: system
    group: dockerfile
    verification: sha256
    docker_arg: DELTA_VERSION
  assettool:
    repo: example/assettool
    version_prefix: v
    artifact: assettool-{asset_version}-{zarch}
    method: binary
    binaries: assettool
    asset_version_from_api: true
    dest: user
    group: setup
    verification: github-release-digest
YAML

YQ_PAYLOAD="$TMP/yq-payload"
cat > "$YQ_PAYLOAD" <<'SH'
#!/usr/bin/env bash
echo "yq (test) version v2.0.0"
SH
DELTA_PAYLOAD="$TMP/delta-payload"
cat > "$DELTA_PAYLOAD" <<'SH'
#!/usr/bin/env bash
echo "delta 2.0.0"
SH
chmod +x "$YQ_PAYLOAD" "$DELTA_PAYLOAD"
ASSET_PAYLOAD="$TMP/asset-payload"
cat > "$ASSET_PAYLOAD" <<'SH'
#!/usr/bin/env bash
echo "assettool 8.1.2"
SH
chmod +x "$ASSET_PAYLOAD"
WRONG_YQ_PAYLOAD="$TMP/yq-wrong-version-payload"
cat > "$WRONG_YQ_PAYLOAD" <<'SH'
#!/usr/bin/env bash
echo "yq (test) version v3.0.0"
SH
chmod +x "$WRONG_YQ_PAYLOAD"
YAZI_ROOT="$TMP/yazi-root/yazi-x86_64"
mkdir -p "$YAZI_ROOT"
printf '#!/usr/bin/env bash\necho "yazi 2.0.0"\n' > "$YAZI_ROOT/yazi"
printf '#!/usr/bin/env bash\necho "ya 2.0.0"\n' > "$YAZI_ROOT/ya"
chmod +x "$YAZI_ROOT/yazi" "$YAZI_ROOT/ya"
YAZI_ARCHIVE="$TMP/yazi.zip"
(cd "$TMP/yazi-root" && zip -qr "$YAZI_ARCHIVE" yazi-x86_64)

GOOD_CHECKSUMS="$TMP/checksums-good.txt"
BAD_CHECKSUMS="$TMP/checksums-bad.txt"
DELTA_HASH=$(sha256sum "$DELTA_PAYLOAD" | awk '{print $1}')
printf '%s  delta-2.0.0-amd64\n' "$DELTA_HASH" > "$GOOD_CHECKSUMS"
printf '%064d  delta-2.0.0-amd64\n' 0 > "$BAD_CHECKSUMS"

FAKE_CURL="$TMP/curl"
cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
set -u
output=""
url=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-w) shift 2 ;;
		-o) output=$2; shift 2 ;;
		-*o) output=$2; shift 2 ;;
		-*) shift ;;
		*) url=$1; shift ;;
	esac
done
printf '%s\n' "$url" >> "$FAKE_CURL_LOG"
if [[ "$url" == *'/repos/example/yq/releases/latest' ]]; then
	if [ "${FAKE_API_FAIL_REPO:-}" = yq ]; then
		printf '{"message":"synthetic failure"}\n500\n'
	else
		printf '{"tag_name":"v2.0.0","assets":[{"name":"yq-2.0.0-amd64","digest":"%s"}]}\n200\n' "$FAKE_YQ_DIGEST"
	fi
elif [[ "$url" == *'/repos/example/delta/releases/latest' ]]; then
	if [ "${FAKE_API_FAIL_REPO:-}" = delta ]; then
		printf '{"message":"synthetic failure"}\n500\n'
	else
		delta_hash=$(sha256sum "$FAKE_DELTA_PAYLOAD" | awk '{print $1}')
		printf '{"tag_name":"2.0.0","assets":['
		printf '{"name":"delta-2.0.0-amd64","digest":"sha256:%s"},' "$delta_hash"
		printf '{"name":"delta-amd64","digest":"sha256:%s"}]}\n200\n' "$delta_hash"
	fi
elif [[ "$url" == *'/repos/example/assettool/releases/latest' ]]; then
	printf '{"tag_name":"v9.0.0","assets":[{"name":"assettool-8.1.2-x86_64","digest":"sha256:%s"}]}\n200\n' "$FAKE_ASSET_HASH"
elif [[ "$url" == *'/repos/example/assettool/releases/tags/v9.0.0' ]]; then
	printf '{"tag_name":"v9.0.0","assets":[{"name":"assettool-8.1.2-x86_64","digest":"sha256:%s"}]}\n200\n' "$FAKE_ASSET_HASH"
elif [[ "$url" == *'/example/yq/releases/download/'* ]]; then
	cp "$FAKE_YQ_PAYLOAD" "$output"
elif [[ "$url" == *'/example/delta/releases/download/'* ]]; then
	cp "$FAKE_DELTA_PAYLOAD" "$output"
elif [[ "$url" == *'/example/assettool/releases/download/'* ]]; then
	cp "$FAKE_ASSET_PAYLOAD" "$output"
elif [[ "$url" == *'/repos/example/yazi/releases/latest' ]]; then
	printf '{"tag_name":"v2.0.0","assets":[{"name":"yazi-x86_64.zip","digest":"sha256:%s"}]}\n200\n' "$FAKE_YAZI_HASH"
elif [[ "$url" == *'/repos/example/yazi/releases/tags/v2.0.0' ]]; then
	printf '{"tag_name":"v2.0.0","assets":[{"name":"yazi-x86_64.zip","digest":"sha256:%s"}]}\n200\n' "$FAKE_YAZI_HASH"
elif [[ "$url" == *'/example/yazi/releases/download/'* ]]; then
	cp "$FAKE_YAZI_ARCHIVE" "$output"
elif [[ "$url" == *'/repos/example/helix/releases/latest' ]]; then
	printf '{"tag_name":"2.0.0"}\n200\n'
elif [[ "$url" == *'/repos/example/nvim/releases/latest' ]]; then
	printf '{"tag_name":"v2.0.0"}\n200\n'
elif [ "$url" = "$FAKE_CHECKSUM_URL" ]; then
	cp "$FAKE_CHECKSUM_FILE" "$output"
else
	echo "fake curl: unexpected URL: $url" >&2
	exit 67
fi
SH
chmod +x "$FAKE_CURL"

new_case() {
	local name=$1 dir="$TMP/$1"
	mkdir -p "$dir/home" "$dir/bin" "$dir/logs"
	cp "$FAKE_CURL" "$dir/bin/curl"
	cat > "$dir/bin/id" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = -u ]; then printf '0\n'; else exec /usr/bin/id "$@"; fi
SH
	chmod +x "$dir/bin/id"
	printf 'dev\n' > "$dir/VERSION"
	printf '%s\n' "$dir"
}

install_observed() {
	local dir=$1 tool=$2 version=$3 path
	path=$tool
	[ "$tool" != delta ] || path=delta
	if [ "$tool" = yq ]; then
		printf '#!/usr/bin/env bash\necho "yq (test) version v%s"\n' "$version" > "$dir/bin/$path"
	else
		printf '#!/usr/bin/env bash\necho "delta %s"\n' "$version" > "$dir/bin/$path"
	fi
	chmod +x "$dir/bin/$path"
}

run_updater() {
	local dir=$1; shift
	local mode=${CASE_CHECKSUM_MODE:-explicit}
	local expected_url=${CASE_EXPECTED_CHECKSUM_URL:-https://checksums.test/manifest}
	local -a environment=(
		HOME="$dir/home" \
		PATH="$dir/home/.local/bin:$dir/bin:$PATH" \
		NO_COLOR=1 \
			SB_TOOLS_YAML="${CASE_REGISTRY:-$REGISTRY}" \
		SB_TOOL_LIB="$REPO_ROOT/scripts/lib/tool-lib.sh" \
		SB_DPKG_ARCH=amd64 \
		SB_GITHUB_API_BASE=https://api.test \
		SB_REPO_RAW_BASE=https://raw.test/squarebox \
		SB_VERSION_FILE="$dir/VERSION" \
		SB_SOURCE_REF_FILE="$dir/no-source-ref" \
		SB_SOURCE_SHA_FILE="$dir/no-source-sha" \
			SB_BAKED_CHECKSUMS="${CASE_BAKED_CHECKSUMS:-$dir/no-baked-manifest}" \
			SB_SYSTEM_BIN_DIR="$dir/home/.local/bin" \
		SB_UPDATE_LOG_DIR="$dir/logs" \
		FAKE_CURL_LOG="$dir/curl.log" \
			FAKE_YQ_PAYLOAD="${CASE_YQ_PAYLOAD:-$YQ_PAYLOAD}" \
		FAKE_DELTA_PAYLOAD="$DELTA_PAYLOAD" \
			FAKE_ASSET_PAYLOAD="$ASSET_PAYLOAD" \
			FAKE_YAZI_ARCHIVE="$YAZI_ARCHIVE" \
			FAKE_YAZI_HASH="$(sha256sum "$YAZI_ARCHIVE" | awk '{print $1}')" \
			FAKE_YQ_HASH="$(sha256sum "${CASE_YQ_PAYLOAD:-$YQ_PAYLOAD}" | awk '{print $1}')" \
			FAKE_YQ_DIGEST="${CASE_YQ_DIGEST:-sha256:$(sha256sum "${CASE_YQ_PAYLOAD:-$YQ_PAYLOAD}" | awk '{print $1}')}" \
		FAKE_ASSET_HASH="$(sha256sum "$ASSET_PAYLOAD" | awk '{print $1}')" \
		FAKE_CHECKSUM_URL="$expected_url" \
		FAKE_CHECKSUM_FILE="${CASE_CHECKSUM_FILE:-$GOOD_CHECKSUMS}" \
		FAKE_API_FAIL_REPO="${CASE_API_FAIL_REPO:-}" \
		SQUAREBOX_SOURCE_REF="${CASE_SOURCE_REF:-}" \
		SQUAREBOX_SOURCE_SHA="${CASE_SOURCE_SHA:-}"
	)
	if [ "$mode" = explicit ]; then
		environment+=(SB_CHECKSUMS_URL=https://checksums.test/manifest)
	fi
	env -u SB_CHECKSUMS_URL -u SQUAREBOX_SOURCE_REF -u SQUAREBOX_SOURCE_SHA \
		"${environment[@]}" "$UPDATER" "$@"
}

CASE=$(new_case dry_run)
install_observed "$CASE" yq 1.0.0
if run_updater "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'delta.*not installed (skipped)' '$CASE/out'" "bulk dry run skips an absent optional/image tool"
	assert_true "[ \"\$(grep -c '/repos/example/yq/releases/latest' '$CASE/curl.log')\" -eq 1 ] && ! grep -q '/repos/example/delta/releases/latest' '$CASE/curl.log'" "bulk dry run fetches metadata once and only for observed tools"
	assert_true "grep -q '1 installed tool update(s) available' '$CASE/out'" "dry run reports only installed-tool updates"
else
	not_ok "bulk dry run completes for checkable installed tools"
fi

CASE=$(new_case image_tier_unvetted)
install_observed "$CASE" delta 1.0.0
install_observed "$CASE" yq 2.0.0
FIXED_REGISTRY="$CASE/tools-fixed-name.yaml"
sed 's/artifact: delta-{version}-{dpkg_arch}/artifact: delta-{dpkg_arch}/' "$REGISTRY" > "$FIXED_REGISTRY"
FIXED_CHECKSUMS="$CASE/checksums-old-candidate.txt"
OLD_DELTA_HASH=$(sha256sum "$CASE/bin/delta" | awk '{print $1}')
printf '%s  delta-amd64\n' "$OLD_DELTA_HASH" > "$FIXED_CHECKSUMS"
CASE_REGISTRY=$FIXED_REGISTRY
CASE_CHECKSUM_FILE=$FIXED_CHECKSUMS
if run_updater "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'delta.*new Candidate required' '$CASE/out'" "dry run identifies an upstream image-tier release that its Candidate cannot authorize"
	assert_true "! grep -q 'installed tool update(s) available' '$CASE/out' && ! grep -q '/example/delta/releases/download/' '$CASE/curl.log'" "unvetted image-tier release is neither advertised as applyable nor downloaded"
else
	not_ok "unvetted image-tier release remains a successful, truthful dry-run result"
fi
unset CASE_REGISTRY CASE_CHECKSUM_FILE

CASE=$(new_case apply)
install_observed "$CASE" yq 1.0.0
if run_updater "$CASE" --apply >"$CASE/out" 2>"$CASE/err"; then
	assert_true "[ -x '$CASE/home/.local/bin/yq' ] && [ \"\$('$CASE/home/.local/bin/yq')\" = 'yq (test) version v2.0.0' ]" "bulk apply updates an observed tool"
	assert_true "[ ! -e '$CASE/home/.local/bin/delta' ]" "bulk apply does not install an absent tool"
	assert_true "[ \"\$(grep -c '/repos/example/yq/releases/latest' '$CASE/curl.log')\" -eq 1 ]" "apply reuses cached release metadata"
	assert_true "grep -q 'GitHub asset SHA256 required' '$CASE/out'" "GitHub release-asset digest policy is explicit during install"
else
	not_ok "bulk apply succeeds for a GitHub-digest-verified observed tool"
fi

CASE=$(new_case github_digest_reject)
install_observed "$CASE" yq 1.0.0
CASE_YQ_DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000
if run_updater "$CASE" yq >"$CASE/out" 2>"$CASE/err"; then
	not_ok "wrong GitHub release-asset digest makes a single-tool update fail"
else
	assert_true "[ ! -e '$CASE/home/.local/bin/yq' ] && [ \"\$('$CASE/bin/yq')\" = 'yq (test) version v1.0.0' ]" "GitHub digest rejection leaves prior observed executable unchanged"
	LOG_PATH=$(sed -n 's/.*Diagnostic log preserved at //p' "$CASE/err" | tail -1)
	assert_true "[ -n '$LOG_PATH' ] && grep -q 'CHECKSUM MISMATCH' '$LOG_PATH'" "updater preserves GitHub digest failure diagnostics"
	rm -f -- "$LOG_PATH"
fi
unset CASE_YQ_DIGEST

CASE=$(new_case post_install_version_mismatch)
install_observed "$CASE" yq 1.0.0
CASE_YQ_PAYLOAD=$WRONG_YQ_PAYLOAD
if run_updater "$CASE" yq >"$CASE/out" 2>"$CASE/err"; then
	not_ok "post-install version mismatch makes an update fail"
else
	assert_true "[ ! -e '$CASE/home/.local/bin/yq' ] && [ \"\$('$CASE/bin/yq')\" = 'yq (test) version v1.0.0' ]" "post-install version mismatch restores the complete prior managed output"
	LOG_PATH=$(sed -n 's/.*Diagnostic log preserved at //p' "$CASE/err" | tail -1)
	assert_true "[ -n '$LOG_PATH' ] && grep -q 'post-install version.*expected 2.0.0' '$LOG_PATH'" "rolled-back version mismatch remains diagnosable"
	rm -f -- "$LOG_PATH"
fi
unset CASE_YQ_PAYLOAD

CASE=$(new_case broken_probe_repair)
printf '#!/usr/bin/env bash\nexit 1\n' > "$CASE/bin/yq"
chmod +x "$CASE/bin/yq"
if run_updater "$CASE" yq >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'yq.*broken.*repair' '$CASE/out' && [ \"\$('$CASE/home/.local/bin/yq')\" = 'yq (test) version v2.0.0' ]" "explicit update repairs an observed binary whose version probe is broken"
else
	not_ok "broken observed binary is repairable through an explicit update"
fi

CASE=$(new_case current)
install_observed "$CASE" yq 2.0.0
if run_updater "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'up to date.*GitHub asset SHA256 required' '$CASE/out'" "current version and release-asset digest policy are distinct statuses"
	assert_true "grep -q 'All installed tools are up to date' '$CASE/out'" "accurate current summary is emitted when every observed tool was checked"
else
	not_ok "current installed tool check succeeds"
fi

CASE=$(new_case incomplete_yazi)
YAZI_REGISTRY="$CASE/yazi-tools.yaml"
cat > "$YAZI_REGISTRY" <<'YAML'
tools:
  yazi:
    repo: example/yazi
    version_prefix: v
    artifact: yazi-{zarch}.zip
    method: zip
    binaries: yazi,ya
    zip_subdir: yazi-{zarch}
    dest: user
    group: setup
    verification: github-release-digest
YAML
printf '#!/usr/bin/env bash\necho "yazi 2.0.0"\n' > "$CASE/bin/yazi"
chmod +x "$CASE/bin/yazi"
CASE_REGISTRY=$YAZI_REGISTRY
if run_updater "$CASE" --apply >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'yazi.*incomplete.*repair' '$CASE/out'" "current Yazi with a missing managed secondary output is scheduled for repair"
	assert_true "[ \"\$('$CASE/home/.local/bin/yazi')\" = 'yazi 2.0.0' ] && [ \"\$('$CASE/home/.local/bin/ya')\" = 'ya 2.0.0' ]" "Yazi repair transaction restores both managed outputs"
else
	not_ok "incomplete Yazi output set is repairable through bulk apply"
fi
unset CASE_REGISTRY

CASE=$(new_case incomplete_trees)
TREE_REGISTRY="$CASE/tree-tools.yaml"
cat > "$TREE_REGISTRY" <<'YAML'
tools:
  helix:
    repo: example/helix
    version_prefix: ""
    artifact: helix-{version}-{zarch}.tar.xz
    method: tar.xz
    binaries: hx
    find_binary: true
    post_install: helix_runtime
    dest: user
    group: setup
    verification: github-release-digest
  nvim:
    repo: example/nvim
    version_prefix: v
    artifact: nvim-{zarch}.tar.gz
    method: tar.gz-tree
    binaries: nvim
    tree_name: nvim-{zarch}
    tree_dest: ~/.local/nvim
    symlink: ~/.local/nvim/bin/nvim
    dest: user
    group: setup
    verification: github-release-digest
YAML
printf '#!/usr/bin/env bash\necho "helix 2.0.0"\n' > "$CASE/bin/hx"
printf '#!/usr/bin/env bash\necho "NVIM v2.0.0"\n' > "$CASE/bin/nvim"
chmod +x "$CASE/bin/hx" "$CASE/bin/nvim"
CASE_REGISTRY=$TREE_REGISTRY
if run_updater "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q 'helix.*incomplete.*repair' '$CASE/out' && grep -q 'nvim.*incomplete.*repair' '$CASE/out'" "missing Helix runtime and Neovim managed tree/link are both reported as repairable incomplete state"
	assert_true "grep -q '2 installed tool update(s) available' '$CASE/out'" "every incomplete multi-output tool enters the applyable repair set"
else
	not_ok "incomplete Helix and Neovim state remains a successful dry-run result"
fi
unset CASE_REGISTRY

CASE=$(new_case explicit_install)
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "[ -x '$CASE/home/.local/bin/delta' ] && [ \"\$('$CASE/home/.local/bin/delta')\" = 'delta 2.0.0' ]" "explicitly naming an absent tool installs it"
	assert_true "grep -q 'SHA256 required' '$CASE/out' && grep -q 'checksums.test/manifest' '$CASE/curl.log'" "explicit image-tier install requires its checksum manifest"
	assert_true "grep -q 'Release source binding is bypassed' '$CASE/err'" "explicit checksum URL override is disclosed"
else
	not_ok "explicit absent image-tier tool install succeeds with a vetted checksum"
fi

CASE=$(new_case release_bound)
printf 'v1.1.0-rc5\n' > "$CASE/VERSION"
CASE_CHECKSUM_MODE=bound
CASE_EXPECTED_CHECKSUM_URL=https://raw.test/squarebox/v1.1.0-rc5/checksums.txt
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -qxF '$CASE_EXPECTED_CHECKSUM_URL' '$CASE/curl.log' && ! grep -q '/main/checksums.txt' '$CASE/curl.log'" "Candidate release version binds checksum retrieval to its immutable source ref"
	assert_true "grep -q 'Checksum source: Candidate source v1.1.0-rc5' '$CASE/out'" "release-bound checksum identity is visible"
else
	not_ok "version-derived Release checksum binding succeeds"
fi
unset CASE_CHECKSUM_MODE CASE_EXPECTED_CHECKSUM_URL

CASE=$(new_case recorded_ref)
printf 'v1.1.0\n' > "$CASE/VERSION"
CASE_CHECKSUM_MODE=bound
CASE_SOURCE_REF=v1.1.0-rc5
CASE_EXPECTED_CHECKSUM_URL=https://raw.test/squarebox/v1.1.0-rc5/checksums.txt
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -qxF '$CASE_EXPECTED_CHECKSUM_URL' '$CASE/curl.log'" "validated recorded source ref takes precedence over baked version metadata"
	assert_true "grep -q 'Checksum source: recorded immutable source v1.1.0-rc5' '$CASE/out'" "recorded immutable source is reported"
else
	not_ok "recorded immutable source checksum binding succeeds"
fi
unset CASE_CHECKSUM_MODE CASE_SOURCE_REF CASE_EXPECTED_CHECKSUM_URL

CASE=$(new_case edge_sha)
printf 'v1.1.0-rc4-4-g8be776b\n' > "$CASE/VERSION"
CASE_CHECKSUM_MODE=bound
CASE_SOURCE_REF=refs/remotes/origin/main
CASE_SOURCE_SHA=cccccccccccccccccccccccccccccccccccccccc
CASE_EXPECTED_CHECKSUM_URL=https://raw.test/squarebox/cccccccccccccccccccccccccccccccccccccccc/checksums.txt
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -qxF '$CASE_EXPECTED_CHECKSUM_URL' '$CASE/curl.log'" "edge Candidate uses its full pinned source SHA instead of mutable branch identity"
	assert_true "grep -q 'not immutable; using pinned edge source SHA' '$CASE/err'" "mutable edge source replacement is disclosed"
else
	not_ok "pinned edge source-SHA checksum binding succeeds"
fi
unset CASE_CHECKSUM_MODE CASE_SOURCE_REF CASE_SOURCE_SHA CASE_EXPECTED_CHECKSUM_URL

CASE=$(new_case legacy_source)
CASE_CHECKSUM_MODE=bound
CASE_EXPECTED_CHECKSUM_URL=https://raw.test/squarebox/main/checksums.txt
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -qxF '$CASE_EXPECTED_CHECKSUM_URL' '$CASE/curl.log'" "legacy Candidate retains an explicit compatibility checksum path"
	assert_true "grep -q 'WARNING: legacy checksum fallback is using mutable main' '$CASE/err' && grep -q 'LEGACY mutable main fallback' '$CASE/out'" "mutable legacy fallback is never silent or represented as Release-bound"
else
	not_ok "legacy checksum compatibility path remains available"
fi
unset CASE_CHECKSUM_MODE CASE_EXPECTED_CHECKSUM_URL

CASE=$(new_case baked_manifest)
CASE_CHECKSUM_MODE=bound
CASE_BAKED_CHECKSUMS=$GOOD_CHECKSUMS
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	assert_true "! grep -q 'raw.test/squarebox' '$CASE/curl.log' && grep -q 'manifest baked into this Candidate image' '$CASE/out'" "baked checksum manifest avoids mutable or release-network retrieval"
	assert_true "! grep -q 'legacy checksum fallback' '$CASE/err'" "baked checksum authority suppresses legacy fallback"
else
	not_ok "baked checksum manifest is authoritative"
fi
unset CASE_CHECKSUM_MODE CASE_BAKED_CHECKSUMS

CASE=$(new_case invalid_source)
CASE_CHECKSUM_MODE=bound
CASE_SOURCE_REF=feature/unsafe
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	not_ok "unsafe recorded source ref is rejected"
else
	assert_true "grep -q 'not an immutable Release ref or full source SHA' '$CASE/err'" "unsafe recorded source ref fails closed with a clear diagnostic"
	assert_true "! grep -q '/releases/download/' '$CASE/curl.log' && [ ! -e '$CASE/home/.local/bin/delta' ]" "source identity failure occurs before artifact download or destination mutation"
fi
unset CASE_CHECKSUM_MODE CASE_SOURCE_REF

CASE=$(new_case checksum_reject)
install_observed "$CASE" delta 1.0.0
CASE_CHECKSUM_FILE=$BAD_CHECKSUMS
if run_updater "$CASE" delta >"$CASE/out" 2>"$CASE/err"; then
	not_ok "checksum rejection makes single-tool update fail"
else
	assert_true "[ ! -e '$CASE/home/.local/bin/delta' ] && [ \"\$('$CASE/bin/delta')\" = 'delta 1.0.0' ]" "checksum rejection leaves the observed executable unchanged"
	assert_true "grep -q 'new Candidate required' '$CASE/out' && grep -q 'publish and rebuild from a newer Candidate' '$CASE/err' && ! grep -q '/example/delta/releases/download/' '$CASE/curl.log'" "mismatched Candidate checksum blocks explicit update before artifact download"
fi
unset CASE_CHECKSUM_FILE

CASE=$(new_case asset_version)
if run_updater "$CASE" assettool >"$CASE/out" 2>"$CASE/err"; then
	assert_true "[ \"\$('$CASE/home/.local/bin/assettool')\" = 'assettool 8.1.2' ]" "asset-version tool verifies the installed binary against resolved asset metadata"
	assert_true "[ \"\$(grep -c '/repos/example/assettool/releases/latest' '$CASE/curl.log')\" -eq 1 ] && ! grep -q '/repos/example/assettool/releases/tags/v9.0.0' '$CASE/curl.log'" "asset-version install reuses cached latest metadata for its exact tag"
else
	not_ok "asset-version tool accepts its intentional tag/binary version difference"
fi

CASE=$(new_case api_failure)
install_observed "$CASE" yq 1.0.0
CASE_API_FAIL_REPO=yq
if run_updater "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	not_ok "metadata lookup failure makes dry run fail"
else
	assert_true "grep -q 'latest version unchecked' '$CASE/out' && ! grep -q 'All installed tools are up to date' '$CASE/out'" "failed metadata lookup is never reported as current"
fi
unset CASE_API_FAIL_REPO

CASE=$(new_case aggregate_failure)
install_observed "$CASE" yq 1.0.0
install_observed "$CASE" delta 1.0.0
CASE_CHECKSUM_FILE=$BAD_CHECKSUMS
if run_updater "$CASE" --apply >"$CASE/out" 2>"$CASE/err"; then
	not_ok "partial apply failure produces aggregate nonzero status"
else
	assert_true "[ \"\$('$CASE/home/.local/bin/yq')\" = 'yq (test) version v2.0.0' ] && [ ! -e '$CASE/home/.local/bin/delta' ]" "aggregate apply continues independent updates but blocks rejected artifact"
	assert_true "grep -q 'Update incomplete: 0 check failure(s), 0 install failure(s), 1 image-tier update(s) requiring a Candidate rebuild' '$CASE/err'" "aggregate apply reports exact Candidate authorization failure and no false success"
	assert_true "[ \"\$(grep -c '/repos/example/yq/releases/latest' '$CASE/curl.log')\" -eq 1 ] && [ \"\$(grep -c '/repos/example/delta/releases/latest' '$CASE/curl.log')\" -eq 1 ]" "partial apply caches each repository metadata response"
fi
unset CASE_CHECKSUM_FILE

CASE=$(new_case option_validation)
if run_updater "$CASE" --bogus >"$CASE/out" 2>"$CASE/err"; then
	not_ok "unknown updater option is rejected"
else ok "unknown updater option is rejected"; fi

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]

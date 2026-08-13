#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
REFRESH="$REPO_ROOT/scripts/update-versions.sh"
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
    dest: system
    group: dockerfile
    verification: sha256
    docker_arg: YQ_VERSION
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
YAML

FAKE_CURL="$TMP/curl"
cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
set -u
output=""; url=""
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
if [ -n "${FAKE_BARRIER_DIR:-}" ] && [[ "$url" == *'/releases/latest' ]] \
	&& [ ! -e "$FAKE_BARRIER_DIR/entered-$FAKE_RUN_ID" ]; then
	: > "$FAKE_BARRIER_DIR/entered-$FAKE_RUN_ID"
	if [ "$FAKE_RUN_ID" = a ]; then
		attempts=0
		while [ ! -e "$FAKE_BARRIER_DIR/entered-b" ] && [ "$attempts" -lt 100 ]; do
			sleep 0.01; attempts=$((attempts + 1))
		done
		[ ! -e "$FAKE_BARRIER_DIR/entered-b" ] || : > "$FAKE_BARRIER_DIR/overlap"
	fi
fi
if [ -n "${FAKE_DOWNLOAD_FAIL_MATCH:-}" ] && [[ "$url" == *"$FAKE_DOWNLOAD_FAIL_MATCH"* ]]; then
	exit 37
fi
asset_digest() {
	local repo=$1 tag=$2 asset=$3
	if [ -n "${FAKE_DIGEST_FAIL_MATCH:-}" ] && [[ "$asset" == *"$FAKE_DIGEST_FAIL_MATCH"* ]]; then
		printf '%064d' 0
	else
		printf 'synthetic artifact for https://github.com/example/%s/releases/download/%s/%s\n' \
			"$repo" "$tag" "$asset" | sha256sum | awk '{print $1}'
	fi
}
if [[ "$url" == *'/repos/example/yq/releases/latest' ]]; then
	printf '{"tag_name":"v2.0.0","assets":['
	printf '{"name":"yq-2.0.0-amd64","digest":"sha256:%s"},' "$(asset_digest yq v2.0.0 yq-2.0.0-amd64)"
	printf '{"name":"yq-2.0.0-arm64","digest":"sha256:%s"}]}\n200\n' "$(asset_digest yq v2.0.0 yq-2.0.0-arm64)"
elif [[ "$url" == *'/repos/example/delta/releases/latest' ]]; then
	printf '{"tag_name":"2.0.0","assets":['
	printf '{"name":"delta-2.0.0-amd64","digest":"sha256:%s"},' "$(asset_digest delta 2.0.0 delta-2.0.0-amd64)"
	printf '{"name":"delta-2.0.0-arm64","digest":"sha256:%s"}]}\n200\n' "$(asset_digest delta 2.0.0 delta-2.0.0-arm64)"
elif [[ "$url" == *'/releases/download/'* ]]; then
	printf 'synthetic artifact for %s\n' "$url" > "$output"
else
	echo "unexpected fake URL: $url" >&2
	exit 67
fi
SH
chmod +x "$FAKE_CURL"

new_repo() {
	local name=$1 dir
	dir="$TMP/$name"
	mkdir -p "$dir/repo" "$dir/bin"
	cp "$FAKE_CURL" "$dir/bin/curl"
	cat > "$dir/repo/Dockerfile" <<'DOCKER'
FROM scratch
ARG YQ_VERSION=1.0.0
ARG DELTA_VERSION=1.0.0
DOCKER
	printf '# original manifest\noldhash  old-artifact\n' > "$dir/repo/checksums.txt"
	cp "$dir/repo/Dockerfile" "$dir/Dockerfile.before"
	cp "$dir/repo/checksums.txt" "$dir/checksums.before"
	printf '%s\n' "$dir"
}

run_refresh() {
	local dir=$1; shift
	env \
		PATH="$dir/bin:$PATH" \
		SB_REPO_ROOT="$dir/repo" \
		SB_DOCKERFILE="$dir/repo/Dockerfile" \
		SB_CHECKSUMS_FILE="$dir/repo/checksums.txt" \
		SB_TOOLS_YAML="$REGISTRY" \
		SB_TOOL_LIB="$REPO_ROOT/scripts/lib/tool-lib.sh" \
		SB_DPKG_ARCH=amd64 \
		SB_GITHUB_API_BASE=https://api.test \
		FAKE_CURL_LOG="$dir/curl.log" \
		FAKE_BARRIER_DIR="${CASE_BARRIER_DIR:-}" \
		FAKE_RUN_ID="${CASE_RUN_ID:-single}" \
		FAKE_EDIT_BARRIER_DIR="${CASE_EDIT_BARRIER_DIR:-}" \
		FAKE_DOWNLOAD_FAIL_MATCH="${CASE_DOWNLOAD_FAIL_MATCH:-}" \
		FAKE_DIGEST_FAIL_MATCH="${CASE_DIGEST_FAIL_MATCH:-}" \
		FAKE_MV_COUNT="$dir/mv.count" \
		FAKE_MV_FAIL_ON="${CASE_MV_FAIL_ON:-0}" \
		"$REFRESH" "$@"
}

CASE=$(new_repo success)
if run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; then
	assert_true "grep -q '^ARG YQ_VERSION=2.0.0$' '$CASE/repo/Dockerfile' && grep -q '^ARG DELTA_VERSION=2.0.0$' '$CASE/repo/Dockerfile'" "successful refresh updates every mapped Docker ARG"
	assert_true "[ \"\$(awk '\$1 ~ /^[0-9a-f]{64}\$/ {n++} END {print n+0}' '$CASE/repo/checksums.txt')\" -eq 4 ]" "successful refresh publishes a complete two-architecture manifest"
	assert_true "[ \"\$(grep -c '/repos/example/yq/releases/latest' '$CASE/curl.log')\" -eq 1 ] && [ \"\$(grep -c '/repos/example/delta/releases/latest' '$CASE/curl.log')\" -eq 1 ]" "refresh resolves each release exactly once"
else
	not_ok "complete refresh transaction succeeds"
fi

CASE=$(new_repo download_failure)
CASE_DOWNLOAD_FAIL_MATCH=delta-2.0.0-arm64
set +e; run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; RC=$?; set -e
assert_true "[ '$RC' -eq 37 ]" "artifact download failure remains the refresh exit status"
assert_true "cmp -s '$CASE/Dockerfile.before' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.before' '$CASE/repo/checksums.txt'" "mid-download failure leaves both tracked outputs byte-for-byte unchanged"
unset CASE_DOWNLOAD_FAIL_MATCH

CASE=$(new_repo concurrent_refresh)
mkdir -p "$CASE/barrier"
CASE_BARRIER_DIR="$CASE/barrier" CASE_RUN_ID=a run_refresh "$CASE" >"$CASE/a.out" 2>"$CASE/a.err" & REFRESH_A=$!
while [ ! -e "$CASE/barrier/entered-a" ]; do sleep 0.01; done
CASE_BARRIER_DIR="$CASE/barrier" CASE_RUN_ID=b run_refresh "$CASE" >"$CASE/b.out" 2>"$CASE/b.err" & REFRESH_B=$!
set +e
wait "$REFRESH_A"; RC_A=$?
wait "$REFRESH_B"; RC_B=$?
set -e
assert_true "[ '$RC_A' -eq 0 ] && [ '$RC_B' -eq 0 ] && [ ! -e '$CASE/barrier/overlap' ]" "concurrent version refreshes serialize across the complete operation"

CASE=$(new_repo digest_failure)
CASE_DIGEST_FAIL_MATCH=yq-2.0.0-arm64
set +e; run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; RC=$?; set -e
assert_true "[ '$RC' -ne 0 ] && grep -q 'digest mismatch' '$CASE/err'" "GitHub release-asset digest mismatch is authoritative"
assert_true "cmp -s '$CASE/Dockerfile.before' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.before' '$CASE/repo/checksums.txt'" "digest mismatch leaves both tracked outputs byte-for-byte unchanged"
unset CASE_DIGEST_FAIL_MATCH

CASE=$(new_repo concurrent_edit)
mkdir -p "$CASE/edit-barrier"
cat > "$CASE/bin/cp" <<'SH'
#!/usr/bin/env bash
set -u
destination=${@: -1}
/bin/cp "$@" || exit $?
if [[ "$destination" == */.Dockerfile.squarebox.* ]] && [ -n "${FAKE_EDIT_BARRIER_DIR:-}" ]; then
	: > "$FAKE_EDIT_BARRIER_DIR/staged"
	while [ ! -e "$FAKE_EDIT_BARRIER_DIR/release" ]; do sleep 0.01; done
fi
SH
chmod +x "$CASE/bin/cp"
CASE_EDIT_BARRIER_DIR="$CASE/edit-barrier" run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err" & EDIT_REFRESH=$!
while [ ! -e "$CASE/edit-barrier/staged" ]; do sleep 0.01; done
printf '\n# concurrent maintainer edit\n' >> "$CASE/repo/Dockerfile"
printf '# concurrent maintainer checksums edit\n' > "$CASE/repo/checksums.txt"
cp "$CASE/repo/Dockerfile" "$CASE/Dockerfile.external"
cp "$CASE/repo/checksums.txt" "$CASE/checksums.external"
: > "$CASE/edit-barrier/release"
set +e; wait "$EDIT_REFRESH"; RC=$?; set -e
assert_true "[ '$RC' -ne 0 ] && grep -q 'changed during version refresh' '$CASE/err'" "concurrent tracked-file edits abort version refresh"
assert_true "cmp -s '$CASE/Dockerfile.external' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.external' '$CASE/repo/checksums.txt'" "aborted refresh preserves concurrent maintainer edits byte-for-byte"

CASE=$(new_repo mapping_failure)
sed -i '/ARG DELTA_VERSION=/d' "$CASE/repo/Dockerfile"
cp "$CASE/repo/Dockerfile" "$CASE/Dockerfile.before"
set +e; run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; RC=$?; set -e
assert_true "[ '$RC' -ne 0 ] && grep -q 'expected exactly one ARG DELTA_VERSION' '$CASE/err'" "missing Docker ARG mapping fails validation"
assert_true "cmp -s '$CASE/Dockerfile.before' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.before' '$CASE/repo/checksums.txt'" "generation validation failure commits neither output"

CASE=$(new_repo commit_failure)
cat > "$CASE/bin/mv" <<'SH'
#!/usr/bin/env bash
set -u
count=0
[ ! -f "$FAKE_MV_COUNT" ] || count=$(<"$FAKE_MV_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_MV_COUNT"
if [ "$FAKE_MV_FAIL_ON" -gt 0 ] && [ "$count" -eq "$FAKE_MV_FAIL_ON" ]; then
	exit 55
fi
exec /bin/mv "$@"
SH
chmod +x "$CASE/bin/mv"
CASE_MV_FAIL_ON=2
set +e; run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; RC=$?; set -e
assert_true "[ '$RC' -eq 55 ]" "second destination replacement failure remains authoritative"
assert_true "cmp -s '$CASE/Dockerfile.before' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.before' '$CASE/repo/checksums.txt'" "failed two-file commit rolls both tracked outputs back"
assert_true "! compgen -G '$CASE/repo/.checksums.txt.squarebox.*' >/dev/null && ! compgen -G '$CASE/repo/.Dockerfile.squarebox.*' >/dev/null" "failed commit removes destination-local stage files"
unset CASE_MV_FAIL_ON

CASE=$(new_repo rollback_copy_failure)
cat > "$CASE/bin/mv" <<'SH'
#!/usr/bin/env bash
set -u
count=0
[ ! -f "$FAKE_MV_COUNT" ] || count=$(<"$FAKE_MV_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_MV_COUNT"
if [ "$FAKE_MV_FAIL_ON" -gt 0 ] && [ "$count" -eq "$FAKE_MV_FAIL_ON" ]; then
	exit 55
fi
exec /bin/mv "$@"
SH
cat > "$CASE/bin/cp" <<'SH'
#!/usr/bin/env bash
set -u
source_path=${@: -2:1}
case "$source_path" in *.original) exit 66 ;; esac
exec /bin/cp "$@"
SH
chmod +x "$CASE/bin/mv" "$CASE/bin/cp"
CASE_MV_FAIL_ON=2
set +e; run_refresh "$CASE" >"$CASE/out" 2>"$CASE/err"; RC=$?; set -e
assert_true "[ '$RC' -eq 55 ]" "promotion failure remains authoritative when copy-based restoration is unavailable"
assert_true "cmp -s '$CASE/Dockerfile.before' '$CASE/repo/Dockerfile' && cmp -s '$CASE/checksums.before' '$CASE/repo/checksums.txt'" "rollback restores both originals without fallible copy-over writes"
unset CASE_MV_FAIL_ON

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]

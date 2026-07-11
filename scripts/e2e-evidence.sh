#!/usr/bin/env bash
set -euo pipefail

# Record one assertion result for the release report. The interface is one
# tab-separated file per assertion so parallel jobs can upload and merge them
# without sharing mutable state.

usage() {
	echo "Usage: SQUAREBOX_EVIDENCE_DIR=<dir> $0 <pass|fail|skip> <id> <description> [detail]" >&2
	exit 2
}

[ "$#" -ge 3 ] || usage

status="$1"
id="$2"
description="$3"
detail="${4:-}"
evidence_dir="${SQUAREBOX_EVIDENCE_DIR:-}"

case "$status" in
	pass|fail|skip) ;;
	*) usage ;;
esac

[ -n "$evidence_dir" ] || {
	echo "SQUAREBOX_EVIDENCE_DIR is required" >&2
	exit 2
}

[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	echo "Evidence id must match [A-Za-z0-9][A-Za-z0-9._-]*" >&2
	exit 2
}
safe_id=$id

clean_field() {
	printf '%s' "$1" | tr '\t\r\n' '   '
}

mkdir -p "$evidence_dir"
tmp=$(mktemp "$evidence_dir/.${safe_id}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '%s\t%s\t%s\t%s\n' \
	"$(clean_field "$id")" \
	"$status" \
	"$(clean_field "$description")" \
	"$(clean_field "$detail")" > "$tmp"
mv -f "$tmp" "$evidence_dir/${safe_id}.evidence"
trap - EXIT

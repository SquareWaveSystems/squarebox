#!/usr/bin/env bash
set -euo pipefail

# Render assertion Evidence. Unlike the old report, this script never maps a
# job result to behavior the job may not have executed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_FILE="${SQUAREBOX_REQUIRED_EVIDENCE:-$SCRIPT_DIR/e2e-required.tsv}"
EVIDENCE_DIR="${1:-${SQUAREBOX_EVIDENCE_DIR:-evidence}}"

[ -f "$REQUIRED_FILE" ] || {
	echo "Required-evidence manifest not found: $REQUIRED_FILE" >&2
	exit 2
}

declare -A statuses required_descriptions evidence_descriptions details required seen
declare -a ordered_required ordered_seen
malformed=0

while IFS=$'\t' read -r id description; do
	[ -z "$id" ] && continue
	[[ "$id" == \#* ]] && continue
	if ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [ -z "$description" ]; then
		echo "Malformed required-evidence entry: $id" >&2
		exit 2
	fi
	[ -z "${required[$id]:-}" ] || {
		echo "Duplicate required Evidence id: $id" >&2
		exit 2
	}
	required["$id"]=1
	required_descriptions["$id"]="$description"
	ordered_required+=("$id")
done < "$REQUIRED_FILE"

if [ -d "$EVIDENCE_DIR" ]; then
	while IFS= read -r file; do
		IFS=$'\t' read -r id status description detail < "$file" || true
		if ! [[ "${id:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
			|| [ "$(basename "$file")" != "$id.evidence" ]; then
			echo "Malformed or mismatched Evidence file: $file" >&2
			malformed=$((malformed + 1))
			continue
		fi
		case "${status:-}" in
			pass|fail|skip) ;;
			*) status=fail; detail="malformed evidence file: $file" ;;
		esac
		if [ "${statuses[$id]:-}" = "fail" ]; then
			continue
		fi
		if [ "$status" = "fail" ] || [ -z "${statuses[$id]:-}" ]; then
			statuses["$id"]="$status"
			evidence_descriptions["$id"]="${description:-}"
			details["$id"]="${detail:-}"
		fi
		if [ -z "${seen[$id]:-}" ]; then
			seen["$id"]=1
			ordered_seen+=("$id")
		fi
	done < <(find "$EVIDENCE_DIR" -type f -name '*.evidence' -print | sort)
fi

pass=0
fail=0
skip=0
missing=0

for id in "${ordered_required[@]}"; do
	case "${statuses[$id]:-missing}" in
		pass) pass=$((pass + 1)) ;;
		fail) fail=$((fail + 1)) ;;
		skip) skip=$((skip + 1)) ;;
		missing) missing=$((missing + 1)) ;;
	esac
done

escape_md() {
	printf '%s' "$1" | sed 's/|/\\|/g'
}

status_label() {
	case "$1" in
		pass) echo "PASS" ;;
		fail) echo "FAIL" ;;
		skip) echo "UNTESTED" ;;
		*) echo "MISSING" ;;
	esac
}

cat <<EOF
# E2E Evidence Report

**Date**: $(date -u +%Y-%m-%d)
**Commit**: ${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}

## Required release evidence

- **Required**: ${#ordered_required[@]}
- **Passed**: ${pass}
- **Failed**: ${fail}
- **Untested**: ${skip}
- **Missing**: ${missing}

| Evidence | Requirement | Result | Detail |
| --- | --- | --- | --- |
EOF

for id in "${ordered_required[@]}"; do
	status="${statuses[$id]:-missing}"
	printf '| `%s` | %s | **%s** | %s |\n' \
		"$(escape_md "$id")" \
		"$(escape_md "${required_descriptions[$id]}")" \
		"$(status_label "$status")" \
		"$(escape_md "${details[$id]:-}")"
done

echo
echo "## Additional assertion evidence"
echo
echo "| Evidence | Assertion | Result | Detail |"
echo "| --- | --- | --- | --- |"
additional=0
for id in "${ordered_seen[@]}"; do
	[ -z "${required[$id]:-}" ] || continue
	additional=$((additional + 1))
	printf '| `%s` | %s | **%s** | %s |\n' \
		"$(escape_md "$id")" \
		"$(escape_md "${evidence_descriptions[$id]:-}")" \
		"$(status_label "${statuses[$id]}")" \
		"$(escape_md "${details[$id]:-}")"
done
[ "$additional" -gt 0 ] || echo "| — | No additional evidence uploaded | — | — |"

echo
echo "Manual platform checks are tracked separately in [uat-checklist.md](/uat-checklist.md); they are never represented as automated passes."

[ "$fail" -eq 0 ] && [ "$skip" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$malformed" -eq 0 ]

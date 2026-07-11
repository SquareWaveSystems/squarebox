#!/usr/bin/env bash
set -uo pipefail

# Verify one downloaded file against one unambiguous SHA256 manifest entry.
# Usage: verify-checksum <file> <artifact-name> [checksums-file]

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "Usage: verify-checksum <file> <artifact-name> [checksums-file]" >&2
	exit 2
fi

FILE=$1
NAME=$2
CHECKSUMS=${3:-/tmp/checksums.txt}

if [ ! -f "$FILE" ] || [ -L "$FILE" ] || [ ! -r "$FILE" ]; then
	echo "ERROR: Artifact is not a readable regular file: ${FILE}" >&2
	exit 1
fi
if [ ! -f "$CHECKSUMS" ] || [ -L "$CHECKSUMS" ] || [ ! -r "$CHECKSUMS" ]; then
	echo "ERROR: Checksum manifest is not a readable regular file: ${CHECKSUMS}" >&2
	exit 1
fi
case "$NAME" in
	""|*/*|*$'\n'*|*$'\r'*)
		echo "ERROR: Unsafe artifact name: ${NAME:-<empty>}" >&2
		exit 1
		;;
esac

mapfile -t MATCHES < <(
	awk -v name="$NAME" '
		NF == 2 && $1 ~ /^[0-9a-f]{64}$/ && $2 == name { print $1 }
	' "$CHECKSUMS"
)

if [ "${#MATCHES[@]}" -eq 0 ]; then
	echo "ERROR: No checksum entry found for '${NAME}' in ${CHECKSUMS}" >&2
	exit 1
fi
if [ "${#MATCHES[@]}" -ne 1 ]; then
	echo "ERROR: Multiple checksum entries found for '${NAME}' in ${CHECKSUMS}" >&2
	exit 1
fi

EXPECTED=${MATCHES[0]}
if ACTUAL_LINE=$(sha256sum -- "$FILE"); then
	ACTUAL=${ACTUAL_LINE%% *}
else
	rc=$?
	echo "ERROR: Could not hash '${FILE}'" >&2
	exit "$rc"
fi

if [ "$ACTUAL" != "$EXPECTED" ]; then
	echo "CHECKSUM MISMATCH for ${NAME}" >&2
	echo "  expected: ${EXPECTED}" >&2
	echo "  actual:   ${ACTUAL}" >&2
	exit 1
fi

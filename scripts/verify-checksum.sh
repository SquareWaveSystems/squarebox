#!/usr/bin/env bash
set -euo pipefail

# Verify SHA256 checksum of a downloaded file against a checksums file.
# Usage: verify-checksum <file> <artifact-name> [checksums-file]
# The checksums file uses the standard "sha256  filename" format.

FILE="$1"
NAME="$2"
CHECKSUMS="${3:-/tmp/checksums.txt}"

EXPECTED=$(grep -E "^[0-9a-f]{64}  ${NAME}$" "$CHECKSUMS" | awk '{print $1}')
if [ -z "$EXPECTED" ]; then
	echo "ERROR: No checksum entry found for '${NAME}' in ${CHECKSUMS}" >&2
	exit 1
fi

ACTUAL=$(sha256sum "$FILE" | awk '{print $1}')
if [ "$ACTUAL" != "$EXPECTED" ]; then
	echo "CHECKSUM MISMATCH for ${NAME}" >&2
	echo "  expected: ${EXPECTED}" >&2
	echo "  actual:   ${ACTUAL}" >&2
	exit 1
fi

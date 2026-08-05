#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/toilet" <<'EOF'
#!/usr/bin/env bash
printf 'squarebox\n'
EOF
chmod +x "$TMP/bin/toilet"

normal_output=$(HERDR_ENV=0 PATH="$TMP/bin:$PATH" bash "$ROOT/motd.sh")
if [[ "$normal_output" != *squarebox* ]]; then
	echo "FAIL: MOTD should render outside Herdr" >&2
	exit 1
fi

herdr_output=$(HERDR_ENV=1 PATH="$TMP/bin:$PATH" bash "$ROOT/motd.sh")
if [ -n "$herdr_output" ]; then
	echo "FAIL: MOTD should be silent in a Herdr-managed pane" >&2
	exit 1
fi

echo "PASS: MOTD renders normally and stays silent inside Herdr"

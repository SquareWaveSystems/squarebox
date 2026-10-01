#!/usr/bin/env bash
# Static policy: every external APT signing key the Dockerfile downloads must be
# verified against a pinned full primary-key fingerprint set before it is
# installed as an APT signer or any source list referencing it is written.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOCKERFILE="$ROOT/Dockerfile"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

line_of() {
	# First line number containing the fixed string $1 (0 if absent).
	grep -nF -- "$1" "$DOCKERFILE" | head -n1 | cut -d: -f1 || true
}

# Fingerprint ARGs: non-empty, each token a 40-hex upper-case fingerprint, no duplicates.
mapfile -t fpr_args < <(sed -n 's/^ARG \([A-Z0-9_]*_KEY_FINGERPRINTS\)=.*/\1/p' "$DOCKERFILE")
[ "${#fpr_args[@]}" -ge 2 ] || fail "expected GitHub CLI and Eza fingerprint ARGs"
for required in GH_CLI_KEY_FINGERPRINTS EZA_KEY_FINGERPRINTS; do
	printf '%s\n' "${fpr_args[@]}" | grep -qx "$required" || fail "missing ARG $required"
done
for arg in "${fpr_args[@]}"; do
	[ "$(grep -c "^ARG ${arg}=" "$DOCKERFILE")" -eq 1 ] || fail "$arg must be declared exactly once"
	value=$(sed -n "s/^ARG ${arg}=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$DOCKERFILE")
	[ -n "$value" ] || fail "$arg is empty"
	read -r -a tokens <<<"$value"
	[ "${#tokens[@]}" -ge 1 ] || fail "$arg has no fingerprints"
	for token in "${tokens[@]}"; do
		[[ "$token" =~ ^[0-9A-F]{40}$ ]] || fail "$arg value '$token' is not a 40-hex upper-case fingerprint"
	done
	[ "$(printf '%s\n' "${tokens[@]}" | sort -u | wc -l)" -eq "${#tokens[@]}" ] \
		|| fail "$arg contains duplicate fingerprints"
	grep -Fq "\"\$${arg}\"" "$DOCKERFILE" || fail "$arg is declared but never used for verification"
done

# The verifier compares primary-key fingerprints (pub -> following fpr) as an exact set.
grep -Fq 'verify_apt_key() {' "$DOCKERFILE" || fail "Dockerfile does not define verify_apt_key"
grep -Fq "\$1 == \"pub\" { want_fpr = 1; next } want_fpr && \$1 == \"fpr\" { print \$10; want_fpr = 0 }" "$DOCKERFILE" \
	|| fail "verify_apt_key must extract only primary-key fingerprints"
grep -Fq 'if [ "$actual" != "$want" ]; then' "$DOCKERFILE" \
	|| fail "verify_apt_key must require the exact expected fingerprint set"

# No key may be piped straight from the network into a keyring.
if grep -Eq 'curl[^|]*(\.gpg|\.asc|keyring)[^|]*\|' "$DOCKERFILE"; then
	fail "an APT key is piped from curl without fingerprint verification"
fi
if grep -Eq 'raw\.githubusercontent\.com/eza-community/eza/(main|master)/' "$DOCKERFILE"; then
	fail "Eza key URL must be pinned to an immutable commit, not a branch"
fi
grep -Eq '^ARG EZA_KEY_URL=https://raw\.githubusercontent\.com/eza-community/eza/[0-9a-f]{40}/deb\.asc$' "$DOCKERFILE" \
	|| fail "Eza key URL must be pinned to a full commit SHA"

# Every downloaded key file is verified, and verification precedes keyring
# installation and source-list creation for that repository.
mapfile -t key_files < <(grep -oE 'curl -fsSL -o "\$KEYDIR/[^"]+"' "$DOCKERFILE" | sed 's/.*"\$KEYDIR\/\([^"]*\)"/\1/')
[ "${#key_files[@]}" -ge 2 ] || fail "expected at least two downloaded APT keys"
for key in "${key_files[@]}"; do
	download=$(line_of "curl -fsSL -o \"\$KEYDIR/$key\"")
	verify=$(grep -nE "verify_apt_key \"[^\"]+\" \"\\\$KEYDIR/${key//./\\.}\" \"\\\$[A-Z0-9_]+_KEY_FINGERPRINTS\"" "$DOCKERFILE" | head -n1 | cut -d: -f1 || true)
	[ -n "$verify" ] || fail "downloaded key $key is never fingerprint-verified"
	[ "$verify" -gt "$download" ] || fail "key $key is verified before it is downloaded"
	use=$(grep -nF "\"\$KEYDIR/$key\"" "$DOCKERFILE" | cut -d: -f1 | awk -v v="$verify" '$1 > v' | head -n1)
	[ -n "$use" ] || fail "verified key $key is never installed"
done

# Every signed-by keyring is installed only after a verification step, and the
# number of signer keyrings matches the number of verified downloads.
mapfile -t signers < <(grep -oE 'signed-by=/etc/apt/keyrings/[^] ]+' "$DOCKERFILE" | sort -u)
[ "${#signers[@]}" -eq "${#key_files[@]}" ] \
	|| fail "signed-by keyrings (${#signers[@]}) do not match verified downloads (${#key_files[@]})"
first_verify=$(grep -nF 'verify_apt_key "' "$DOCKERFILE" | head -n1 | cut -d: -f1)
for signer in "${signers[@]}"; do
	path=${signer#signed-by=}
	sources_line=$(line_of "$signer")
	[ "$sources_line" -gt "$first_verify" ] || fail "$path is trusted before key verification"
done

echo "PASS: external APT signing keys are pinned by primary-key fingerprint and verified before use"

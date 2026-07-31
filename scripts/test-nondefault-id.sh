#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:?usage: test-nondefault-id.sh IMAGE_REF}"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$repo_root/dotfiles/bashrc"
suffix="${GITHUB_RUN_ID:-local}-$$"
box="sqrbx-remap-$suffix"
home_volume="sqrbx-remap-home-$suffix"
profile_sha=$(sha256sum "$profile" | cut -d' ' -f1)

cleanup() {
	docker rm -f "$box" >/dev/null 2>&1 || true
	docker volume rm "$home_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
docker volume create "$home_volume" >/dev/null

docker run --name "$box" \
	--cap-drop=ALL --cap-add=CHOWN --cap-add=DAC_OVERRIDE \
	--cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID --cap-add=KILL \
	-e PUID=12345 -e PGID=23456 -e EXPECTED_PROFILE_SHA="$profile_sha" \
	-v "$home_volume:/home/dev" \
	-v "$profile:/home/dev/.bashrc:ro" \
	"$image_ref" bash -lc '
		test "$(id -u)" = 12345
		test "$(id -g)" = 23456
		test "$HOME" = /home/dev
		test "$(getent passwd dev | cut -d: -f6)" = /home/dev
		test "$(stat -c %u:%g /home/dev)" = 12345:23456
		test -r /home/dev/.bashrc
		test "$(sha256sum /home/dev/.bashrc | cut -d" " -f1)" = "$EXPECTED_PROFILE_SHA"
		printf "%s\n" writable > /home/dev/nondefault-id-test
		grep -qx writable /home/dev/nondefault-id-test
	'

# Starting the same container reruns the entrypoint against its already-remapped
# passwd entry and retained Managed home, proving the operation is idempotent.
docker start -a "$box"
test "$(sha256sum "$profile" | cut -d' ' -f1)" = "$profile_sha"

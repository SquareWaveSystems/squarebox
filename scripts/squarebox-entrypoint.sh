#!/usr/bin/env bash
# squarebox-entrypoint — optional PUID/PGID remap for bind-mount ownership parity.
#
# Why: when squarebox runs as a long-lived server container (docker-compose,
# Unraid, a NAS), files it writes to bind-mounted host paths inherit the
# container user's uid/gid. Hosts rarely use 1000:1000 — Unraid shares are
# 99:100, other setups vary — so without a remap the host sees files owned by a
# phantom uid and other services can't touch them. linuxserver.io solved this
# with PUID/PGID; we mirror that convention.
#
# How: when started as root, remap the image's `dev` user to the requested
# PUID/PGID, fix ownership of the paths dev must write, then drop privileges to
# it via setpriv (util-linux — always present on Ubuntu, no gosu dependency).
# When already unprivileged — rootless Podman maps the container user to the
# host user, or the operator passed `--user` — there is nothing to remap, so we
# just exec the command as-is.
#
# Defaults are 1000:1000, i.e. exactly the image's baked `dev` user, so the
# common desktop install path is a no-op: the remap and chown are skipped
# entirely and behaviour is identical to a plain `USER dev` image.
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [ "$(id -u)" = "0" ]; then
	cur_uid="$(id -u dev)"
	cur_gid="$(id -g dev)"

	# -o permits a non-unique id (e.g. a PUID that collides with an existing
	# account). groupmod before usermod so the gid exists when usermod runs.
	if [ "$PGID" != "$cur_gid" ]; then
		groupmod -o -g "$PGID" dev
	fi
	if [ "$PUID" != "$cur_uid" ]; then
		usermod -o -u "$PUID" dev
	fi

	# Re-own the paths dev owns only when the ids actually changed. /etc/passwd
	# is in the container's writable layer, so on a create-once-start-many
	# container (squarebox's model) this fires only on the first start after a
	# change — subsequent starts see cur == requested and skip the costly chown.
	if [ "$PUID" != "$cur_uid" ] || [ "$PGID" != "$cur_gid" ]; then
		# Best-effort: /home/dev may be a large named volume; never fail boot on it.
		chown -R "$PUID:$PGID" /home/dev 2>/dev/null || true
		chown "$PUID:$PGID" /workspace 2>/dev/null || true
	fi

	# Re-seed image-managed dotfiles over the (volume-shadowed) home so image
	# updates reach upgraded containers — issue #89. Done as root, before the
	# privilege drop, so refreshed files can be chowned to the resolved dev user.
	/usr/local/lib/squarebox/refresh-dotfiles.sh "$PUID:$PGID" || true

	# Drop to dev. --init-groups picks up dev's supplementary groups; numeric
	# ids resolve back to the (now-remapped) dev passwd entry.
	exec setpriv --reuid "$PUID" --regid "$PGID" --init-groups -- "$@"
fi

# Already unprivileged (rootless Podman, or --user override): run as-is, but
# still refresh managed dotfiles (owned by the running user; no chown needed).
/usr/local/lib/squarebox/refresh-dotfiles.sh || true
exec "$@"

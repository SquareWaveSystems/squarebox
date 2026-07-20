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

validate_id() {
	local name="$1" value="$2"
	if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "${#value}" -gt 10 ] \
		|| [ "$((10#$value))" -lt 1 ] || [ "$((10#$value))" -gt 2147483647 ]; then
		echo "squarebox: $name must be an integer between 1 and 2147483647 (got '$value')" >&2
		exit 64
	fi
}

selection_contains() {
	local file="$1" item="$2" value=""
	[ -f "$file" ] || return 1
	IFS= read -r value < "$file" || true
	[[ ",$value," == *",$item,"* ]]
}

validate_selection_state_dir() {
	local state="${SQUAREBOX_STATE_DIR:-/workspace/.squarebox}"
	local name path
	while [[ "$state" == */ && "$state" != / ]]; do state="${state%/}"; done
	if [ -L "$state" ]; then
		echo "squarebox: Selection state directory must not be a symlink: $state" >&2
		return 1
	fi
	if [ -e "$state" ] && [ ! -d "$state" ]; then
		echo "squarebox: Selection state path is not a directory: $state" >&2
		return 1
	fi
	for name in ai-tool editors editor-default nvim-lazyvim nvim-lazyvim-sha tuis multiplexer sdks shell; do
		path="$state/$name"
		if [ -L "$path" ]; then
			echo "squarebox: Selection state file must not be a symlink: $path" >&2
			return 1
		fi
		if [ -e "$path" ] && [ ! -f "$path" ]; then
			echo "squarebox: Selection state path is not a regular file: $path" >&2
			return 1
		fi
	done
}

# Box-tier packages live in the writable layer and disappear when a Box is
# replaced, while their Selection lives in the Workspace. Ask setup to
# reconcile only when Observed state is missing or needs a managed migration.
box_reconcile_needed() {
	local state="${SQUAREBOX_STATE_DIR:-/workspace/.squarebox}"
	local managed_home="${SQUAREBOX_MANAGED_HOME:-/home/dev}"
	if selection_contains "$state/editors" nvim \
		&& [ "$(cat "$state/nvim-lazyvim" 2>/dev/null || true)" = true ]; then
		command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || return 0
	fi
	if selection_contains "$state/multiplexer" tmux; then
		command -v tmux >/dev/null 2>&1 || return 0
		[ -f "$managed_home/.config/tmux/tmux.conf" ] || return 0
		grep -Eq '^[[:space:]]*set(-option)?[[:space:]]+-g[[:space:]]+mouse[[:space:]]+(on|off)([[:space:]]|$)' \
			"$managed_home/.config/tmux/tmux.conf" || return 0
	fi
	if selection_contains "$state/shell" zsh; then
		command -v zsh >/dev/null 2>&1 || return 0
		[ -f "$managed_home/.zshrc" ] || return 0
	fi
	if selection_contains "$state/shell" fish; then
		command -v fish >/dev/null 2>&1 || return 0
		[ -f "$managed_home/.config/fish/config.fish" ] || return 0
	fi
	return 1
}

reconcile_box_as_current_user() {
	if box_reconcile_needed; then
		echo "squarebox: reconciling saved Box-tier selections..."
		/usr/local/lib/squarebox/setup.sh --reconcile-box || {
			echo "squarebox: Box-tier reconciliation failed; see diagnostics above" >&2
			return 1
		}
	fi
}

# The Codex app-server daemon (`codex app-server daemon start`, used for the
# experimental remote-control feature) keeps its state in /home/dev — which
# survives in the home volume — but the process itself dies with the container,
# so remote control silently drops on every restart and has to be brought back
# by hand. Restart it at boot, but only when its state file shows the operator
# used it before; boxes that never ran the daemon skip this entirely.
start_codex_app_server() {
	local codex_home="${SQUAREBOX_MANAGED_HOME:-/home/dev}/.codex"
	[ -f "$codex_home/app-server-daemon/settings.json" ] || return 0

	# A fresh container has no codex processes, so any control socket or pid
	# file left in the volume is stale — the daemon's bind would fail with
	# EADDRINUSE, or chase a socket symlink into the wiped /tmp.
	rm -f "$codex_home/app-server-daemon/app-server.pid" \
		"$codex_home/app-server-daemon/app-server.pid.lock" \
		"$codex_home/app-server-control/app-server-control.sock" \
		"$codex_home/app-server-control/app-server-startup.lock"

	# Run as dev when still root (redirection included, so the log stays
	# dev-owned). codex is user-installed, so mise shims and ~/.local/bin must
	# be on PATH; missing codex is a silent no-op. `daemon start` waits for
	# the control socket to come up — cap it so a broken install or dead
	# network can never wedge boot. Best-effort by design: never fail boot.
	local drop=()
	if [ "$(id -u)" = "0" ]; then
		drop=(setpriv --reuid "$PUID" --regid "$PGID" --init-groups --)
	fi
	timeout 30 "${drop[@]}" /usr/bin/env HOME=/home/dev USER=dev \
		PATH="/home/dev/.local/share/mise/shims:/home/dev/.local/bin:$PATH" \
		bash -c 'command -v codex >/dev/null 2>&1 || exit 0
			codex app-server daemon start \
				>>"$HOME/.codex/app-server-daemon/autostart.log" 2>&1' \
		|| echo "squarebox: codex app-server autostart failed (non-fatal)" >&2
}

# Tests source the pure selection/validation helpers without performing user
# remapping or exec. Production never sets this variable.
if [ "${SQUAREBOX_ENTRYPOINT_FUNCTIONS_ONLY:-}" = "1" ]; then
	return 0 2>/dev/null || exit 0
fi

validate_selection_state_dir || exit 1
validate_id PUID "$PUID"
validate_id PGID "$PGID"
# Strip leading zeroes after validation so usermod/groupmod receive canonical
# decimal values rather than values that other tools may interpret as octal.
PUID="$((10#$PUID))"
PGID="$((10#$PGID))"

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
	/usr/local/lib/squarebox/refresh-dotfiles.sh "$PUID:$PGID"

	if box_reconcile_needed; then
		echo "squarebox: reconciling saved Box-tier selections..."
		setpriv --reuid "$PUID" --regid "$PGID" --init-groups -- \
			/usr/bin/env HOME=/home/dev USER=dev \
			/usr/local/lib/squarebox/setup.sh --reconcile-box || {
				echo "squarebox: Box-tier reconciliation failed; see diagnostics above" >&2
				exit 1
			}
	fi

	start_codex_app_server

	# Drop to dev. --init-groups picks up dev's supplementary groups; numeric
	# ids resolve back to the (now-remapped) dev passwd entry.
	exec setpriv --reuid "$PUID" --regid "$PGID" --init-groups -- "$@"
fi

# Already unprivileged (rootless Podman, or --user override): run as-is, but
# still refresh managed dotfiles (owned by the running user; no chown needed).
/usr/local/lib/squarebox/refresh-dotfiles.sh
reconcile_box_as_current_user
start_codex_app_server
exec "$@"

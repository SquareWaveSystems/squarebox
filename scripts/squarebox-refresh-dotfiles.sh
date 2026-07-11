#!/usr/bin/env bash
# squarebox-refresh-dotfiles — re-seed image-managed dotfiles into /home/dev.
#
# Why: /home/dev is the persisted `squarebox-home` named volume. Docker seeds a
# volume from the image only when the volume is first created, so the dotfiles
# baked into /home/dev (.bashrc, starship.toml) are shadowed by the volume on
# every later start. An upgraded container therefore keeps whatever dotfile
# shipped when its volume was born — image updates never reach it (issue #89).
#
# Fix: the managed copies also live under /usr/local/lib/squarebox/dotfiles/ — a
# plain image path the volume cannot shadow. The entrypoint runs this on every
# start to copy the current managed dotfile back over the (possibly stale) volume
# copy, so dotfile changes ship with the image like every other tool.
#
# Skips any target the operator bind-mounted (the desktop install.sh path mounts
# dotfiles/bashrc and starship.toml from the host repo, often read-only — the
# host owns those and keeps them in sync itself).
#
# Arg 1 (optional): uid:gid to chown refreshed files to. The entrypoint passes
# the resolved PUID:PGID when it runs this as root before dropping privileges;
# omit it when running unprivileged and the copying user owns the result.
#
# Deliberately NOT `set -e`: report every rejected/failed destination in one
# pass. A non-zero result is authoritative so the entrypoint never continues
# after an unsafe refresh.
set -uo pipefail

owner="${1:-}"
status=0
source_root="${SQUAREBOX_DOTFILES_SOURCE:-/usr/local/lib/squarebox/dotfiles}"
managed_home="${SQUAREBOX_MANAGED_HOME:-/home/dev}"

if [ -n "$owner" ] && [[ ! "$owner" =~ ^[0-9]+:[0-9]+$ ]]; then
	echo "squarebox: invalid dotfile owner '$owner' (expected uid:gid)" >&2
	exit 2
fi

# Return true when the destination itself or any existing directory below the
# Managed home is a symlink. Following one while running as root could
# overwrite a file outside the Managed home.
has_symlink_component() {
	local path="$1"
	while [[ "$path" == "$managed_home"/* ]]; do
		if [ -L "$path" ]; then
			return 0
		fi
		path="$(dirname "$path")"
	done
	return 1
}

# src:dest pairs — src is the non-volume image copy, dest is the volume path.
pairs=(
	"$source_root/bashrc:$managed_home/.bashrc"
	"$source_root/starship.toml:$managed_home/.config/starship.toml"
)

for pair in "${pairs[@]}"; do
	src="${pair%%:*}"
	dest="${pair#*:}"

	[ -f "$src" ] || continue

	if has_symlink_component "$dest"; then
		echo "squarebox: refusing to refresh symlinked dotfile destination: $dest" >&2
		status=1
		continue
	fi

	# Operator bind-mounted this path — host-managed, leave it alone.
	if mountpoint -q -- "$dest" 2>/dev/null; then
		continue
	fi

	# Already current — don't churn the mtime on every start.
	if cmp -s "$src" "$dest" 2>/dev/null; then
		continue
	fi

	if ! mkdir -p "$(dirname "$dest")"; then
		echo "squarebox: failed to create dotfile directory for $dest" >&2
		status=1
		continue
	fi
	# --remove-destination prevents cp from following a destination symlink if
	# one appears between the check above and this operation.
	if ! cp --remove-destination -- "$src" "$dest"; then
		echo "squarebox: failed to refresh $dest" >&2
		status=1
		continue
	fi
	if [ -n "$owner" ] && ! chown -- "$owner" "$dest"; then
		echo "squarebox: failed to set ownership on $dest" >&2
		status=1
	fi
done

exit "$status"

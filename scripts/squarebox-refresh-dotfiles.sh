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
# Deliberately NOT `set -e`: refreshing a convenience dotfile must never abort
# container boot. Every step is best-effort and the script always exits 0.
set -uo pipefail

owner="${1:-}"

# src:dest pairs — src is the non-volume image copy, dest is the volume path.
pairs=(
	"/usr/local/lib/squarebox/dotfiles/bashrc:/home/dev/.bashrc"
	"/usr/local/lib/squarebox/dotfiles/starship.toml:/home/dev/.config/starship.toml"
)

for pair in "${pairs[@]}"; do
	src="${pair%%:*}"
	dest="${pair#*:}"

	[ -f "$src" ] || continue

	# Operator bind-mounted this path — host-managed, leave it alone.
	if mountpoint -q -- "$dest" 2>/dev/null; then
		continue
	fi

	# Already current — don't churn the mtime on every start.
	if cmp -s "$src" "$dest" 2>/dev/null; then
		continue
	fi

	mkdir -p "$(dirname "$dest")" 2>/dev/null
	cp -f "$src" "$dest" 2>/dev/null || continue
	[ -n "$owner" ] && chown "$owner" "$dest" 2>/dev/null
done

exit 0

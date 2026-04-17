#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="squarebox"
CONTAINER_NAME="squarebox"

# On MSYS2/Git Bash, HOME points to the MSYS home (/home/user) while the
# install dir was placed under $USERPROFILE (C:/Users/user/squarebox). Mirror
# install.sh's USER_HOME handling so --purge targets the right directory; the
# shell init file and rc files still live under $HOME (where bash reads from).
if [ -n "${USERPROFILE:-}" ]; then
	USER_HOME="$(cygpath -m "$USERPROFILE" 2>/dev/null || true)"
	if [ -z "$USER_HOME" ]; then
		USER_HOME="${USERPROFILE//\\//}"
		if [[ "$USER_HOME" =~ ^/([a-zA-Z])(/.*)$ ]]; then
			USER_HOME="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'):${BASH_REMATCH[2]}"
		fi
	fi
else
	USER_HOME="${HOME}"
fi
INSTALL_DIR="${USER_HOME}/squarebox"
SHELL_INIT_FILE="${HOME}/.squarebox-shell-init"

usage() {
	cat <<'EOF'
Usage: uninstall.sh [OPTIONS]

Remove the squarebox container, image, and shell integration.

Options:
  --purge              Also remove the install directory (~/squarebox),
                       including workspace/ and any host-side config under it.
  -y, --yes            Skip all confirmation prompts (for scripting).
  --runtime RUNTIME    Use docker or podman explicitly (default: auto-detect by
                       looking for the squarebox container/image).
  -h, --help           Show this help and exit.

Environment:
  SQUAREBOX_RUNTIME    Same as --runtime (the flag takes priority).

By default, ~/squarebox is preserved so your workspace is not lost. Use --purge
to remove it; a second confirmation is required if workspace/ is non-empty.
EOF
}

PURGE=0
YES=0
RUNTIME_OVERRIDE=""

while [ $# -gt 0 ]; do
	case "$1" in
		--purge) PURGE=1; shift ;;
		-y|--yes) YES=1; shift ;;
		--runtime=*) RUNTIME_OVERRIDE="${1#*=}"; shift ;;
		--runtime)
			if [ $# -lt 2 ]; then
				echo "Error: --runtime requires a value (docker or podman)." >&2
				exit 1
			fi
			RUNTIME_OVERRIDE="$2"
			shift 2
			;;
		-h|--help) usage; exit 0 ;;
		*) echo "Error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
	esac
done

# On MSYS2/Git Bash, disable automatic path conversion for container runtime
# args (same rationale as install.sh's rt_cmd).
rt_cmd() {
	if [[ -n "${MSYSTEM:-}" ]]; then
		MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$RUNTIME" "$@"
	else
		"$RUNTIME" "$@"
	fi
}

# Returns 0 if the given runtime has a squarebox container or image.
_rt_has_state() {
	local rt="$1" out
	local msys_env=()
	[[ -n "${MSYSTEM:-}" ]] && msys_env=(env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*')
	out="$("${msys_env[@]}" "$rt" ps -a --format '{{.Names}}' 2>/dev/null || true)"
	printf '%s\n' "$out" | grep -qx "$CONTAINER_NAME" && return 0
	out="$("${msys_env[@]}" "$rt" images --format '{{.Repository}}' 2>/dev/null || true)"
	printf '%s\n' "$out" | grep -qx "$IMAGE_NAME" && return 0
	return 1
}

# Detect runtime. Priority: --runtime > SQUAREBOX_RUNTIME > auto-detect by
# looking for squarebox container/image. If both runtimes have state (unusual),
# prefer docker (matching install.sh's preference) and warn about podman.
_has_docker=0; command -v docker &>/dev/null && _has_docker=1
_has_podman=0; command -v podman &>/dev/null && _has_podman=1

RUNTIME=""
SECONDARY_RUNTIME=""

if [ -n "$RUNTIME_OVERRIDE" ]; then
	case "$RUNTIME_OVERRIDE" in
		docker|podman) RUNTIME="$RUNTIME_OVERRIDE" ;;
		*) echo "Error: --runtime must be 'docker' or 'podman' (got '$RUNTIME_OVERRIDE')." >&2; exit 1 ;;
	esac
	if ! command -v "$RUNTIME" &>/dev/null; then
		echo "Error: --runtime=$RUNTIME but '$RUNTIME' is not installed." >&2
		exit 1
	fi
elif [ -n "${SQUAREBOX_RUNTIME:-}" ]; then
	case "$SQUAREBOX_RUNTIME" in
		docker|podman) RUNTIME="$SQUAREBOX_RUNTIME" ;;
		*) echo "Error: SQUAREBOX_RUNTIME must be 'docker' or 'podman' (got '$SQUAREBOX_RUNTIME')." >&2; exit 1 ;;
	esac
	if ! command -v "$RUNTIME" &>/dev/null; then
		echo "Error: SQUAREBOX_RUNTIME=$RUNTIME but '$RUNTIME' is not installed." >&2
		exit 1
	fi
else
	_docker_state=0
	_podman_state=0
	[ "$_has_docker" = 1 ] && _rt_has_state docker && _docker_state=1
	[ "$_has_podman" = 1 ] && _rt_has_state podman && _podman_state=1

	if [ "$_docker_state" = 1 ] && [ "$_podman_state" = 1 ]; then
		RUNTIME="docker"
		SECONDARY_RUNTIME="podman"
	elif [ "$_docker_state" = 1 ]; then
		RUNTIME="docker"
	elif [ "$_podman_state" = 1 ]; then
		RUNTIME="podman"
	elif [ "$_has_docker" = 1 ]; then
		RUNTIME="docker"
	elif [ "$_has_podman" = 1 ]; then
		RUNTIME="podman"
	fi
fi

# Probe state for the summary.
has_container=0
has_image=0
if [ -n "$RUNTIME" ]; then
	if rt_cmd ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
		has_container=1
	fi
	if rt_cmd images --format '{{.Repository}}' 2>/dev/null | grep -qx "$IMAGE_NAME"; then
		has_image=1
	fi
fi

has_shell_init=0
[ -f "$SHELL_INIT_FILE" ] && has_shell_init=1

# An rc file needs scrubbing if it has a squarebox sentinel block OR orphan
# alias/function defs from a legacy install. Same patterns install.sh uses to
# decide whether its scrub will change anything.
_rc_scrub_pattern='^# >>> squarebox >>>|^[[:space:]]*alias[[:space:]]+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)=|^(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)\(\)[[:space:]]*\{'

_rc_files_to_scrub=()
for f in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
	if [ -f "$f" ] && grep -qE "$_rc_scrub_pattern" "$f" 2>/dev/null; then
		_rc_files_to_scrub+=("$f")
	fi
done

# install.sh appends this exact 2-line snippet to ~/.bash_profile on Git Bash
# so a login shell picks up the sentinel in ~/.bashrc. Remove it on match.
_bash_profile="${HOME}/.bash_profile"
has_bash_profile_source_line=0
if [ -f "$_bash_profile" ] \
	&& grep -qxF '# Source .bashrc for aliases and functions' "$_bash_profile" 2>/dev/null \
	&& grep -qxF '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' "$_bash_profile" 2>/dev/null; then
	has_bash_profile_source_line=1
fi

has_install_dir=0
[ -d "$INSTALL_DIR" ] && has_install_dir=1

# Summary.
echo "squarebox uninstall"
echo "==================="
echo ""

if [ -n "$RUNTIME" ]; then
	echo "Container runtime: $RUNTIME"
else
	echo "Container runtime: none detected (skipping container/image cleanup)"
fi

if [ -n "$SECONDARY_RUNTIME" ]; then
	echo ""
	echo "Note: squarebox state also detected in $SECONDARY_RUNTIME."
	echo "      This run will clean $RUNTIME only. To also clean $SECONDARY_RUNTIME, run again with:"
	echo "        SQUAREBOX_RUNTIME=$SECONDARY_RUNTIME $0"
fi

anything_to_do=0

echo ""
echo "Will remove:"
if [ "$has_container" = 1 ]; then
	echo "  - Container:      $CONTAINER_NAME ($RUNTIME)"
	anything_to_do=1
fi
if [ "$has_image" = 1 ]; then
	echo "  - Image:          $IMAGE_NAME ($RUNTIME)"
	anything_to_do=1
fi
if [ "$has_shell_init" = 1 ]; then
	echo "  - Shell init:     $SHELL_INIT_FILE"
	anything_to_do=1
fi
for f in "${_rc_files_to_scrub[@]}"; do
	echo "  - Sentinel block: $f"
	anything_to_do=1
done
if [ "$has_bash_profile_source_line" = 1 ]; then
	echo "  - Source snippet: $_bash_profile"
	anything_to_do=1
fi
if [ "$PURGE" = 1 ] && [ "$has_install_dir" = 1 ]; then
	echo "  - Install dir:    $INSTALL_DIR"
	anything_to_do=1
fi
if [ "$anything_to_do" = 0 ]; then
	echo "  (nothing)"
fi

if [ "$PURGE" = 0 ] && [ "$has_install_dir" = 1 ]; then
	echo ""
	echo "Will KEEP:"
	echo "  - $INSTALL_DIR (re-run with --purge to remove, including workspace)"
fi

echo ""

if [ "$anything_to_do" = 0 ]; then
	echo "Nothing to do - squarebox appears to be already uninstalled."
	exit 0
fi

# Confirmation. Non-interactive stdin without -y is an error, otherwise the
# read would hang or consume a subsequent line the caller didn't intend.
if [ "$YES" = 0 ] && [ ! -t 0 ]; then
	echo "Error: stdin is not a terminal; pass -y to run non-interactively." >&2
	exit 1
fi

if [ "$YES" = 0 ]; then
	printf "Proceed? [y/N]: "
	read -r _answer
	case "$_answer" in
		[yY]|[yY][eE][sS]) ;;
		*) echo "Aborted." >&2; exit 1 ;;
	esac
fi

if [ "$PURGE" = 1 ] && [ "$has_install_dir" = 1 ] && [ "$YES" = 0 ]; then
	_workspace_dir="${INSTALL_DIR}/workspace"
	if [ -d "$_workspace_dir" ]; then
		_count=$(find "$_workspace_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
		if [ "$_count" -gt 0 ]; then
			echo ""
			echo "Warning: $_workspace_dir contains $_count item(s)."
			echo "         Purging will permanently delete them."
			printf "Really purge workspace? [y/N]: "
			read -r _answer
			case "$_answer" in
				[yY]|[yY][eE][sS]) ;;
				*) echo "Aborted." >&2; exit 1 ;;
			esac
		fi
	fi
fi

# Perform the work. cd away first so we can safely rm INSTALL_DIR if --purge
# and so we don't trip over a deleted cwd on return.
cd /

removed_container=0
removed_image=0
removed_shell_init=0
removed_rc_entries=()
removed_bash_profile_source=0
removed_install_dir=0

if [ "$has_container" = 1 ]; then
	echo "Stopping container..."
	rt_cmd stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
	echo "Removing container..."
	if rt_cmd rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
		removed_container=1
	fi
fi

if [ "$has_image" = 1 ]; then
	echo "Removing image..."
	if rt_cmd rmi -f "$IMAGE_NAME" >/dev/null 2>&1; then
		removed_image=1
	fi
fi

if [ "$has_shell_init" = 1 ]; then
	rm -f "$SHELL_INIT_FILE"
	removed_shell_init=1
fi

# Same scrub as install.sh's awk at install.sh:228-235, extended to also match
# sqrbx-uninstall / squarebox-uninstall legacy defs. Keeping this in sync with
# install.sh is manual for now; consolidating into a shared helper is flagged
# as future work.
_scrub_rc() {
	local rc="$1" tmp
	[ -f "$rc" ] || return 0
	tmp="$(mktemp "${rc}.sqrbx.XXXXXX")"
	awk '
		/^# >>> squarebox >>>/ { skip=1; next }
		/^# <<< squarebox <<</ { skip=0; next }
		skip { next }
		/^[[:space:]]*alias[[:space:]]+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)=/ { next }
		/^(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)\(\)[[:space:]]*\{/ { next }
		{ print }
	' "$rc" > "$tmp" && mv "$tmp" "$rc"
}

for f in "${_rc_files_to_scrub[@]}"; do
	_scrub_rc "$f"
	removed_rc_entries+=("$f")
done

# Scrub the Git Bash .bash_profile 2-line source snippet. Exact match only so
# we don't touch user-authored .bashrc source lines.
if [ "$has_bash_profile_source_line" = 1 ]; then
	_tmp="$(mktemp "${_bash_profile}.sqrbx.XXXXXX")"
	awk '
		$0 == "# Source .bashrc for aliases and functions" {
			if ((getline nextline) > 0) {
				if (nextline == "[ -f \"$HOME/.bashrc\" ] && . \"$HOME/.bashrc\"") {
					next
				}
				print
				print nextline
				next
			}
			print
			next
		}
		{ print }
	' "$_bash_profile" > "$_tmp" && mv "$_tmp" "$_bash_profile"
	removed_bash_profile_source=1
fi

if [ "$PURGE" = 1 ] && [ "$has_install_dir" = 1 ]; then
	echo "Removing install directory..."
	# On Linux installs where host uid != 1000, files under workspace/ and
	# .config/ may be owned by the container's dev user (uid 1000). Fall back
	# to sudo if a plain rm fails for permission reasons.
	if ! rm -rf "$INSTALL_DIR" 2>/dev/null; then
		if [ "$(id -u)" -eq 0 ]; then
			rm -rf "$INSTALL_DIR"
		elif command -v sudo &>/dev/null; then
			echo "Some files owned by uid 1000 (container's dev user); using sudo..."
			sudo rm -rf "$INSTALL_DIR"
		else
			echo "Error: failed to remove $INSTALL_DIR - some files may be owned by uid 1000." >&2
			echo "       Run: sudo rm -rf $INSTALL_DIR" >&2
			exit 1
		fi
	fi
	removed_install_dir=1
fi

echo ""
echo "Done."
[ "$removed_container" = 1 ] && echo "  Removed container $CONTAINER_NAME from $RUNTIME."
[ "$removed_image" = 1 ]     && echo "  Removed image $IMAGE_NAME from $RUNTIME."
[ "$removed_shell_init" = 1 ] && echo "  Removed $SHELL_INIT_FILE."
for f in "${removed_rc_entries[@]}"; do
	echo "  Scrubbed squarebox block from $f."
done
[ "$removed_bash_profile_source" = 1 ] && echo "  Scrubbed .bashrc source snippet from $_bash_profile."
[ "$removed_install_dir" = 1 ]         && echo "  Removed $INSTALL_DIR."

if [ "$PURGE" = 0 ] && [ "$has_install_dir" = 1 ]; then
	echo ""
	echo "Kept $INSTALL_DIR (including workspace). Remove manually with:"
	echo "  rm -rf $INSTALL_DIR"
fi

echo ""
echo "Note: sqrbx, squarebox, and related functions may still be defined in"
echo "      your current shell. Start a new shell (or 'exec bash' / 'exec zsh')"
echo "      to drop them."

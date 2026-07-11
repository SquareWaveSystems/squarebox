#!/usr/bin/env bash
set -euo pipefail

IDENTITY_LABEL=io.squarebox.install-id
REPO=https://github.com/SquareWaveSystems/squarebox.git
usage() {
	cat <<'EOF'
Usage: uninstall.sh [--purge] [-y|--yes] [--runtime docker|podman]
                    [--adopt] [--force]

  --purge    Also remove the recorded install directory and Managed home.
  --adopt    Explicitly adopt an origin-verified legacy install with no state.
  --force    Permit purge of an explicitly adopted, unlabeled legacy volume.

Destructive actions consume .squarebox/install-state and verify resource
ownership. A familiar fixed name is never sufficient authority.
EOF
}

PURGE=0; YES=0; ADOPT=0; FORCE=0; RUNTIME_OVERRIDE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--purge) PURGE=1; shift ;; -y|--yes) YES=1; shift ;;
		--adopt) ADOPT=1; shift ;; --force) FORCE=1; shift ;;
		--runtime=*) RUNTIME_OVERRIDE="${1#*=}"; shift ;;
		--runtime) [ $# -ge 2 ] || { echo "Error: --runtime requires a value." >&2; exit 64; }; RUNTIME_OVERRIDE="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Error: unknown option '$1'" >&2; usage >&2; exit 64 ;;
	esac
done

WINDOWS_BASH=0
[ -n "${MSYSTEM:-}" ] && WINDOWS_BASH=1
if [ "$WINDOWS_BASH" = 1 ] && [ -n "${USERPROFILE:-}" ]; then
	USER_HOME="$(cygpath -m "$USERPROFILE" 2>/dev/null || true)"
	if [ -z "$USER_HOME" ]; then
		USER_HOME="${USERPROFILE//\\//}"
		if [[ "$USER_HOME" =~ ^/([a-zA-Z])(/.*)$ ]]; then
			USER_HOME="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'):${BASH_REMATCH[2]}"
		fi
	fi
else USER_HOME="$HOME"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
if [ "$WINDOWS_BASH" = 1 ] && [ -n "$SCRIPT_DIR" ]; then SCRIPT_DIR="$(cygpath -m "$SCRIPT_DIR" 2>/dev/null || printf '%s' "$SCRIPT_DIR")"; fi
if [ -n "${SQUAREBOX_DIR+x}" ]; then INSTALL_DIR="$SQUAREBOX_DIR"
elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.squarebox/install-state" ]; then INSTALL_DIR="$SCRIPT_DIR"
else INSTALL_DIR="$USER_HOME/squarebox"
fi
while [[ "$INSTALL_DIR" == */ && "$INSTALL_DIR" != / && ! "$INSTALL_DIR" =~ ^[A-Za-z]:/$ ]]; do INSTALL_DIR="${INSTALL_DIR%/}"; done
STATE_FILE="$INSTALL_DIR/.squarebox/install-state"
[ ! -L "$INSTALL_DIR/.squarebox" ] && [ ! -L "$STATE_FILE" ] || {
	echo "Error: Install identity state must not be reached through a symlink." >&2; exit 1;
}

STATE_FORMAT=""; INSTALL_ID=""; RUNTIME=""; STATE_INSTALL_DIR=""; WORKSPACE_DIR=""
GIT_CONFIG_DIR=""; HOME_VOLUME=""; CONTAINER_NAME=""; IMAGE_ALIAS=""; IMAGE_REF=""
IMAGE_REPOSITORY=""; IMAGE_ID=""; IMAGE_DIGEST=""; SOURCE_REF=""; SOURCE_COMMIT=""
RELEASE_TAG=""; REQUESTED_TAG=""; PUID=""; PGID=""; BUILD=""; EDGE=""
SHELL_INIT=""; SHELL_RC=""; ORIGIN=""; HOME_VOLUME_ADOPTED=0
STATE_KEYS="FORMAT INSTALL_ID RUNTIME INSTALL_DIR WORKSPACE_DIR GIT_CONFIG_DIR HOME_VOLUME CONTAINER_NAME IMAGE_ALIAS IMAGE_REPOSITORY IMAGE_REF IMAGE_ID IMAGE_DIGEST SOURCE_REF SOURCE_COMMIT RELEASE_TAG REQUESTED_TAG PUID PGID BUILD EDGE SHELL_INIT SHELL_RC ORIGIN HOME_VOLUME_ADOPTED"
STATE_SCHEMA_VALID=1
invalid_state() {
	echo "Error: invalid Install identity: $STATE_FILE${1:+ ($1)}" >&2
	STATE_SCHEMA_VALID=0
	return 0
}
is_release_tag() {
	[ "${#1}" -le 128 ] \
		&& [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?$ ]]
}
is_absolute_state_path() {
	case "$1" in
		/*) ;;
		[A-Za-z]:/*) [ "$WINDOWS_BASH" = 1 ] || return 1 ;;
		*) return 1 ;;
	esac
	case "$1" in */../*|*/..|*/./*|*/.|*[$'\001'-$'\037'$'\177']*) return 1 ;; esac
}
is_root_state_path() {
	case "$1" in
		/) return 0 ;;
		[A-Za-z]:/) [ "$WINDOWS_BASH" = 1 ] ;;
		*) return 1 ;;
	esac
}
same_state_path() {
	local left="$1" right="$2"
	[ "$left" = "$right" ] && return 0
	[ "$WINDOWS_BASH" = 1 ] || return 1
	[ "$(printf '%s' "$left" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$right" | tr '[:upper:]' '[:lower:]')" ]
}
valid_state_id() {
	[[ "$1" =~ ^[0-9]{1,10}$ ]] && [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 2147483647 ]
}
validate_state_schema() {
	STATE_SCHEMA_VALID=1
	[ "$STATE_FORMAT" = 1 ] || invalid_state 'FORMAT must be 1'
	[[ "$INSTALL_ID" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || invalid_state 'invalid INSTALL_ID'
	case "$RUNTIME" in docker|podman) ;; *) invalid_state 'invalid RUNTIME' ;; esac
	same_state_path "$STATE_INSTALL_DIR" "$INSTALL_DIR" || invalid_state 'INSTALL_DIR path mismatch'
	for _path in "$STATE_INSTALL_DIR" "$WORKSPACE_DIR" "$GIT_CONFIG_DIR" "$SHELL_INIT" "$SHELL_RC"; do
		is_absolute_state_path "$_path" || invalid_state 'paths must be absolute and normalized'
	done
	! is_root_state_path "$STATE_INSTALL_DIR" && ! same_state_path "$STATE_INSTALL_DIR" "$USER_HOME" && ! same_state_path "$STATE_INSTALL_DIR" "$HOME" \
		|| invalid_state 'unsafe INSTALL_DIR'
	! is_root_state_path "$WORKSPACE_DIR" && ! same_state_path "$WORKSPACE_DIR" "$STATE_INSTALL_DIR" \
		&& ! same_state_path "$WORKSPACE_DIR" "$USER_HOME" && ! same_state_path "$WORKSPACE_DIR" "$HOME" \
		|| invalid_state 'unsafe WORKSPACE_DIR'
	same_state_path "$GIT_CONFIG_DIR" "$STATE_INSTALL_DIR/.squarebox/identity/git" || invalid_state 'GIT_CONFIG_DIR is outside managed identity state'
	same_state_path "$SHELL_INIT" "$HOME/.squarebox-shell-init" || invalid_state 'unexpected SHELL_INIT path'
	same_state_path "$SHELL_RC" "$HOME/.bashrc" || same_state_path "$SHELL_RC" "$HOME/.zshrc" || invalid_state 'unexpected SHELL_RC path'
	[[ "$HOME_VOLUME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || invalid_state 'invalid HOME_VOLUME'
	[[ "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || invalid_state 'invalid CONTAINER_NAME'
	[[ "$IMAGE_ALIAS" =~ ^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$ ]] || invalid_state 'invalid IMAGE_ALIAS'
	[[ "$IMAGE_REPOSITORY" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || invalid_state 'invalid IMAGE_REPOSITORY'
	[[ "$IMAGE_ID" =~ ^(sha256:)?[0-9a-f]{64}$ ]] || invalid_state 'invalid IMAGE_ID'
	if [ -n "$IMAGE_DIGEST" ]; then
		[[ "$IMAGE_DIGEST" =~ ^[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$ ]] || invalid_state 'invalid IMAGE_DIGEST'
	fi
	[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || invalid_state 'invalid SOURCE_COMMIT'
	valid_state_id "$PUID" || invalid_state 'invalid PUID'
	valid_state_id "$PGID" || invalid_state 'invalid PGID'
	case "$BUILD:$EDGE:$HOME_VOLUME_ADOPTED" in
		0:0:0|0:0:1|1:0:0|1:0:1|1:1:0|1:1:1) ;;
		*) invalid_state 'invalid BUILD, EDGE, or HOME_VOLUME_ADOPTED flag' ;;
	esac
	[ "$ORIGIN" = "$REPO" ] || invalid_state 'noncanonical ORIGIN'
	if [ "$EDGE" = 1 ]; then
		[ -z "$RELEASE_TAG" ] && [ -z "$REQUESTED_TAG" ] && [ "$SOURCE_REF" = refs/remotes/origin/main ] \
			|| invalid_state 'inconsistent edge source identity'
	else
		is_release_tag "$RELEASE_TAG" || invalid_state 'invalid RELEASE_TAG'
		[ "$SOURCE_REF" = "$RELEASE_TAG" ] || invalid_state 'SOURCE_REF does not match RELEASE_TAG'
		case "$REQUESTED_TAG" in ''|latest) ;; *)
			is_release_tag "$REQUESTED_TAG" && [ "$REQUESTED_TAG" = "$RELEASE_TAG" ] || invalid_state 'invalid REQUESTED_TAG' ;;
		esac
	fi
	if [ "$BUILD" = 1 ]; then
		[ "$IMAGE_REF" = "$IMAGE_ALIAS" ] || invalid_state 'built IMAGE_REF must equal IMAGE_ALIAS'
	else
		case "$RELEASE_TAG" in v1.0.0|v1.0.0-rc*)
			[ "$IMAGE_REF" = "$IMAGE_REPOSITORY:$RELEASE_TAG" ] && [ -n "$IMAGE_DIGEST" ] \
				&& [[ "$IMAGE_DIGEST" == "$IMAGE_REPOSITORY"@sha256:* ]] || invalid_state 'invalid legacy IMAGE_REF' ;;
		*)
			[ -n "$IMAGE_DIGEST" ] && [ "$IMAGE_REF" = "$IMAGE_DIGEST" ] \
				&& [[ "$IMAGE_REF" == "$IMAGE_REPOSITORY"@sha256:* ]] || invalid_state 'release image identities do not match' ;;
		esac
	fi
	[ "$STATE_SCHEMA_VALID" = 1 ]
}
load_state() {
	local line key value seen="" expected
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in ''|'#'*) continue ;; esac
		case "$line" in *$'\r'*) echo "Error: malformed Install identity: $STATE_FILE" >&2; return 1 ;; esac
		key="${line%%=*}"; value="${line#*=}"; [ "$key" != "$line" ] || return 1
		case "$key" in
			FORMAT|INSTALL_ID|RUNTIME|INSTALL_DIR|WORKSPACE_DIR|GIT_CONFIG_DIR|HOME_VOLUME|CONTAINER_NAME|IMAGE_ALIAS|IMAGE_REPOSITORY|IMAGE_REF|IMAGE_ID|IMAGE_DIGEST|SOURCE_REF|SOURCE_COMMIT|RELEASE_TAG|REQUESTED_TAG|PUID|PGID|BUILD|EDGE|SHELL_INIT|SHELL_RC|ORIGIN|HOME_VOLUME_ADOPTED) ;;
			*) echo "Error: malformed Install identity: $STATE_FILE (unknown field '$key')" >&2; return 1 ;;
		esac
		case "|$seen|" in *"|$key|"*) echo "Error: malformed Install identity: $STATE_FILE (duplicate field '$key')" >&2; return 1 ;; esac
		seen="${seen:+$seen|}$key"
		case "$key" in
			FORMAT) STATE_FORMAT="$value" ;; INSTALL_ID) INSTALL_ID="$value" ;; RUNTIME) RUNTIME="$value" ;;
			INSTALL_DIR) STATE_INSTALL_DIR="$value" ;; WORKSPACE_DIR) WORKSPACE_DIR="$value" ;;
			GIT_CONFIG_DIR) GIT_CONFIG_DIR="$value" ;; HOME_VOLUME) HOME_VOLUME="$value" ;;
			CONTAINER_NAME) CONTAINER_NAME="$value" ;; IMAGE_ALIAS) IMAGE_ALIAS="$value" ;;
			IMAGE_REPOSITORY) IMAGE_REPOSITORY="$value" ;; IMAGE_REF) IMAGE_REF="$value" ;;
			IMAGE_ID) IMAGE_ID="$value" ;; IMAGE_DIGEST) IMAGE_DIGEST="$value" ;;
			SOURCE_REF) SOURCE_REF="$value" ;; SOURCE_COMMIT) SOURCE_COMMIT="$value" ;;
			RELEASE_TAG) RELEASE_TAG="$value" ;; REQUESTED_TAG) REQUESTED_TAG="$value" ;;
			PUID) PUID="$value" ;; PGID) PGID="$value" ;; BUILD) BUILD="$value" ;; EDGE) EDGE="$value" ;;
			SHELL_INIT) SHELL_INIT="$value" ;; SHELL_RC) SHELL_RC="$value" ;;
			ORIGIN) ORIGIN="$value" ;; HOME_VOLUME_ADOPTED) HOME_VOLUME_ADOPTED="$value" ;;
		esac
	done <"$STATE_FILE"
	for expected in $STATE_KEYS; do
		case "|$seen|" in *"|$expected|"*) ;; *) echo "Error: malformed Install identity: $STATE_FILE (missing field '$expected')" >&2; return 1 ;; esac
	done
	validate_state_schema
}

HAD_STATE=0
if [ -f "$STATE_FILE" ]; then
	load_state || { echo "Error: invalid Install identity: $STATE_FILE" >&2; exit 1; }
	HAD_STATE=1
elif [ "$ADOPT" = 1 ]; then
	_origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
	case "$_origin" in
		https://github.com/SquareWaveSystems/squarebox|https://github.com/SquareWaveSystems/squarebox.git|git@github.com:SquareWaveSystems/squarebox.git|ssh://git@github.com/SquareWaveSystems/squarebox.git) ;;
		*) echo "Error: legacy adoption requires an origin-verified squarebox checkout." >&2; exit 1 ;;
	esac
	RUNTIME="${RUNTIME_OVERRIDE:-${SQUAREBOX_RUNTIME:-}}"; WORKSPACE_DIR="$INSTALL_DIR/workspace"
	HOME_VOLUME="${SQUAREBOX_HOME_VOLUME:-squarebox-home}"; CONTAINER_NAME=squarebox
	IMAGE_ALIAS=squarebox; IMAGE_REF=squarebox; SHELL_INIT="$HOME/.squarebox-shell-init"; SHELL_RC=""
else
	echo "Error: no Install identity at $STATE_FILE. Use --adopt only for a verified legacy install." >&2
	exit 1
fi

if [ -n "$RUNTIME_OVERRIDE" ]; then
	case "$RUNTIME_OVERRIDE" in docker|podman) ;; *) echo "Error: runtime must be docker or podman." >&2; exit 64 ;; esac
	if [ "$HAD_STATE" = 1 ] && [ "$RUNTIME_OVERRIDE" != "$RUNTIME" ] && [ "$FORCE" != 1 ]; then
		echo "Error: override differs from recorded runtime '$RUNTIME'; use --force only after verifying the migration." >&2; exit 1
	fi
	RUNTIME="$RUNTIME_OVERRIDE"
fi
if [ -z "$RUNTIME" ]; then
	if command -v docker >/dev/null 2>&1; then RUNTIME=docker
	elif command -v podman >/dev/null 2>&1; then RUNTIME=podman
	else echo "Error: no runtime recorded or installed; resource ownership cannot be checked." >&2; exit 1
	fi
fi
case "$RUNTIME" in docker|podman) ;; *) echo "Error: invalid recorded runtime '$RUNTIME'." >&2; exit 1 ;; esac
command -v "$RUNTIME" >/dev/null 2>&1 || { echo "Error: recorded runtime '$RUNTIME' is not installed; resources were not removed." >&2; exit 1; }
rt_cmd() {
	if [[ -n "${MSYSTEM:-}" ]]; then MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$RUNTIME" "$@"; else "$RUNTIME" "$@"; fi
}
normalize_label() {
	case "$1" in '<no value>'|'<nil>') printf '' ;; *) printf '%s' "$1" ;; esac
}
assert_purge_checkout() {
	local logical physical origin
	[ -d "$INSTALL_DIR" ] || return 0
	[ ! -L "$INSTALL_DIR" ] || { echo "Error: recorded purge path is a symlink: $INSTALL_DIR" >&2; return 1; }
	logical="$(cd -L -- "$INSTALL_DIR" 2>/dev/null && pwd -L)" || {
		echo "Error: unable to resolve recorded purge path '$INSTALL_DIR'." >&2; return 1;
	}
	physical="$(cd -P -- "$INSTALL_DIR" 2>/dev/null && pwd -P)" || {
		echo "Error: unable to resolve recorded purge path '$INSTALL_DIR'." >&2; return 1;
	}
	[ "$logical" = "$physical" ] || {
		echo "Error: recorded purge path crosses a symlinked directory component: $INSTALL_DIR" >&2; return 1;
	}
	origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
	case "$origin" in
		https://github.com/SquareWaveSystems/squarebox|https://github.com/SquareWaveSystems/squarebox.git|git@github.com:SquareWaveSystems/squarebox.git|ssh://git@github.com/SquareWaveSystems/squarebox.git) ;;
		*) echo "Error: recorded install directory no longer has the expected origin; refusing purge." >&2; return 1 ;;
	esac
}
resource_owner() {
	local kind="$1" name="$2" value=""
	case "$kind" in
		container)
			if ! value="$(rt_cmd inspect -f '{{ index .Config.Labels "io.squarebox.install-id" }}' "$name" 2>/dev/null)"; then
				echo "Error: unable to verify ownership label for Box '$name'." >&2; return 1
			fi ;;
		volume)
			if ! value="$(rt_cmd volume inspect -f '{{ index .Labels "io.squarebox.install-id" }}' "$name" 2>/dev/null)"; then
				echo "Error: unable to verify ownership label for Managed home '$name'." >&2; return 1
			fi ;;
		*) echo "Error: unknown managed-resource type '$kind'." >&2; return 1 ;;
	esac
	normalize_label "$value"
}
if ! rt_cmd info >/dev/null 2>&1; then
	echo "Error: $RUNTIME is installed but unreachable; this is not evidence that no resources exist." >&2; exit 1
fi

container_owned=0; image_owned=0; volume_owned=0
if rt_cmd container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
	_owner="$(resource_owner container "$CONTAINER_NAME")"
	if [ "$HAD_STATE" = 1 ]; then
		[ "$_owner" = "$INSTALL_ID" ] || { echo "Error: Box '$CONTAINER_NAME' is not owned by this Install identity." >&2; exit 1; }
	else
		[ -z "$_owner" ] || { echo "Error: legacy Box is labeled for another identity." >&2; exit 1; }
	fi
	container_owned=1
fi
if rt_cmd image inspect "$IMAGE_ALIAS" >/dev/null 2>&1; then
	_observed_image="$(rt_cmd image inspect -f '{{.Id}}' "$IMAGE_ALIAS")"
	if [ "$HAD_STATE" = 1 ]; then
		[ -n "$IMAGE_ID" ] && [ "$_observed_image" = "$IMAGE_ID" ] || { echo "Error: image alias '$IMAGE_ALIAS' no longer matches the recorded image." >&2; exit 1; }
	fi
	image_owned=1
fi
if rt_cmd volume inspect "$HOME_VOLUME" >/dev/null 2>&1; then
	_owner="$(resource_owner volume "$HOME_VOLUME")"
	if [ "$HAD_STATE" = 1 ] && [ "$HOME_VOLUME_ADOPTED" != 1 ]; then
		[ "$_owner" = "$INSTALL_ID" ] || { echo "Error: Managed home '$HOME_VOLUME' is not owned by this Install identity." >&2; exit 1; }
	elif [ -n "$_owner" ] && ! { [ "$HAD_STATE" = 1 ] && [ "$_owner" = "$INSTALL_ID" ]; }; then
		echo "Error: unlabeled legacy adoption cannot claim a volume labeled for another identity." >&2; exit 1
	fi
	volume_owned=1
fi

assert_regular_host_file() {
	local file="$1" description="$2"
	[ ! -L "$file" ] || { echo "Error: $description must not be a symlink: $file" >&2; return 1; }
	[ ! -e "$file" ] || [ -f "$file" ] || { echo "Error: $description is not a regular file: $file" >&2; return 1; }
}
block_present() {
	local file="$1" start="$2" finish="$3"
	[ -f "$file" ] || return 1
	awk -v start="$start" -v finish="$finish" '
		{ line=$0; sub(/\r$/, "", line); if (line == start || line == finish) found=1 }
		END { exit(found ? 0 : 1) }
	' "$file"
}
validate_managed_block() {
	local file="$1" start="$2" finish="$3" description="$4"
	assert_regular_host_file "$file" "$description"
	awk -v start="$start" -v finish="$finish" '
		{
			line=$0; sub(/\r$/, "", line)
			if (line == start) { if (inside || blocks) exit 42; inside=1; blocks=1; next }
			if (line == finish) { if (!inside) exit 42; inside=0; next }
		}
		END { if (inside || blocks != 1) exit 42 }
	' "$file" || {
		echo "Error: malformed $description marker block in $file; the file was preserved." >&2; return 1;
	}
}
copy_mode() {
	local source="$1" destination="$2" mode=""
	mode="$(stat -c '%a' "$source" 2>/dev/null || stat -f '%Lp' "$source" 2>/dev/null || true)"
	[ -z "$mode" ] || chmod "$mode" "$destination" 2>/dev/null || true
}
scrub_managed_block() {
	local file="$1" start="$2" finish="$3" description="$4" tmp
	validate_managed_block "$file" "$start" "$finish" "$description"
	tmp="$(mktemp "${file}.sqrbx.XXXXXX")"
	awk -v start="$start" -v finish="$finish" '
		{ line=$0; sub(/\r$/, "", line); if (line == start) { inside=1; next }; if (line == finish) { inside=0; next }; if (!inside) print }
	' "$file" >"$tmp"
	copy_mode "$file" "$tmp"
	mv -f -- "$tmp" "$file"
}

has_shell_init=0
if [ -e "$SHELL_INIT" ] || [ -L "$SHELL_INIT" ]; then
	assert_regular_host_file "$SHELL_INIT" 'recorded shell adapter'
	if [ "$HAD_STATE" = 1 ] && ! grep -qxF "# squarebox-install-id=$INSTALL_ID" "$SHELL_INIT"; then
		echo "Error: recorded shell adapter '$SHELL_INIT' is not owned by this Install identity." >&2; exit 1
	fi
	has_shell_init=1
fi
rc_files=()
for _rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
	if block_present "$_rc" '# >>> squarebox >>>' '# <<< squarebox <<<'; then
		validate_managed_block "$_rc" '# >>> squarebox >>>' '# <<< squarebox <<<' 'shell profile'
		rc_files+=("$_rc")
	fi
done
has_bridge=0
if block_present "$HOME/.bash_profile" '# >>> squarebox bashrc bridge >>>' '# <<< squarebox bashrc bridge <<<'; then
	validate_managed_block "$HOME/.bash_profile" '# >>> squarebox bashrc bridge >>>' '# <<< squarebox bashrc bridge <<<' 'Git Bash bridge'
	has_bridge=1
fi

echo "squarebox uninstall"
echo "==================="
echo "Install identity: ${INSTALL_ID:-legacy adoption}"
echo "Runtime:          $RUNTIME (reachable)"
echo "Install dir:      $INSTALL_DIR"
echo ""
echo "Will remove:"
anything=0
[ "$container_owned" = 1 ] && { echo "  - Managed Box: $CONTAINER_NAME"; anything=1; }
[ "$image_owned" = 1 ] && { echo "  - Recorded image refs: $IMAGE_ALIAS ${IMAGE_REF:+and $IMAGE_REF}"; anything=1; }
[ "$has_shell_init" = 1 ] && { echo "  - Shell adapter: $SHELL_INIT"; anything=1; }
for _rc in "${rc_files[@]}"; do echo "  - Shell sentinel: $_rc"; anything=1; done
[ "$has_bridge" = 1 ] && { echo "  - Git Bash bridge: $HOME/.bash_profile"; anything=1; }
if [ "$PURGE" = 1 ]; then
	[ -d "$INSTALL_DIR" ] && { echo "  - Recorded install directory: $INSTALL_DIR"; anything=1; }
	[ "$volume_owned" = 1 ] && { echo "  - Managed home: $HOME_VOLUME"; anything=1; }
fi
if [ "$anything" = 0 ]; then echo "  (nothing)"; exit 0; fi

if [ "$PURGE" = 1 ] && [ "$volume_owned" = 1 ] && { [ "$HOME_VOLUME_ADOPTED" = 1 ] || [ "$HAD_STATE" = 0 ]; } && [ "$FORCE" != 1 ]; then
	echo "Error: '$HOME_VOLUME' is an explicitly adopted unlabeled volume; --force is required to purge it." >&2; exit 1
fi
if [ "$PURGE" = 1 ] && [ -d "$INSTALL_DIR" ]; then
	case "$INSTALL_DIR" in ''|/|"$HOME"|"$USER_HOME") echo "Error: unsafe recorded purge path '$INSTALL_DIR'." >&2; exit 1 ;; esac
	assert_purge_checkout
fi

if [ "$YES" != 1 ]; then
	[ -t 0 ] || { echo "Error: stdin is not a terminal; pass --yes." >&2; exit 1; }
	printf 'Proceed? [y/N]: '; read -r answer
	case "$answer" in y|Y|yes|YES|Yes) ;; *) echo "Aborted."; exit 1 ;; esac
fi
if [ "$PURGE" = 1 ] && [ -d "$WORKSPACE_DIR" ] && [ "$YES" != 1 ]; then
	_count="$(find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
	if [ "$_count" -gt 0 ]; then
		echo "Warning: recorded Workspace contains $_count item(s): $WORKSPACE_DIR"
		case "$WORKSPACE_DIR/" in "$INSTALL_DIR"/*) echo "It will be removed with the install directory." ;; *) echo "It is outside the install directory and will be preserved." ;; esac
		printf 'Continue? [y/N]: '; read -r answer
		case "$answer" in y|Y|yes|YES|Yes) ;; *) echo "Aborted."; exit 1 ;; esac
	fi
fi

# The summary and Workspace warning may leave an arbitrarily long interactive
# window. Revalidate the checkout before the first destructive operation.
[ "$PURGE" != 1 ] || assert_purge_checkout

cd /
if [ "$container_owned" = 1 ]; then
	echo "Removing managed Box..."
	rt_cmd container inspect "$CONTAINER_NAME" >/dev/null 2>&1 \
		|| { echo "Error: Box '$CONTAINER_NAME' changed after confirmation; refusing removal." >&2; exit 1; }
	_owner="$(resource_owner container "$CONTAINER_NAME")"
	if [ "$HAD_STATE" = 1 ]; then
		[ "$_owner" = "$INSTALL_ID" ] || { echo "Error: Box '$CONTAINER_NAME' changed ownership after confirmation." >&2; exit 1; }
	else
		[ -z "$_owner" ] || { echo "Error: legacy Box changed ownership after confirmation." >&2; exit 1; }
	fi
	rt_cmd rm -f "$CONTAINER_NAME" >/dev/null || { echo "Error: failed to remove $CONTAINER_NAME." >&2; exit 1; }
fi

if [ "$image_owned" = 1 ]; then
	echo "Removing recorded image references..."
	_refs=("$IMAGE_ALIAS"); [ -n "$IMAGE_REF" ] && [ "$IMAGE_REF" != "$IMAGE_ALIAS" ] && _refs+=("$IMAGE_REF")
	for _ref in "${_refs[@]}"; do
		if rt_cmd image inspect "$_ref" >/dev/null 2>&1; then
			_ref_id="$(rt_cmd image inspect -f '{{.Id}}' "$_ref")"
			if [ "$HAD_STATE" = 1 ] && [ "$_ref_id" != "$IMAGE_ID" ]; then
				echo "Error: image ref '$_ref' changed ownership during uninstall; refusing removal." >&2; exit 1
			fi
			rt_cmd rmi "$_ref" >/dev/null || {
				echo "Error: image ref '$_ref' is still in use or could not be removed." >&2; exit 1;
			}
		fi
	done
fi

rm -f "$SHELL_INIT"
for _rc in "${rc_files[@]}"; do scrub_managed_block "$_rc" '# >>> squarebox >>>' '# <<< squarebox <<<' 'shell profile'; done
[ "$has_bridge" = 1 ] && scrub_managed_block "$HOME/.bash_profile" '# >>> squarebox bashrc bridge >>>' '# <<< squarebox bashrc bridge <<<' 'Git Bash bridge'

if [ "$PURGE" = 1 ] && [ "$volume_owned" = 1 ]; then
	echo "Removing Managed home..."
	rt_cmd volume inspect "$HOME_VOLUME" >/dev/null 2>&1 \
		|| { echo "Error: Managed home '$HOME_VOLUME' changed after confirmation; refusing removal." >&2; exit 1; }
	_owner="$(resource_owner volume "$HOME_VOLUME")"
	if [ "$HAD_STATE" = 1 ] && [ "$HOME_VOLUME_ADOPTED" != 1 ]; then
		[ "$_owner" = "$INSTALL_ID" ] || { echo "Error: Managed home changed ownership after confirmation." >&2; exit 1; }
	elif [ -n "$_owner" ] && ! { [ "$HAD_STATE" = 1 ] && [ "$_owner" = "$INSTALL_ID" ]; }; then
		echo "Error: adopted Managed home changed ownership after confirmation." >&2; exit 1
	fi
	rt_cmd volume rm "$HOME_VOLUME" >/dev/null || { echo "Error: failed to remove $HOME_VOLUME; it may still be in use." >&2; exit 1; }
fi
if [ "$PURGE" = 1 ] && [ -d "$INSTALL_DIR" ]; then
	echo "Removing recorded install directory..."
	assert_purge_checkout
	if ! rm -rf -- "$INSTALL_DIR" 2>/dev/null; then
		echo "Error: permission denied removing $INSTALL_DIR; no privilege escalation was attempted." >&2
		exit 1
	fi
fi

echo "Uninstall complete."
if [ "$PURGE" != 1 ]; then
	echo "Preserved install identity and Workspace at $INSTALL_DIR."
	[ "$volume_owned" = 1 ] && echo "Preserved Managed home $HOME_VOLUME."
elif [[ "$WORKSPACE_DIR/" != "$INSTALL_DIR/"* ]] && [ -d "$WORKSPACE_DIR" ]; then
	echo "Preserved external Workspace $WORKSPACE_DIR."
fi
echo "Start a new shell to drop functions already loaded in this session."

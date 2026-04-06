#!/usr/bin/env bash
# tool-lib.sh — shared library for SquareBox tool management.
# Source this file; do not execute directly.
#
# Provides:
#   sb_get <tool> <field>           Read a field from tools.yaml
#   sb_list_tools                   List all tool names
#   sb_list_group <group>           List tools in a group (dockerfile/setup)
#   sb_artifact <tool> <ver> [arch] Resolve artifact filename
#   sb_url <tool> <ver> [arch]      Full GitHub release download URL
#   sb_install <tool> <ver>         Download, verify, extract, and install
#
# Override sb_verify(file, artifact_name) before calling sb_install to
# plug in your own checksum verification. Default is a no-op.
#
# Set SB_TOOLS_YAML before sourcing to override the tools.yaml path.

# ── tools.yaml location ──────────────────────────────────────────────

if [ -z "${SB_TOOLS_YAML:-}" ]; then
	SB_TOOLS_YAML="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools.yaml"
fi

# ── Architecture detection (performed once) ───────────────────────────

_sb_dpkg=$(dpkg --print-architecture 2>/dev/null || true)
_sb_uname=$(uname -m 2>/dev/null || true)

if [ "$_sb_uname" = "aarch64" ] || [ "$_sb_dpkg" = "arm64" ]; then
	SB_DPKG_ARCH=arm64;  SB_ZARCH=aarch64; SB_LARCH=arm64
	SB_GOARCH=arm64;     SB_OCARCH=arm64;  SB_MARCH=-arm64
else
	SB_DPKG_ARCH=amd64;  SB_ZARCH=x86_64;  SB_LARCH=x86_64
	SB_GOARCH=amd64;     SB_OCARCH=x64;    SB_MARCH=64
fi
unset _sb_dpkg _sb_uname

# ── YAML reader (awk-based, no yq dependency) ────────────────────────

sb_get() {
	local tool="$1" field="$2"
	awk -v tool="  $tool:" -v field="    $field:" '
		$0 == tool { found=1; next }
		found && /^  [a-zA-Z_-]/ { exit }
		found && index($0, field) == 1 {
			val = substr($0, length(field) + 1)
			gsub(/^ +| +$/, "", val)
			gsub(/^["'"'"']|["'"'"']$/, "", val)
			print val
			exit
		}
	' "$SB_TOOLS_YAML"
}

sb_list_tools() {
	awk '/^  [a-z].*:$/ { sub(/:$/, ""); gsub(/^ +/, ""); print }' "$SB_TOOLS_YAML"
}

sb_list_group() {
	local group="$1" tool
	for tool in $(sb_list_tools); do
		if [ "$(sb_get "$tool" group)" = "$group" ]; then echo "$tool"; fi
	done
}

# ── Arch token resolution ────────────────────────────────────────────

_sb_resolve_arch() {
	local arch="$1" str="$2"
	if [ "$arch" = "arm64" ]; then
		str="${str//\{dpkg_arch\}/arm64}";  str="${str//\{zarch\}/aarch64}"
		str="${str//\{larch\}/arm64}";      str="${str//\{goarch\}/arm64}"
		str="${str//\{ocarch\}/arm64}";     str="${str//\{march\}/-arm64}"
	else
		str="${str//\{dpkg_arch\}/amd64}";  str="${str//\{zarch\}/x86_64}"
		str="${str//\{larch\}/x86_64}";     str="${str//\{goarch\}/amd64}"
		str="${str//\{ocarch\}/x64}";       str="${str//\{march\}/64}"
	fi
	echo "$str"
}

# ── Artifact + URL resolution ─────────────────────────────────────────

sb_artifact() {
	local tool="$1" version="$2" arch="${3:-$SB_DPKG_ARCH}"
	local pattern
	pattern=$(sb_get "$tool" artifact)
	pattern="${pattern//\{version\}/$version}"
	# {asset_version} — caller sets SB_ASSET_VERSION for tools like edit
	[[ "$pattern" == *"{asset_version}"* ]] && \
		pattern="${pattern//\{asset_version\}/${SB_ASSET_VERSION:-$version}}"
	_sb_resolve_arch "$arch" "$pattern"
}

sb_url() {
	local tool="$1" version="$2" arch="${3:-$SB_DPKG_ARCH}"
	local repo prefix tag artifact
	repo=$(sb_get "$tool" repo)
	prefix=$(sb_get "$tool" version_prefix)
	tag="${prefix}${version}"
	artifact=$(sb_artifact "$tool" "$version" "$arch")
	echo "https://github.com/${repo}/releases/download/${tag}/${artifact}"
}

# ── Verification hook (override before calling sb_install) ────────────

sb_verify() { :; }

# ── Install pipeline ─────────────────────────────────────────────────

sb_install() {
	local tool="$1" version="$2"
	local method dest_type artifact url binaries find_bin
	method=$(sb_get "$tool" method)
	dest_type=$(sb_get "$tool" dest)
	artifact=$(sb_artifact "$tool" "$version")
	url=$(sb_url "$tool" "$version")
	binaries=$(sb_get "$tool" binaries)
	find_bin=$(sb_get "$tool" find_binary)

	local dest_dir
	if [ "$dest_type" = "system" ]; then
		dest_dir="/usr/local/bin"
	else
		dest_dir="$HOME/.local/bin"
		mkdir -p "$dest_dir"
	fi

	local _sb_tmp
	_sb_tmp=$(mktemp -d)

	case "$method" in
		deb)
			curl -fsSLo "$_sb_tmp/pkg.deb" "$url"
			sb_verify "$_sb_tmp/pkg.deb" "$artifact"
			if [ "$(id -u)" != "0" ]; then sudo dpkg -i "$_sb_tmp/pkg.deb"
			else dpkg -i "$_sb_tmp/pkg.deb"; fi
			;;
		binary)
			local bname="${binaries%%,*}"
			curl -fsSLo "$_sb_tmp/$bname" "$url"
			sb_verify "$_sb_tmp/$bname" "$artifact"
			_sb_do_install "$_sb_tmp/$bname" "$dest_dir/$bname" "$dest_type"
			;;
		tar.gz|tar.xz)
			local flags="xzf"
			[ "$method" = "tar.xz" ] && flags="xJf"
			curl -fsSLo "$_sb_tmp/archive" "$url"
			sb_verify "$_sb_tmp/archive" "$artifact"
			_sb_extract_tar "$tool" "$version" "$_sb_tmp" "$dest_dir" "$dest_type" "$flags" "$_sb_tmp/archive"
			;;
		tar.zst)
			curl -fsSLo "$_sb_tmp/archive.tar.zst" "$url"
			sb_verify "$_sb_tmp/archive.tar.zst" "$artifact"
			zstd -d "$_sb_tmp/archive.tar.zst" -o "$_sb_tmp/archive.tar"
			_sb_extract_tar "$tool" "$version" "$_sb_tmp" "$dest_dir" "$dest_type" "xf" "$_sb_tmp/archive.tar"
			;;
		zip)
			curl -fsSLo "$_sb_tmp/archive.zip" "$url"
			sb_verify "$_sb_tmp/archive.zip" "$artifact"
			unzip -q "$_sb_tmp/archive.zip" -d "$_sb_tmp"
			local subdir
			subdir=$(_sb_resolve_arch "$SB_DPKG_ARCH" "$(sb_get "$tool" zip_subdir)")
			local bin
			for bin in $(echo "$binaries" | tr ',' ' '); do
				_sb_do_install "$_sb_tmp/${subdir:+$subdir/}$bin" "$dest_dir/$bin" "$dest_type"
			done
			;;
		tar.gz-tree)
			curl -fsSLo "$_sb_tmp/archive.tar.gz" "$url"
			sb_verify "$_sb_tmp/archive.tar.gz" "$artifact"
			tar xzf "$_sb_tmp/archive.tar.gz" -C "$_sb_tmp"
			local tree_name tree_dest symlink
			tree_name=$(_sb_resolve_arch "$SB_DPKG_ARCH" "$(sb_get "$tool" tree_name)")
			tree_dest=$(sb_get "$tool" tree_dest)
			tree_dest="${tree_dest/#\~/$HOME}"
			rm -rf "$tree_dest"
			mv "$_sb_tmp/$tree_name" "$tree_dest"
			symlink=$(sb_get "$tool" symlink)
			if [ -n "$symlink" ]; then
				symlink="${symlink/#\~/$HOME}"
				mkdir -p "$dest_dir"
				ln -sf "$symlink" "$dest_dir/${binaries%%,*}"
			fi
			;;
	esac

	# Post-install hooks
	local post
	post=$(sb_get "$tool" post_install)
	case "${post:-}" in
		helix_runtime)
			local hdir
			hdir=$(find "$_sb_tmp" -type d -name "helix-*-linux" | head -1)
			if [ -n "$hdir" ] && [ -d "$hdir/runtime" ]; then
				mkdir -p "$HOME/.config/helix"
				rm -rf "$HOME/.config/helix/runtime"
				mv "$hdir/runtime" "$HOME/.config/helix/runtime"
			fi
			;;
	esac

	rm -rf "$_sb_tmp"
}

_sb_extract_tar() {
	local tool="$1" version="$2" tmp="$3" dest_dir="$4" dest_type="$5" flags="$6" archive="$7"
	local strip find_bin binaries tar_extract
	strip=$(sb_get "$tool" tar_strip)
	find_bin=$(sb_get "$tool" find_binary)
	binaries=$(sb_get "$tool" binaries)
	tar_extract=$(sb_get "$tool" tar_extract)

	local -a args=("$flags" "$archive" "-C" "$tmp")
	[ -n "$strip" ] && args+=("--strip-components=$strip")
	[ -n "$tar_extract" ] && args+=("$tar_extract")
	tar "${args[@]}"

	local bin
	for bin in $(echo "$binaries" | tr ',' ' '); do
		local src
		if [ "$find_bin" = "true" ]; then
			src=$(find "$tmp" -name "$bin" -type f -executable | head -1)
			[ -n "$src" ] || { echo "Error: $bin not found in archive" >&2; rm -rf "$tmp"; return 1; }
		else
			src="$tmp/$bin"
		fi
		_sb_do_install "$src" "$dest_dir/$bin" "$dest_type"
	done
}

_sb_do_install() {
	local src="$1" dest="$2" dest_type="$3"
	if [ "$dest_type" = "system" ] && [ "$(id -u)" != "0" ]; then
		sudo install "$src" "$dest"
	else
		install "$src" "$dest"
	fi
}

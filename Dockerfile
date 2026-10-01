# Gum v0.17.0's release binaries embed vulnerable Go 1.25.1. Upstream has not
# published a newer stable release, so copy the fixed development binary from
# its exact multi-architecture OCI manifest. The build below asserts the
# expected v0.17.1-devel commit identity before the binary enters the Box.
ARG GUM_IMAGE=ghcr.io/charmbracelet/gum@sha256:426c1e40739f11083e06d58ffaac910289eeace709a3d9bddcb8d4566140c93c
FROM ${GUM_IMAGE} AS gum-source

FROM ubuntu:26.04

# 1. Base Packages & Rust CLI Tools (consolidated, slimmed)

# The Ubuntu base image strips /usr/share/doc/* (dpkg.cfg.d/excludes), but fzf
# ships its shell keybindings ONLY under /usr/share/doc/fzf/examples/. Re-include
# that one file (must be set BEFORE fzf is unpacked below) so the Ctrl+R/Ctrl+T/
# Alt+C bindings sourced from bashrc actually exist. The ** completion lives under
# /usr/share/bash-completion/ and is unaffected.
RUN printf 'path-include=/usr/share/doc/fzf/examples/key-bindings.bash\n' \
		> /etc/dpkg/dpkg.cfg.d/zz-squarebox-fzf \
	&& apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	git \
	# openssh-client: git only Recommends it, so --no-install-recommends drops it.
	# Needed for SSH git remotes and the agent-forwarding mounts (SSH_AUTH_SOCK,
	# ~/.ssh/config, ~/.ssh/known_hosts) set up at run time.
	openssh-client \
	curl \
	unzip \
	xz-utils \
	jq \
	less \
	sudo \
	ca-certificates \
	fd-find \
	ripgrep \
	bat \
	fzf \
	bash-completion \
	nano \
	zstd \
	zoxide \
	# bubblewrap: OpenAI Codex CLI's Linux sandbox uses the first bwrap on PATH
	# and warns at startup when only its bundled fallback helper is available.
	bubblewrap \
	toilet \
	toilet-fonts \
	libicu-dev \
	locales \
	# Runtime package installs happen with /etc/localtime bind-mounted read-only.
	# Configure tzdata in the image, then setup.sh holds it before Box-tier apt.
	tzdata \
	# Runtime deps for mise-managed SDKs:
	#   gpg        — mise verifies upstream signatures (Node, etc.)
	#   libatomic1 — required by official Node Linux builds
	gpg \
	libatomic1 \
	&& sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
	&& locale-gen \
	&& rm -rf /var/lib/apt/lists/* \
	&& ln -s $(which fdfind) /usr/local/bin/fd \
	&& ln -s $(which batcat) /usr/local/bin/bat

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 2. External APT Repos (GitHub CLI, Eza) + Binary Tools

# Pinned tool versions — update via: scripts/update-versions.sh
ARG DELTA_VERSION=0.19.2
ARG YQ_VERSION=4.53.3
ARG XH_VERSION=0.26.2
ARG STARSHIP_VERSION=1.26.0
ARG GLOW_VERSION=2.1.2
ARG JUST_VERSION=1.57.0
ARG DIFFTASTIC_VERSION=0.71.0
ARG MISE_VERSION=2026.7.18
ARG GUM_EXPECTED_VERSION=v0.17.1-devel
ARG GUM_EXPECTED_COMMIT=591ded2

# Validate version ARGs are non-empty
RUN test -n "$DELTA_VERSION"       || { echo "Error: DELTA_VERSION is empty" >&2; exit 1; } \
 && test -n "$YQ_VERSION"          || { echo "Error: YQ_VERSION is empty" >&2; exit 1; } \
 && test -n "$XH_VERSION"          || { echo "Error: XH_VERSION is empty" >&2; exit 1; } \
 && test -n "$STARSHIP_VERSION"    || { echo "Error: STARSHIP_VERSION is empty" >&2; exit 1; } \
 && test -n "$GLOW_VERSION"        || { echo "Error: GLOW_VERSION is empty" >&2; exit 1; } \
 && test -n "$JUST_VERSION"        || { echo "Error: JUST_VERSION is empty" >&2; exit 1; } \
 && test -n "$DIFFTASTIC_VERSION"  || { echo "Error: DIFFTASTIC_VERSION is empty" >&2; exit 1; } \
 && test -n "$MISE_VERSION"        || { echo "Error: MISE_VERSION is empty" >&2; exit 1; } \
 && test -n "$GUM_EXPECTED_VERSION" || { echo "Error: GUM_EXPECTED_VERSION is empty" >&2; exit 1; } \
 && test -n "$GUM_EXPECTED_COMMIT" || { echo "Error: GUM_EXPECTED_COMMIT is empty" >&2; exit 1; }

# Checksum verification infrastructure
COPY checksums.txt /tmp/checksums.txt
COPY scripts/verify-checksum.sh /usr/local/bin/verify-checksum
COPY scripts/lib/tools.yaml /tmp/tools.yaml
COPY scripts/lib/tool-lib.sh /tmp/tool-lib.sh
RUN chmod +x /usr/local/bin/verify-checksum

# tool-lib.sh uses bash parameter substitution
SHELL ["/bin/bash", "-c"]

# 2a. External APT repos (GitHub CLI, Eza) — needs gnupg, stays combined
#
# Signing keys are pinned by full primary-key fingerprint. Each downloaded
# keyring must contain exactly the expected set of primary keys (subkeys are
# ignored) before it is trusted as an APT signer; any difference fails the
# build. To rotate, verify the new fingerprint out-of-band (see SECURITY.md)
# and update the ARG. Values are space-separated, upper-case, 40-hex.
#   GitHub CLI: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
#   Eza (deb.gierens.de): key file pinned to an immutable eza commit
ARG GH_CLI_KEY_FINGERPRINTS="2C6106201985B60E6C7AC87323F3D4EA75716059 7F38BBB59D064DBCB3D84D725612B36462313325"
ARG EZA_KEY_FINGERPRINTS="1548BC8A4B4D2688F9B0DAF7EC29E2090CE3FD43"
ARG EZA_KEY_URL=https://raw.githubusercontent.com/eza-community/eza/1cff499fb218f2a133aafa01824ddab090f4389e/deb.asc
RUN set -euo pipefail \
	&& mkdir -p -m 755 /etc/apt/keyrings \
	&& ARCH=$(dpkg --print-architecture) \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gnupg \
	&& KEYDIR=$(mktemp -d) \
	&& verify_apt_key() { \
		local name=$1 file=$2 expected=$3 actual want; \
		want=$(printf '%s\n' $expected | tr '[:lower:]' '[:upper:]' | sort -u | paste -sd' ' -); \
		[ -n "$want" ] || { echo "Error: no expected fingerprint configured for ${name} APT key" >&2; return 1; }; \
		actual=$(GNUPGHOME="$KEYDIR/gnupg" gpg --batch --quiet --show-keys --with-colons "$file" 2>/dev/null \
			| awk -F: '$1 == "pub" { want_fpr = 1; next } want_fpr && $1 == "fpr" { print $10; want_fpr = 0 }' \
			| sort -u | paste -sd' ' -); \
		if [ "$actual" != "$want" ]; then \
			echo "Error: ${name} APT signing key fingerprint mismatch" >&2; \
			echo "  expected: ${want}" >&2; \
			echo "  actual:   ${actual:-<none>}" >&2; \
			return 1; \
		fi; \
		echo "Verified ${name} APT signing key: ${actual}"; \
	} \
	&& mkdir -m 700 "$KEYDIR/gnupg" \
	# GitHub CLI
	&& curl -fsSL -o "$KEYDIR/githubcli.gpg" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& verify_apt_key "GitHub CLI" "$KEYDIR/githubcli.gpg" "$GH_CLI_KEY_FINGERPRINTS" \
	&& install -m 644 "$KEYDIR/githubcli.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	# Eza
	&& curl -fsSL -o "$KEYDIR/eza.asc" "$EZA_KEY_URL" \
	&& verify_apt_key "Eza" "$KEYDIR/eza.asc" "$EZA_KEY_FINGERPRINTS" \
	&& GNUPGHOME="$KEYDIR/gnupg" gpg --batch --dearmor -o /etc/apt/keyrings/gierens.gpg < "$KEYDIR/eza.asc" \
	&& chmod 644 /etc/apt/keyrings/gierens.gpg \
	&& echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list \
	&& rm -rf "$KEYDIR" \
	# Install from repos
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gh eza \
	# gh and eza are image-tier tools. Their repositories are build inputs, not
	# runtime package sources: leaving them configured makes an unrelated outage
	# prevent Box-tier installs such as tmux, zsh, and fish.
	&& rm -f /etc/apt/sources.list.d/github-cli.list /etc/apt/sources.list.d/gierens.list \
		/etc/apt/keyrings/githubcli-archive-keyring.gpg /etc/apt/keyrings/gierens.gpg \
	# Note: gnupg is kept (also installed in layer 1 as `gpg`) — mise needs it
	# at runtime to verify Node release signatures.
	&& rm -rf /var/lib/apt/lists/*

# Build-time tool install helper: sources library + wires up checksum verification
RUN echo '. /tmp/tool-lib.sh; sb_verify() { verify-checksum "$1" "$2"; }' > /tmp/sb-init.sh

# 3. Binary tool installs (one per layer for cache granularity)
RUN . /tmp/sb-init.sh && sb_install delta "$DELTA_VERSION"
RUN . /tmp/sb-init.sh && sb_install yq "$YQ_VERSION"
RUN . /tmp/sb-init.sh && sb_install xh "$XH_VERSION"
RUN . /tmp/sb-init.sh && sb_install glow "$GLOW_VERSION"
COPY --from=gum-source /usr/local/bin/gum /usr/local/bin/gum
RUN test "$(gum --version)" = "gum version ${GUM_EXPECTED_VERSION} (${GUM_EXPECTED_COMMIT})"
RUN . /tmp/sb-init.sh && sb_install starship "$STARSHIP_VERSION"
RUN . /tmp/sb-init.sh && sb_install just "$JUST_VERSION"
RUN . /tmp/sb-init.sh && sb_install difftastic "$DIFFTASTIC_VERSION"
RUN . /tmp/sb-init.sh && sb_install mise "$MISE_VERSION"

# Clean up build-time files
RUN rm -f /tmp/checksums.txt /tmp/tools.yaml /tmp/tool-lib.sh /tmp/sb-init.sh

# 4. User Setup

# Runtime authority is intentionally split: apt/dpkg/chown support Box setup;
# install stages an image-tier binary; mv may atomically promote only a
# .<tool>.squarebox.* sibling into /usr/local/bin; rm may clean only that stage.
RUN userdel -r ubuntu 2>/dev/null || true \
	&& useradd -m -s /bin/bash -u 1000 dev \
	&& printf '%s\n' \
		'Defaults:dev env_keep += "DEBIAN_FRONTEND"' \
		'dev ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt-mark, /usr/bin/dpkg, /usr/bin/chown, /usr/bin/install' \
		'dev ALL=(root) NOPASSWD: /usr/bin/mv ^-fT -- /usr/local/bin/\.[A-Za-z0-9._+-]+\.squarebox\.[0-9]+\.[0-9]+ /usr/local/bin/[A-Za-z0-9._+-]+$' \
		'dev ALL=(root) NOPASSWD: /usr/bin/rm ^-f -- /usr/local/bin/\.[A-Za-z0-9._+-]+\.squarebox\.[0-9]+\.[0-9]+$' \
		> /etc/sudoers.d/dev \
	&& chmod 0440 /etc/sudoers.d/dev \
	&& visudo -cf /etc/sudoers.d/dev \
	&& mkdir -p /home/dev/.claude /home/dev/.config /home/dev/.ssh \
	&& chown -R dev:dev /home/dev

# 5. Config Files

RUN printf '[core]\n\tpager = delta\n[interactive]\n\tdiffFilter = delta --color-only\n[delta]\n\tnavigate = true\n\tdark = true\n[merge]\n\tconflictstyle = zdiff3\n' > /etc/gitconfig

# 6. Setup script
#
# setup.sh and motd.sh live under /usr/local/lib/squarebox/ rather than
# /home/dev/ so they stay image-managed. /home/dev/ is backed by the
# squarebox-home named volume, which Docker only seeds from the image when
# the volume is first created — anything we put there would go stale after
# a `sqrbx-rebuild` against an existing volume.

COPY --chown=dev:dev starship.toml /home/dev/.config/starship.toml

COPY motd.sh /usr/local/lib/squarebox/motd.sh
COPY setup.sh /usr/local/lib/squarebox/setup.sh
COPY scripts/squarebox-update.sh /usr/local/bin/sqrbx-update
COPY scripts/squarebox-setup.sh /usr/local/bin/sqrbx-setup
COPY scripts/squarebox-help.sh /usr/local/bin/sqrbx-help
COPY scripts/squarebox-entrypoint.sh /usr/local/bin/squarebox-entrypoint
COPY scripts/squarebox-refresh-dotfiles.sh /usr/local/lib/squarebox/refresh-dotfiles.sh
COPY scripts/lib/tools.yaml /usr/local/lib/squarebox/tools.yaml
COPY scripts/lib/tool-lib.sh /usr/local/lib/squarebox/tool-lib.sh
# This is the Candidate's vetted manifest. Runtime image-tier updates must
# match it; advancing the manifest requires publishing a newer Candidate.
COPY checksums.txt /usr/local/lib/squarebox/checksums.txt

# Image-managed dotfiles also live under a non-volume path so the entrypoint can
# refresh them into the squarebox-home volume on every start. Without this the
# volume shadows the /home/dev image layer and dotfile updates never reach
# upgraded containers (issue #89). The /home/dev copies below still seed a fresh
# volume; these are the source of truth the refresh re-applies thereafter.
COPY dotfiles/bashrc /usr/local/lib/squarebox/dotfiles/bashrc
COPY starship.toml /usr/local/lib/squarebox/dotfiles/starship.toml

RUN chmod +x /usr/local/lib/squarebox/setup.sh \
	/usr/local/lib/squarebox/motd.sh \
	/usr/local/lib/squarebox/refresh-dotfiles.sh \
	/usr/local/bin/sqrbx-update \
	/usr/local/bin/sqrbx-setup \
	/usr/local/bin/sqrbx-help \
	/usr/local/bin/squarebox-entrypoint

RUN chown -R dev:dev /home/dev/.config /home/dev/.claude \
	&& mkdir -p /workspace && chown dev:dev /workspace

# squarebox release version, baked at build time so the MOTD can surface it.
# Defaults to "dev" for local/untagged builds; install.sh passes `git describe`
# and the GHCR publish workflow passes the release tag. Declared this late so a
# version bump only invalidates the trailing layers, not the whole tool stack.
ARG SQUAREBOX_VERSION=dev
RUN printf '%s\n' "$SQUAREBOX_VERSION" > /usr/local/lib/squarebox/VERSION
LABEL org.opencontainers.image.version="$SQUAREBOX_VERSION"

# The container starts as root so the entrypoint can honour PUID/PGID, then
# drops to `dev` via setpriv. With the default 1000:1000 this is a no-op and
# the running process is `dev` — identical to a plain `USER dev` image. PUID/
# PGID are declared here so docker-compose / Unraid template UIs surface them.
ENV HOME=/home/dev
# Keep child processes launched via `docker exec` on the same interactive shell
# path as the image's default CMD, even when the runtime does not export SHELL.
ENV SHELL=/bin/bash
ENV SQUAREBOX=1
ENV PUID=1000
ENV PGID=1000

# 7. Shell Config
# The .bashrc lives in dotfiles/ on the host so install.sh can bind-mount it
# into the container — keeping it in sync with the repo while shell history
# and per-user state stay in the squarebox-home named volume. The COPY here
# seeds a fresh volume; the desktop install path then bind-mounts the host copy,
# and the pull/compose path keeps it current via the entrypoint dotfile refresh
# (issue #89) since there is no bind-mount in that path.

COPY --chown=dev:dev dotfiles/bashrc /home/dev/.bashrc

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/squarebox-entrypoint"]
CMD ["/bin/bash"]

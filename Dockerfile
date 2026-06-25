FROM ubuntu:24.04

# 1. Base Packages & Rust CLI Tools (consolidated, slimmed)

RUN apt-get update && apt-get install -y --no-install-recommends \
	git \
	curl \
	unzip \
	jq \
	less \
	sudo \
	ca-certificates \
	fd-find \
	ripgrep \
	bat \
	fzf \
	nano \
	zstd \
	zoxide \
	toilet \
	toilet-fonts \
	libicu-dev \
	locales \
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
ARG YQ_VERSION=4.53.2
ARG XH_VERSION=0.25.3
ARG STARSHIP_VERSION=1.24.2
ARG GLOW_VERSION=2.1.2
ARG GUM_VERSION=0.17.0
ARG JUST_VERSION=1.49.0
ARG DIFFTASTIC_VERSION=0.68.0
ARG MISE_VERSION=2026.5.4

# Validate version ARGs are non-empty
RUN test -n "$DELTA_VERSION"       || { echo "Error: DELTA_VERSION is empty" >&2; exit 1; } \
 && test -n "$YQ_VERSION"          || { echo "Error: YQ_VERSION is empty" >&2; exit 1; } \
 && test -n "$XH_VERSION"          || { echo "Error: XH_VERSION is empty" >&2; exit 1; } \
 && test -n "$STARSHIP_VERSION"    || { echo "Error: STARSHIP_VERSION is empty" >&2; exit 1; } \
 && test -n "$GLOW_VERSION"        || { echo "Error: GLOW_VERSION is empty" >&2; exit 1; } \
 && test -n "$GUM_VERSION"         || { echo "Error: GUM_VERSION is empty" >&2; exit 1; } \
 && test -n "$JUST_VERSION"        || { echo "Error: JUST_VERSION is empty" >&2; exit 1; } \
 && test -n "$DIFFTASTIC_VERSION"  || { echo "Error: DIFFTASTIC_VERSION is empty" >&2; exit 1; } \
 && test -n "$MISE_VERSION"        || { echo "Error: MISE_VERSION is empty" >&2; exit 1; }

# Checksum verification infrastructure
COPY checksums.txt /tmp/checksums.txt
COPY scripts/verify-checksum.sh /usr/local/bin/verify-checksum
COPY scripts/lib/tools.yaml /tmp/tools.yaml
COPY scripts/lib/tool-lib.sh /tmp/tool-lib.sh
RUN chmod +x /usr/local/bin/verify-checksum

# tool-lib.sh uses bash parameter substitution
SHELL ["/bin/bash", "-c"]

# 2a. External APT repos (GitHub CLI, Eza) — needs gnupg, stays combined
RUN mkdir -p -m 755 /etc/apt/keyrings \
	&& ARCH=$(dpkg --print-architecture) \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gnupg \
	# GitHub CLI
	&& curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	# Eza
	&& curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
	&& echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list \
	# Install from repos
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gh eza \
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
RUN . /tmp/sb-init.sh && sb_install gum "$GUM_VERSION"
RUN . /tmp/sb-init.sh && sb_install starship "$STARSHIP_VERSION"
RUN . /tmp/sb-init.sh && sb_install just "$JUST_VERSION"
RUN . /tmp/sb-init.sh && sb_install difftastic "$DIFFTASTIC_VERSION"
RUN . /tmp/sb-init.sh && sb_install mise "$MISE_VERSION"

# Clean up build-time files
RUN rm -f /tmp/checksums.txt /tmp/tools.yaml /tmp/tool-lib.sh /tmp/sb-init.sh

# 4. User Setup

RUN userdel -r ubuntu 2>/dev/null || true \
	&& useradd -m -s /bin/bash -u 1000 dev \
	&& echo 'dev ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/dpkg, /usr/bin/chown, /usr/bin/install' > /etc/sudoers.d/dev \
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
COPY scripts/sqrbx-learn /usr/local/bin/sqrbx-learn
COPY scripts/squarebox-entrypoint.sh /usr/local/bin/squarebox-entrypoint
COPY scripts/lib/tools.yaml /usr/local/lib/squarebox/tools.yaml
COPY scripts/lib/tool-lib.sh /usr/local/lib/squarebox/tool-lib.sh
RUN chmod +x /usr/local/lib/squarebox/setup.sh \
	/usr/local/lib/squarebox/motd.sh \
	/usr/local/bin/sqrbx-update \
	/usr/local/bin/sqrbx-setup \
	/usr/local/bin/sqrbx-learn \
	/usr/local/bin/squarebox-entrypoint

RUN chown -R dev:dev /home/dev/.config /home/dev/.claude \
	&& mkdir -p /workspace && chown dev:dev /workspace

# The container starts as root so the entrypoint can honour PUID/PGID, then
# drops to `dev` via setpriv. With the default 1000:1000 this is a no-op and
# the running process is `dev` — identical to a plain `USER dev` image. PUID/
# PGID are declared here so docker-compose / Unraid template UIs surface them.
ENV HOME=/home/dev
ENV SQUAREBOX=1
ENV PUID=1000
ENV PGID=1000

# 7. Shell Config
# The .bashrc lives in dotfiles/ on the host so install.sh can bind-mount it
# into the container — keeping it in sync with the repo while shell history
# and per-user state stay in the squarebox-home named volume. The COPY here
# is what seeds a fresh volume; subsequent runs see the bind-mounted version.

COPY --chown=dev:dev dotfiles/bashrc /home/dev/.bashrc

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/squarebox-entrypoint"]
CMD ["/bin/bash"]

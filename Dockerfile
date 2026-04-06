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
	&& rm -rf /var/lib/apt/lists/* \
	&& ln -s $(which fdfind) /usr/local/bin/fd \
	&& ln -s $(which batcat) /usr/local/bin/bat

# 2. External APT Repos (GitHub CLI, Eza) + Binary Tools

# Pinned tool versions — update via: scripts/update-versions.sh
ARG DELTA_VERSION=0.19.2
ARG YQ_VERSION=4.52.5
ARG LAZYGIT_VERSION=0.60.0
ARG XH_VERSION=0.25.3
ARG YAZI_VERSION=26.1.22
ARG STARSHIP_VERSION=1.24.2
ARG GH_DASH_VERSION=4.23.2
ARG GLOW_VERSION=2.1.1
ARG GUM_VERSION=0.17.0

# Validate version ARGs are non-empty
RUN test -n "$DELTA_VERSION"    || { echo "Error: DELTA_VERSION is empty" >&2; exit 1; } \
 && test -n "$YQ_VERSION"       || { echo "Error: YQ_VERSION is empty" >&2; exit 1; } \
 && test -n "$LAZYGIT_VERSION"  || { echo "Error: LAZYGIT_VERSION is empty" >&2; exit 1; } \
 && test -n "$XH_VERSION"       || { echo "Error: XH_VERSION is empty" >&2; exit 1; } \
 && test -n "$YAZI_VERSION"     || { echo "Error: YAZI_VERSION is empty" >&2; exit 1; } \
 && test -n "$STARSHIP_VERSION" || { echo "Error: STARSHIP_VERSION is empty" >&2; exit 1; } \
 && test -n "$GH_DASH_VERSION"  || { echo "Error: GH_DASH_VERSION is empty" >&2; exit 1; } \
 && test -n "$GLOW_VERSION"     || { echo "Error: GLOW_VERSION is empty" >&2; exit 1; } \
 && test -n "$GUM_VERSION"      || { echo "Error: GUM_VERSION is empty" >&2; exit 1; }

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
	# Purge build-only dependency
	&& apt-get purge -y --auto-remove gnupg \
	&& rm -rf /var/lib/apt/lists/*

# Build-time tool install helper: sources library + wires up checksum verification
RUN echo '. /tmp/tool-lib.sh; sb_verify() { verify-checksum "$1" "$2"; }' > /tmp/sb-init.sh

# 3. Binary tool installs (one per layer for cache granularity)
RUN . /tmp/sb-init.sh && sb_install delta "$DELTA_VERSION"
RUN . /tmp/sb-init.sh && sb_install yq "$YQ_VERSION"
RUN . /tmp/sb-init.sh && sb_install lazygit "$LAZYGIT_VERSION"
RUN . /tmp/sb-init.sh && sb_install gh-dash "$GH_DASH_VERSION"
RUN . /tmp/sb-init.sh && sb_install xh "$XH_VERSION"
RUN . /tmp/sb-init.sh && sb_install yazi "$YAZI_VERSION"
RUN . /tmp/sb-init.sh && sb_install glow "$GLOW_VERSION"
RUN . /tmp/sb-init.sh && sb_install gum "$GUM_VERSION"
RUN . /tmp/sb-init.sh && sb_install starship "$STARSHIP_VERSION"

# Clean up build-time files
RUN rm -f /tmp/checksums.txt /tmp/tools.yaml /tmp/tool-lib.sh /tmp/sb-init.sh

# 4. User Setup

RUN userdel -r ubuntu 2>/dev/null || true \
	&& useradd -m -s /bin/bash -u 1000 dev \
	&& echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
	&& mkdir -p /home/dev/.claude /home/dev/.config/lazygit \
	&& chown -R dev:dev /home/dev

# 5. Config Files

RUN printf '[core]\n\tpager = delta\n[interactive]\n\tdiffFilter = delta --color-only\n[delta]\n\tnavigate = true\n\tdark = true\n[merge]\n\tconflictstyle = zdiff3\n' > /etc/gitconfig \
	&& printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > /home/dev/.config/lazygit/config.yml

# 6. Setup script

COPY --chown=dev:dev motd.sh /home/dev/motd.sh
RUN chmod +x /home/dev/motd.sh

COPY --chown=dev:dev setup.sh /home/dev/setup.sh
COPY --chown=dev:dev setup-checksums.txt /home/dev/setup-checksums.txt
COPY --chown=dev:dev starship.toml /home/dev/.config/starship.toml

COPY scripts/squarebox-update.sh /usr/local/bin/sqrbx-update
COPY scripts/lib/tools.yaml /usr/local/lib/squarebox/tools.yaml
COPY scripts/lib/tool-lib.sh /usr/local/lib/squarebox/tool-lib.sh
RUN chmod +x /usr/local/bin/sqrbx-update

RUN chown -R dev:dev /home/dev/.config /home/dev/.claude \
	&& mkdir -p /workspace && chown dev:dev /workspace

USER dev

ENV HOME=/home/dev
ENV SQUAREBOX=1

# 7. Shell Config

RUN cat <<'EOFRC' >> ~/.bashrc
eval "$(starship init bash)"
eval "$(zoxide init bash --cmd cd)"
alias ls='eza --icons'
alias ll='eza -la --icons'
alias lsa='ls -a'
alias lt='eza --tree --level=2 --long --icons --git'
alias lta='lt -a'
alias cat='bat --paging=never'
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
alias eff='$EDITOR "$(ff)"'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
export EDITOR='nano'
[ -f ~/.squarebox-ai-aliases ] && source ~/.squarebox-ai-aliases
[ -f ~/.squarebox-editor-aliases ] && source ~/.squarebox-editor-aliases
[ -f ~/.squarebox-sdk-paths ] && source ~/.squarebox-sdk-paths
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
alias lg='lazygit'
export PATH="$HOME/.local/bin:$PATH"
# First-run setup
if [ ! -f ~/.squarebox-setup-done ]; then
	if [ -n "${DEVCONTAINER:-}" ]; then
		touch ~/.squarebox-setup-done
	else
		~/setup.sh && touch ~/.squarebox-setup-done
	fi
fi
EOFRC

# Display MOTD on interactive shell login
RUN echo '~/motd.sh' >> ~/.bashrc

WORKDIR /workspace
CMD ["/bin/bash"]

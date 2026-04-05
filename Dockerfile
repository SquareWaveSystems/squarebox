FROM ubuntu:24.04

# 1. Base Packages & Rust CLI Tools (consolidated, slimmed)

RUN apt-get update && apt-get install -y --no-install-recommends \
	git \
	curl \
	unzip \
	jq \
	less \
	ca-certificates \
	fd-find \
	ripgrep \
	bat \
	fzf \
	nano \
	zstd \
	zoxide \
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

# Checksum verification infrastructure
COPY checksums.txt /tmp/checksums.txt
COPY scripts/verify-checksum.sh /usr/local/bin/verify-checksum
RUN chmod +x /usr/local/bin/verify-checksum

RUN mkdir -p -m 755 /etc/apt/keyrings \
	&& ARCH=$(dpkg --print-architecture) \
	# gnupg needed for key imports, purged at end of this layer
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gnupg \
	# GitHub CLI
	&& curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	# Eza
	&& curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
	&& echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list \
	# Install from repos
	&& apt-get update \
	&& apt-get install -y --no-install-recommends gh eza \
	&& rm -rf /var/lib/apt/lists/* \
	# Purge build-only dependency
	&& apt-get purge -y --auto-remove gnupg \
	# Delta (arch-aware deb)
	&& curl -fsSLo /tmp/delta.deb "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" \
	&& verify-checksum /tmp/delta.deb "git-delta_${DELTA_VERSION}_${ARCH}.deb" \
	&& dpkg -i /tmp/delta.deb \
	&& rm /tmp/delta.deb \
	# Yq (arch-aware binary)
	&& curl -fsSLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" \
	&& verify-checksum /usr/local/bin/yq "yq_linux_${ARCH}" \
	&& chmod +x /usr/local/bin/yq

# 3a. Git Tools

RUN DPKG_ARCH=$(dpkg --print-architecture) \
	&& if [ "$DPKG_ARCH" = "arm64" ]; then LARCH="arm64"; GOARCH="arm64"; else LARCH="x86_64"; GOARCH="amd64"; fi \
	# Lazygit
	&& curl -fsSLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LARCH}.tar.gz" \
	&& verify-checksum /tmp/lazygit.tar.gz "lazygit_${LAZYGIT_VERSION}_Linux_${LARCH}.tar.gz" \
	&& tar xf /tmp/lazygit.tar.gz -C /tmp lazygit \
	&& install /tmp/lazygit /usr/local/bin \
	&& rm /tmp/lazygit /tmp/lazygit.tar.gz \
	# gh-dash
	&& curl -fsSLo /usr/local/bin/gh-dash "https://github.com/dlvhdr/gh-dash/releases/download/v${GH_DASH_VERSION}/gh-dash_v${GH_DASH_VERSION}_linux-${GOARCH}" \
	&& verify-checksum /usr/local/bin/gh-dash "gh-dash_v${GH_DASH_VERSION}_linux-${GOARCH}" \
	&& chmod +x /usr/local/bin/gh-dash

# 3b. File & HTTP Tools

RUN DPKG_ARCH=$(dpkg --print-architecture) \
	&& if [ "$DPKG_ARCH" = "arm64" ]; then ZARCH="aarch64"; LARCH="arm64"; else ZARCH="x86_64"; LARCH="x86_64"; fi \
	# xh
	&& curl -fsSLo /tmp/xh.tar.gz "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${ZARCH}-unknown-linux-musl.tar.gz" \
	&& verify-checksum /tmp/xh.tar.gz "xh-v${XH_VERSION}-${ZARCH}-unknown-linux-musl.tar.gz" \
	&& tar xzf /tmp/xh.tar.gz --strip-components=1 -C /usr/local/bin "xh-v${XH_VERSION}-${ZARCH}-unknown-linux-musl/xh" \
	&& rm /tmp/xh.tar.gz \
	# Yazi
	&& curl -fsSLo /tmp/yazi.zip "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-${ZARCH}-unknown-linux-musl.zip" \
	&& verify-checksum /tmp/yazi.zip "yazi-${ZARCH}-unknown-linux-musl.zip" \
	&& unzip -q /tmp/yazi.zip -d /tmp \
	&& mv /tmp/yazi-${ZARCH}-unknown-linux-musl/yazi /usr/local/bin/ \
	&& mv /tmp/yazi-${ZARCH}-unknown-linux-musl/ya /usr/local/bin/ \
	&& rm -rf /tmp/yazi* \
	# Glow
	&& curl -fsSLo /tmp/glow.tar.gz "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_${LARCH}.tar.gz" \
	&& verify-checksum /tmp/glow.tar.gz "glow_${GLOW_VERSION}_Linux_${LARCH}.tar.gz" \
	&& tar xzf /tmp/glow.tar.gz -C /tmp \
	&& find /tmp -name 'glow' -type f -executable -exec mv {} /usr/local/bin/glow \; \
	&& rm -f /tmp/glow.tar.gz

# 3c. Shell Tools

RUN DPKG_ARCH=$(dpkg --print-architecture) \
	&& if [ "$DPKG_ARCH" = "arm64" ]; then ZARCH="aarch64"; else ZARCH="x86_64"; fi \
	# Starship
	&& curl -fsSLo /tmp/starship.tar.gz "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${ZARCH}-unknown-linux-musl.tar.gz" \
	&& verify-checksum /tmp/starship.tar.gz "starship-${ZARCH}-unknown-linux-musl.tar.gz" \
	&& tar xf /tmp/starship.tar.gz -C /usr/local/bin starship \
	&& rm /tmp/starship.tar.gz \
	# Clean up checksums
	&& rm -f /tmp/checksums.txt

# 4. User Setup

RUN userdel -r ubuntu 2>/dev/null || true \
	&& useradd -m -s /bin/bash -u 1000 dev \
	&& mkdir -p /home/dev/.claude /home/dev/.config/lazygit \
	&& chown -R dev:dev /home/dev

# 5. Config Files

RUN printf '[core]\n\tpager = delta\n[interactive]\n\tdiffFilter = delta --color-only\n[delta]\n\tnavigate = true\n\tdark = true\n[merge]\n\tconflictstyle = zdiff3\n' > /etc/gitconfig \
	&& printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > /home/dev/.config/lazygit/config.yml

# 6. Setup script

COPY --chown=dev:dev setup.sh /home/dev/setup.sh
COPY --chown=dev:dev setup-checksums.txt /home/dev/setup-checksums.txt
COPY --chown=dev:dev starship.toml /home/dev/.config/starship.toml

COPY scripts/squarebox-update.sh /usr/local/bin/sqrbx-update
RUN chmod +x /usr/local/bin/sqrbx-update

RUN chown -R dev:dev /home/dev/.config /home/dev/.claude \
	&& mkdir -p /workspace && chown dev:dev /workspace \
	&& chown dev:dev /usr/local/bin

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

WORKDIR /workspace

FROM ubuntu:24.04

# 1. Base Packages & Rust CLI Tools (consolidated, slimmed)

RUN apt-get update && apt-get install -y --no-install-recommends \
	git \
	curl \
	unzip \
	jq \
	zstd \
	sudo \
	less \
	btop \
	tmux \
	ca-certificates \
	gnupg \
	fd-find \
	ripgrep \
	bat \
	fzf \
	zoxide \
	&& rm -rf /var/lib/apt/lists/* \
	&& ln -s $(which fdfind) /usr/local/bin/fd \
	&& ln -s $(which batcat) /usr/local/bin/bat

# 2. External APT Repos (GitHub CLI, Eza) + Binary Tools

ARG DELTA_VERSION=0.18.2

RUN mkdir -p -m 755 /etc/apt/keyrings \
	&& ARCH=$(dpkg --print-architecture) \
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
	# Delta & Yq (arch-aware debs)
	&& curl -fsSLo /tmp/delta.deb "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" \
	&& dpkg -i /tmp/delta.deb \
	&& rm /tmp/delta.deb \
	&& curl -fsSLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_${ARCH}" \
	&& chmod +x /usr/local/bin/yq

# 3. Binary Tools (arch-aware, single layer)

RUN ARCH=$(uname -m) \
	&& if [ "$ARCH" = "aarch64" ]; then ZARCH="aarch64"; LARCH="arm64"; GOARCH="arm64"; OCARCH="arm64"; else ZARCH="x86_64"; LARCH="x86_64"; GOARCH="amd64"; OCARCH="x64"; fi \
	# Lazygit
	&& LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
	&& curl -fsSLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_${LARCH}.tar.gz" \
	&& tar xf /tmp/lazygit.tar.gz -C /tmp lazygit \
	&& install /tmp/lazygit /usr/local/bin \
	&& rm /tmp/lazygit /tmp/lazygit.tar.gz \
	# xh
	&& XH_VERSION=$(curl -s "https://api.github.com/repos/ducaale/xh/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
	&& curl -fsSL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${ZARCH}-unknown-linux-musl.tar.gz" | tar xz --strip-components=1 -C /usr/local/bin "xh-v${XH_VERSION}-${ZARCH}-unknown-linux-musl/xh" \
	# Yazi
	&& curl -fsSLo /tmp/yazi.zip "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${ZARCH}-unknown-linux-musl.zip" \
	&& unzip -q /tmp/yazi.zip -d /tmp \
	&& mv /tmp/yazi-${ZARCH}-unknown-linux-musl/yazi /usr/local/bin/ \
	&& mv /tmp/yazi-${ZARCH}-unknown-linux-musl/ya /usr/local/bin/ \
	&& rm -rf /tmp/yazi* \
	# Starship
	&& curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin \
	# gh-dash
	&& GH_DASH_VERSION=$(curl -s "https://api.github.com/repos/dlvhdr/gh-dash/releases/latest" | grep -Po '"tag_name": "\K[^"]*') \
	&& curl -fsSLo /usr/local/bin/gh-dash "https://github.com/dlvhdr/gh-dash/releases/download/${GH_DASH_VERSION}/gh-dash_${GH_DASH_VERSION}_linux-${GOARCH}" \
	&& chmod +x /usr/local/bin/gh-dash \
	# Glow
	&& GLOW_VERSION=$(curl -s "https://api.github.com/repos/charmbracelet/glow/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
	&& curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_${LARCH}.tar.gz" | tar xz -C /tmp \
	&& mv /tmp/glow /usr/local/bin/ \
	# Fresh
	&& curl -fsSLo /tmp/fresh.tar.gz "https://github.com/sinelaw/fresh/releases/latest/download/fresh-editor-${ZARCH}-unknown-linux-musl.tar.gz" \
	&& tar xf /tmp/fresh.tar.gz -C /tmp \
	&& find /tmp -name 'fresh' -type f -executable -exec mv {} /usr/local/bin/fresh \; \
	&& rm -rf /tmp/fresh* \
	# Edit (Microsoft)
	&& EDIT_VERSION=$(curl -s "https://api.github.com/repos/microsoft/edit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
	&& curl -fsSL "https://github.com/microsoft/edit/releases/download/v${EDIT_VERSION}/edit-${EDIT_VERSION}-${ZARCH}-linux-gnu.tar.zst" | zstd -d | tar x -C /tmp \
	&& mv /tmp/edit /usr/local/bin/ \
	# OpenCode
	&& curl -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${OCARCH}.tar.gz" | tar xz -C /tmp \
	&& mv /tmp/opencode /usr/local/bin/

# 4. User Setup

RUN useradd -m -s /bin/bash dev \
	&& mkdir -p /home/dev/.claude /home/dev/.config/lazygit \
	&& chown -R dev:dev /home/dev \
	&& echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 5. Config Files

RUN printf '[core]\n\tpager = delta\n[interactive]\n\tdiffFilter = delta --color-only\n[delta]\n\tnavigate = true\n\tdark = true\n[merge]\n\tconflictstyle = zdiff3\n' > /etc/gitconfig \
	&& printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > /home/dev/.config/lazygit/config.yml

# 6. Claude Code Global CLAUDE.md (optional)

COPY --chown=dev:dev CLAUDE.md* /home/dev/.claude/
COPY --chown=dev:dev setup.sh /home/dev/setup.sh

RUN chown -R dev:dev /home/dev/.config /home/dev/.claude

USER dev

ENV HOME=/home/dev

# 7. Claude Code (install as dev user)

RUN curl -fsSL https://claude.ai/install.sh | bash

# 8. Shell Config

RUN cat <<'EOFRC' >> ~/.bashrc
eval "$(starship init bash)"
eval "$(zoxide init bash --cmd cd)"
alias ls='eza --icons'
alias ll='eza -la --icons'
alias cat='bat --paging=never'
alias claude-yolo='claude --dangerously-skip-permissions'
alias lg='lazygit'
export EDITOR='edit'
export PATH="$HOME/.local/bin:$PATH"
# First-run setup
if [ ! -f ~/.devbox-setup-done ]; then
	~/setup.sh && touch ~/.devbox-setup-done
fi
EOFRC

WORKDIR /workspace

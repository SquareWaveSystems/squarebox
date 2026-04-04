TUI Devbox
==========

Containerised development environment with modern CLI/TUI tools and Claude Code.

Install
-------

    curl -fsSL https://raw.githubusercontent.com/BrettKinny/tui-devbox/main/install.sh | bash

This clones the repo, builds the Docker image, and drops you into the container.
On first login, a setup script runs automatically to configure git and GitHub CLI.

Start
-----

    docker start -ai devbox

When you exit the shell, the container stops but is not removed. All changes inside
the container (installed packages, config files, shell history) persist between
sessions. Think of it as a VM that suspends on exit and resumes on start.

Your code lives on the host at ~/tui-devbox-workspace and is mounted into the container, so it
is never lost even if the container is deleted.

The install script also adds a `devbox` alias to your shell, so after the first
run you can just type `devbox` to jump back in.

How it works
------------

The container is a persistent stopped container, not an ephemeral one. The
difference:

- Ephemeral (`docker run --rm`): container is deleted when you exit. All
  filesystem changes are lost.
- Persistent (what this uses): container stops when you exit but stays on disk.
  `docker start -ai` resumes it with everything intact.

Volume mounts:

- ~/tui-devbox-workspace -> /workspace: your code (lives on host, survives container deletion)
- ~/.ssh -> /home/dev/.ssh (read-only): SSH keys for git
- ~/.config/git -> /home/dev/.config/git: shared git config

Nuke and rebuild
----------------

Destroys the container and rebuilds from scratch. Your code in ~/tui-devbox-workspace is safe
since it lives on the host.

    docker stop devbox 2>/dev/null
    docker rm devbox
    cd ~/tui-devbox
    docker build -t devbox .
    docker run -it --name devbox \
      -v ~/tui-devbox-workspace:/workspace \
      -v ~/.ssh:/home/dev/.ssh:ro \
      -v ~/.config/git:/home/dev/.config/git \
      devbox

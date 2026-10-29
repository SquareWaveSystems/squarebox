# Squarebox compared with other environments and sandboxes

> **Draft.** Last reviewed 2026-10-29. Several of these tools are pre-1.0 and
> change quickly. Check each project's own docs before relying on a cell.

People reach for Squarebox, dev containers, and AI-agent sandboxes for
different jobs. Some give you a consistent, tool-rich environment. Others limit
what an agent can touch. A few do both. This page compares them on the
properties that matter when you let AI assistants run code.

Squarebox is a portable development Box. It is not a hostile-code sandbox (see
[SECURITY.md](../SECURITY.md#container-authority-and-isolation)).

## At a glance

| Tool | Primary job | Isolation boundary | Outbound network | Credentials the agent can see | Workspace access | Runs on |
| --- | --- | --- | --- | --- | --- | --- |
| **Squarebox** | Portable dev environment with curated CLI/TUI tools and assistants | Container, with reduced capabilities and a PID limit | Unrestricted ([opt-in allowlist proposed](adr/0011-opt-in-egress-allowlist.md)) | Everything persisted in the Managed home; SSH agent socket if forwarded | Read-write bind mount | Docker or Podman on Linux, macOS, Windows; Compose; Dev Containers; Codespaces |
| **Dev Containers** (spec, VS Code) | Reproducible per-project dev environment | Container, configured per project | Unrestricted unless you configure it | Whatever the config and editor forward (Git credentials, SSH agent, env vars) | Read-write bind mount | Any Docker-compatible runtime |
| **GitHub Codespaces** | Hosted Dev Containers | Container on a dedicated cloud VM | No built-in allowlist | Codespaces secrets, exposed as environment variables; GitHub token | Repo clone on the VM | GitHub-hosted |
| **Docker Sandboxes** (`sbx`) | Run coding agents unattended | microVM with its own kernel | HTTP/HTTPS allowlist (`sbx policy allow`); raw TCP, UDP, and ICMP blocked | A host-side proxy injects credentials into requests, so the agent doesn't hold the raw values | Read-write mount by default; `--clone` gives a private copy | macOS (Apple silicon), Windows 11, Ubuntu 24.04+ with KVM |
| **Anthropic sandbox-runtime** (`srt`, used by Claude Code's sandbox) | Confine one process, with no container | OS sandbox: bubblewrap on Linux, Seatbelt on macOS | Domain allowlist through host-side HTTP/SOCKS proxies | Whatever the filesystem rules allow it to read | Filesystem allow/deny rules | Linux, macOS |
| **Container Use** (Dagger) | Parallel agents, each in its own branch | Container per agent, via Dagger | Not a focus | Whatever the container gets | Its own Git branch or worktree, reviewed through Git | Anywhere Dagger runs; MCP server for agents |
| **NVIDIA OpenShell** | Policy-governed runtime for fleets of agents | Container or VM, plus Landlock, seccomp, and a network namespace | Default deny; per-binary host rules with optional HTTP method/path rules | Provider credentials injected by a TLS-terminating proxy | Policy-defined filesystem access | Linux, macOS (Apple silicon), WSL 2; Kubernetes gateway |
| **Hosted agent sandboxes** (E2B, Daytona, and others) | Code-execution API for agent products | Firecracker microVM (E2B); varies by provider | Provider-specific | What your application passes in | Files uploaded through the API | Vendor cloud; Daytona can self-host |
| **Distrobox / Toolbx** | Run another distro's userland on the host | Container, deliberately well integrated with the host | Host network | Your host home directory, by default | Your whole host home directory | Linux |
| **Nix devshells / mise alone** | Pin toolchains per project | None | Host network | Everything your user can read | The host filesystem | Host OS |

## Choosing

- **You want the same terminal tools and assistants everywhere, and you trust
  what runs in them:** use Squarebox, or Dev Containers if you prefer to build
  your own image per project.
- **You want an agent to run unattended with a hard network and credential
  boundary:** use Docker Sandboxes or OpenShell, or confine individual commands
  with `srt`. Squarebox's `*-yolo` aliases don't give you this today.
- **You want several agents working in parallel without conflicts:** use
  Container Use, or Git worktrees inside one Box.
- **You are building a product that runs model-generated code:** use a hosted
  sandbox API.
- **You just want host-integrated tools from another distro:** use Distrobox or
  Toolbx. They are not isolation.

## What Squarebox borrows, and where it differs

- Like Dev Containers, Squarebox is a container you reuse. It adds a
  persistent Managed home and runs on Docker, Podman, Compose, Dev Containers,
  and Codespaces.
- Unlike Docker Sandboxes and OpenShell, it doesn't yet enforce network egress
  or keep credentials out of the Box. [ADR 0011](adr/0011-opt-in-egress-allowlist.md)
  proposes host-level egress filtering. It deliberately does not include TLS
  interception or credential injection.
- Unlike `srt`, it doesn't confine individual processes. Everything in the Box
  shares the same access.
- Unlike hosted sandboxes, it runs on your own machine or server, and your
  state stays in your own volume.

## Sources

- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/),
  [security defaults](https://docs.docker.com/ai/sandboxes/security/defaults/),
  [get started](https://docs.docker.com/ai/sandboxes/get-started/)
- [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- [dagger/container-use](https://github.com/dagger/container-use)
- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) and its
  [security best practices](https://docs.nvidia.com/openshell/latest/security/best-practices)
- [E2B vs Daytona comparison (third party)](https://www.morphllm.com/comparisons/e2b-vs-daytona)
- [Dev Containers specification](https://containers.dev/)
- [GitHub Codespaces docs](https://docs.github.com/en/codespaces)
- [Distrobox](https://distrobox.it/) and [Toolbx](https://containertoolbx.org/)

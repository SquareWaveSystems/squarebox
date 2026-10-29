# Security

## Supported versions

Security fixes are applied to the latest published stable Release and to an
actively tested release candidate when one exists. Older images and raw Git
commits may contain known defects; rebuild or reinstall from a current
published Release before reporting a problem that may already be fixed.

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/SquareWaveSystems/squarebox/security/advisories/new).
Do not open a public issue for a suspected vulnerability, leaked credential,
or exploitable installation path. Include the Squarebox version, image digest,
host/runtime versions, architecture, reproduction steps, and the impact you
observed.

## Host changes made by the installer

The Bash and PowerShell lifecycle adapters:

1. Resolve a published Squarebox Release, including its `release.json` identity.
2. Create or update the recorded install directory and Workspace.
3. Pull the Release image by immutable digest, or build only when explicitly requested.
4. Create an installation-private Git config containing only `user.name` and
   `user.email`; the host's real Git config and credential helpers are not mounted.
5. Create a named Managed-home volume and a labeled Box owned by one Install identity.
6. Mount the Workspace read-write, the private Git identity, optional SSH access,
   and explicitly documented managed configuration. Bash/POSIX and Git Bash
   adapters forward `SSH_AUTH_SOCK` when available and otherwise mount SSH files
   read-only only on explicit opt-in; native PowerShell provides only the
   opt-in read-only SSH-file path.
7. Add a sentinel-delimited shell integration block that reads the recorded
   Install identity for launch, rebuild, and uninstall operations.

For rootless Podman, the adapter maps the host user to container UID/GID 1000
(`dev`) and passes `--security-opt label=disable`. This avoids recursively
relabeling the Workspace, home SSH files, or system files with private `:Z`
labels. The tradeoff is explicit: SELinux container separation is disabled for
this Box, which is already treated as a trusted development environment rather
than a hostile-code sandbox. Host DAC permissions and the declared mounts
remain the access boundary.
Because the entrypoint is already unprivileged in this mode, rootless Podman
rejects PUID/PGID overrides that differ from the invoking host identity;
the native Linux POSIX lifecycle adapter rejects the same mismatch for every
unprivileged runtime before it mutates host state. Root-run rootful runtimes
retain explicit remapping for administered NAS and Unraid installations.

The installer does not install host packages. On legacy Linux installs it may
need to repair ownership that an older Squarebox release changed; any host
`sudo` use must be displayed and confirmed. New Linux installs default to the
invoking user's numeric UID/GID. macOS and Windows hosts default the Linux Box
user to UID/GID 1000 because native host IDs are not portable into Docker
Desktop. No platform repurposes the host's Git config.

Before running a downloaded installer, inspect it:

```bash
(
  set -euo pipefail
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSLo "$tmp/install.sh" \
    https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.sh
  less "$tmp/install.sh"
  bash "$tmp/install.sh"
)
```

Piping directly to Bash trusts GitHub and TLS to deliver the intended bootstrap
asset. Download-and-inspect is the safer default.

## SSH access

The Box does not receive your SSH private-key files by default, because anything
running inside it, including unattended `*-yolo` AI agents, could read them.

- **SSH agent (recommended).** When `SSH_AUTH_SOCK` points at a running agent,
  the Bash/POSIX and Git Bash adapters forward the agent socket and mount only
  `~/.ssh/config` and `~/.ssh/known_hosts` read-only. Key files stay on the
  host, though Box processes can ask the agent to sign while the socket is
  available.
- **No agent.** `~/.ssh` is not mounted, and install prints a note. To mount
  the directory read-only instead, opt in with `SQUAREBOX_MOUNT_SSH=1` (native
  PowerShell: `.\install.ps1 -MountSsh` or `$env:SQUAREBOX_MOUNT_SSH = '1'`).
  The choice is recorded in the Install identity and reused by
  `sqrbx-rebuild`; set `SQUAREBOX_MOUNT_SSH=0` (or `-MountSsh:$false`) on a
  rebuild to turn it back off.

## Release identity and verification

Every v1.1+ Release includes:

- `release.json`, binding the version and source SHA to an immutable
  multi-architecture image digest;
- `e2e-report.md`, `e2e-required.tsv`, and `evidence-manifest.json`, whose
  hashes bind the exact required Evidence to that source SHA and image digest;
- `SHA256SUMS` for the Bash/PowerShell lifecycle adapters, release identity,
  and Evidence assets;
- `SHA256SUMS.sigstore.json`, a Sigstore bundle for the checksum file;
- an identity signature on the image digest;
- an SBOM and provenance attestation attached to the Candidate image.

Verification requires `jq`, Cosign, a current GitHub CLI with
`gh release verify`, and either `sha256sum` or `shasum`.

Verify downloaded assets:

```bash
(
  set -euo pipefail
  if command -v sha256sum >/dev/null; then
    sha256sum --check SHA256SUMS
  else
    shasum -a 256 --check SHA256SUMS
  fi
  version=$(jq -er .version release.json)
  gh release verify "$version" --repo SquareWaveSystems/squarebox
  workflow_identity="https://github.com/SquareWaveSystems/squarebox/.github/workflows/e2e.yml@refs/tags/$version"
  cosign verify-blob \
    --bundle SHA256SUMS.sigstore.json \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity "$workflow_identity" \
    SHA256SUMS
)
```

Verify the image named by `release.json`:

```bash
(
  set -euo pipefail
  image_ref=$(jq -er .image_ref release.json)
  version=$(jq -er .version release.json)
  workflow_identity="https://github.com/SquareWaveSystems/squarebox/.github/workflows/e2e.yml@refs/tags/$version"
  cosign verify \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity "$workflow_identity" \
    "$image_ref"
)
```

The stable installer discovers published GitHub Releases, not raw Git tags. A
tag under test therefore cannot replace stable installation metadata. For a
stable version, the final tag is built and its signed assets are verified in a
non-discoverable draft before physical qualification. A required reviewer on
the `v1.1-production` environment authorizes publication only after that
qualification. The publication job downloads and verifies the draft assets
again, then promotes the exact tested Candidate digest rather than rebuilding
different image bytes. Prereleases use the same automated integrity gates but
publish without the stable human-approval wait.

Two repository controls are release prerequisites: GitHub immutable releases,
and the active, no-bypass `Protect release tags` ruleset matching
`refs/tags/v*` with update and deletion protection. The immutable-release
settings endpoint requires repository Administration access, so an
administrator verifies it before creating a release tag; the workflow's scoped
`GITHUB_TOKEN` cannot perform that settings preflight. As defense in depth, the
workflow resolves annotated and lightweight remote tags to the exact Candidate
source both before drafting and after approval. It then requires GitHub's
immutable flag and signed Release attestation, verifies the GitHub latest
pointer selected during publication, and only then changes GHCR convenience
aliases.

## Download trust by Tool tier

| Tool tier | Source | Integrity policy | Version policy |
| --- | --- | --- | --- |
| Image tier binary artifacts | Official GitHub Releases | Squarebox-pinned SHA-256, checked against the exact GitHub release-asset digest during pin refresh; installation fails closed if missing/mismatched | Pinned in the Candidate |
| Image tier APT packages | Ubuntu archive; build-only GitHub CLI and Eza repositories | APT repository signatures; external signing keys pinned by full primary-key fingerprint and verified before they are trusted | Distribution/repository version |
| Box tier packages | APT inside the Box | APT repository signatures | Reconciled when selected |
| Managed-home GitHub tools | Official GitHub Releases | Exact release tag and asset name; GitHub release-asset SHA-256 digest; fail closed if missing, duplicate, malformed, or mismatched | Selected latest or explicit release |
| Managed-home Git sources | Official GitHub repositories (LazyVim, Oh My Zsh, and Zsh plugins) | Default branch resolved through GitHub metadata to a full commit SHA; exact fetch/checkout and HEAD verification before activation | Resolved only during an explicit setup/reconcile action; local changes are preserved by refusal |
| Managed-home npm assistants | npm registry | npm package integrity metadata | Explicit update/setup action |
| Claude installer | Anthropic HTTPS installer | Transport plus authoritative download/installer exit status | Explicit update/setup action |
| SDKs | mise backends and language upstreams | mise/backend policy | Selected latest unless configured otherwise |

`scripts/lib/tools.yaml` records whether each artifact uses Squarebox's pinned
`sha256` manifest or `github-release-digest`. The shared installation module
validates the exact release tag and exact asset name before download, compares
the downloaded bytes with the authoritative digest before extraction, and
returns the original failure after cleanup. Release metadata is cached only for
the current setup/update run, including across normal Bash subprocesses, in a
current-user-only directory. A prepared digest is bound to its Tool identity.
Unsupported architectures and invalid Tool-tier/destination combinations fail
before network or destination mutation. Extracted archives reject escaping
links, special files, and ambiguous executable matches before promotion.

GitHub API metadata requests are optionally authenticated to raise the
unauthenticated rate limit. The token comes from `GH_TOKEN`, then
`GITHUB_TOKEN`, then an already-authenticated `gh` CLI (`gh auth token`, only
for the default `https://api.github.com` base; never prompted). It is sent as
an `Authorization: Bearer` header only to the configured HTTPS API base, never
to artifact downloads or redirect targets, and reaches curl through a stdin
config rather than its command line. It is not logged or written to the
metadata cache. An HTTP 401 drops the token for the rest of that run and
retries once unauthenticated. Authentication changes only rate limits; it does
not relax digest verification.

The GitHub CLI and Eza APT repositories are configured only while the image
builds (then removed). Their signing keys are not trusted on download alone:
the Dockerfile pins each key's expected full 40-hex primary-key fingerprint set
in `GH_CLI_KEY_FINGERPRINTS` and `EZA_KEY_FINGERPRINTS`, and the build fails
unless the downloaded keyring contains exactly that set of primary keys
(subkeys are not compared). The check runs before any keyring is installed
under `/etc/apt/keyrings` or any source list refers to it. The Eza key is
fetched from an immutable eza commit (`EZA_KEY_URL`), not a branch.
`tests/test-apt-key-policy.sh` asserts this policy statically.

To rotate a key, obtain the new key and confirm its fingerprint out-of-band
before editing the ARG: compare `gpg --show-keys --with-colons` output with the
publisher's documentation (GitHub CLI lists its fingerprints in
`docs/install_linux.md`) and with the issuer fingerprint on the live
repository's `Release.gpg`/`InRelease` signature. Never copy the value from a
failed build's "actual" output alone; a mismatch is exactly the signal this
control exists to raise.

Image-tier runtime updates receive one additional gate: the exact current-arch
artifact in the Candidate checksum manifest must equal GitHub's digest for the
resolved upstream release asset. Otherwise `sqrbx-update` reports that a newer
Candidate and Box rebuild are required and does not download or promote it.

Multi-output managed-home installs (currently Yazi's `yazi`/`ya`, Helix's
`hx`/runtime, and Neovim's tree/entry link) stage every output before the first
destination replacement. Unexpected destination types are rejected rather than
recursively removed, and concurrent installs serialize on one Managed-home
lock. A later observed failure rolls all destinations back.
This is rollback transactionality, not crash atomicity: `SIGKILL`, host failure,
or power loss between per-destination renames can leave stages, backups, or a
partial result that needs inspection and a rerun.

`sqrbx-update` retains those Managed-home backups and the install lock until it
has verified both the reported version and every required companion output.
Post-install mismatch restores the prior complete output set. A broken version
probe or missing Yazi helper, Helix runtime, or Neovim tree/link is reported as
repairable incomplete state rather than “up to date.”

Setup installs absent selections; `sqrbx-update --apply` explicitly updates
already installed registered tools to newer authorized releases. Oh My Pi uses
its official mise GitHub backend and follows mise’s backend integrity policy.

External installers and package managers are outside this artifact registry.
That includes npm assistants, Anthropic's Claude installer, mise SDK backends,
APT, and `dpkg`; their integrity and transaction behavior remain the upstream
tool's contract. In particular, a failing `dpkg` invocation may already have
changed the package database or run maintainer scripts, so Squarebox does not
claim to roll system package installation back.

## Reproducibility limits

Published Candidate bytes are immutable and identified by digest. Rebuilding
the Dockerfile later is not guaranteed to produce the same digest: the Ubuntu
base tag, APT repositories, and some package versions are external mutable
inputs. Image-tier direct-download tools are pinned and checksummed, but that
does not make the entire Docker build bit-for-bit reproducible.

Maintainer version refresh resolves one exact release asset per architecture,
requires its GitHub SHA-256 digest, and verifies downloaded bytes before
generating pins. Refreshes serialize per repository, abort if either tracked
input changes during the run, and keep destination-local originals so rollback
uses atomic renames rather than copy-over writes. Review both files, upstream
signatures where available, and the release notes before accepting a refresh;
GitHub's digest is an integrity snapshot, not an independent publisher signature.

## Container authority and isolation

The Box is a development environment, not a hostile-code security sandbox.
The `dev` user can invoke passwordless package-management/install commands.
`dpkg` maintainer scripts and `install` can provide effective root authority
inside the Box, so the sudo allowlist is an operational control, not a security
barrier against a malicious Box user.

### Runtime controls at a glance

Each row is a control that shapes what code running in the Box can reach. The
sections below give the details.

| Control | Default | What you can change | Risk if relaxed or misused | Recommendation |
| --- | --- | --- | --- | --- |
| Linux capabilities | All dropped, then `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `KILL` re-added (Dev Container also adds `SYS_CHROOT`). | Only by editing Compose, `devcontainer.json`, or the runtime command yourself. The adapters expose no setting for this. | Extra capabilities such as `SYS_ADMIN` or `NET_ADMIN` widen the host kernel surface that container root can reach. | Keep the default set. |
| PID limit | `4096`. | Same as capabilities. | Without a limit, a fork bomb in the Box can exhaust the host's process table. | Keep the limit. |
| Package-management sudo | Passwordless `apt-get`, `apt-mark`, `dpkg`, `chown`, and `install` for `dev`, plus narrow `mv`/`rm` forms for staged `/usr/local/bin` promotion. | Not configurable. | This is effectively root inside the Box. It is not a barrier. | Treat every Box process as able to become root inside the Box. |
| Workspace mount | Read-write at `/workspace`. | Choose the host directory at install time. | Box processes can modify or delete project files, including `.git/hooks` and other config that host tools later run. | Push work regularly, and check `.git/hooks` and build scripts before running them on the host after an unattended session. |
| Managed home | Persistent volume holding history, `gh` auth, assistant logins, and SDKs. | Not configurable. | Any Box process can read every persisted token. | Use fine-grained, narrowly scoped tokens. Revoke them if the Box may be compromised. |
| Git identity | Private name/email config only. The host's Git config and credential helpers are never mounted. | Not configurable. | — | — |
| SSH access | Agent socket plus read-only `config`/`known_hosts` when an agent is available (Bash adapters). Otherwise none. | `SQUAREBOX_MOUNT_SSH=1` / `-MountSsh` mounts `~/.ssh` read-only when no agent is forwarded. | The opt-in exposes private keys to every Box process. A forwarded agent signs for any Box process while it is available. | Use an agent with per-use confirmation, or a dedicated narrow-scope key. Leave the directory mount off. |
| Network egress | Unrestricted outbound. The Box publishes no ports. | Not yet. An opt-in allowlist is proposed in [ADR 0011](docs/adr/0011-opt-in-egress-allowlist.md). | Any reachable host can receive Workspace content or tokens. On cloud VMs, `169.254.169.254` can hand out instance credentials. | Don't give unattended assistants credentials or Workspace content you couldn't afford to have exfiltrated. |
| Unattended assistants | Off. The `*-yolo` aliases skip approval prompts only when you invoke them. | Use them or not, per invocation. | They combine every exposure in this table with no human in the loop. | Prefer approval modes. Use `*-yolo` only in a Box whose Workspace, tokens, and SSH access are scoped for it. |
| Rootless Podman SELinux | `--security-opt label=disable` for the Box. | Not configurable. | SELinux container separation is off. Host file permissions and the declared mounts are the only boundary. | Validate on the target host before using sensitive credentials. |
| Additional mounts | None beyond those listed above. | Add your own through Compose, Dev Container config, or the runtime command. | Every added mount is fully exposed to Box processes. | Mount the narrowest path you can, and read-only where possible. |

Dev Container and Codespaces builds add the digest-locked official SSH server
Feature to the derived development image; the published Squarebox Candidate
does not contain that server. The upstream Feature enables root login in its
SSHD configuration, but Squarebox publishes no SSH host port or password, and
restricts remote-forwarded listeners to loopback.

The Dev Container applies the same `runArgs` hardening as the installers and
Compose: `--cap-drop=ALL`, re-adding only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`,
`SETUID`, `SETGID`, and `KILL`, plus `--pids-limit=4096`. It adds exactly one
extra capability, `SYS_CHROOT`, because the SSH server Feature's OpenSSH uses
privilege separation: the pre-authentication child `chroot`s into `/run/sshd`,
and without `SYS_CHROOT` every connection is reset during key exchange. The
Feature listens on port 2222, so `NET_BIND_SERVICE` is not needed, and logins
were verified to succeed without `AUDIT_WRITE`.

Linux capabilities are reduced, and the Box is bounded to 4096 PIDs so a
runaway process cannot exhaust the host's process table. The Box has network
access and the host resources explicitly mounted by its Install identity.
Treat code and tools run inside it as having access to:

- the Workspace, read-write;
- the Managed home, including persisted tool credentials;
- the installation-private Git name/email config;
- an SSH agent socket, plus read-only `~/.ssh/config` and `~/.ssh/known_hosts`,
  when the Bash/POSIX or Git Bash adapter forwards an available agent;
- the read-only `~/.ssh` directory, including private keys, only when the
  operator opts in with `SQUAREBOX_MOUNT_SSH=1` (or `-MountSsh` on native
  PowerShell) and no agent is forwarded;
- any additional mounts the operator supplies.

Agent forwarding keeps private-key files on the host, but processes inside the
Box can ask the forwarded agent to sign while the socket is available. Because
AI assistants may run unattended in the Box (for example the `*-yolo` aliases),
the `~/.ssh` directory is never mounted by default: without an agent the Box
gets no SSH material and install prints how to opt in. The opt-in exposes every
file in that directory, private keys included, read-only to all Box processes.
It is recorded as `MOUNT_SSH` in the Install identity and reused on rebuild
until a rebuild sets `SQUAREBOX_MOUNT_SSH=0`. Prefer an agent, ideally with
per-use confirmation, or a dedicated key with narrow scope.

The entrypoint validates numeric UID/GID inputs and refuses unsafe Managed-home
dotfile symlinks. On native Linux, an unprivileged lifecycle install also
requires PUID/PGID to match the invoking account because a different Box owner
cannot safely share its private host-bound lifecycle files. Explicit ownership
remapping is reserved for root-run rootful runtimes, including Docker or Podman
on NAS and Unraid.
Rootless Podman maps keep-id to the image's `dev` account and leaves host SELinux
labels untouched by disabling label separation for the Box; validate this
tradeoff on the target host before using sensitive credentials.

If an existing POSIX Install identity records IDs that no longer match the
invoking Linux account, adopt the current account without changing channels or
paths:

```bash
PUID="$(id -u)" PGID="$(id -g)" "$SQUAREBOX_DIR/install.sh"
```

An older Box may already have changed the specific host binds that it mounted
beneath `/home/dev`. Stop the recorded Box, then restore only those paths after
validating the recorded install and Workspace identities:

```bash
set -euo pipefail
case "${SQUAREBOX_DIR:-}" in /*) ;; *) exit 64 ;; esac
[ "$SQUAREBOX_DIR" != / ] && [ ! -L "$SQUAREBOX_DIR" ] || exit 64
state="$SQUAREBOX_DIR/.squarebox/install-state"
sudo test -f "$state" && sudo test ! -L "$state" || exit 1
state_value() {
  sudo awk -F= -v wanted="$1" '
    $1 == wanted { count++; value = substr($0, index($0, "=") + 1) }
    END { if (count != 1) exit 1; print value }
  ' "$state"
}
format=$(state_value FORMAT)
recorded_install=$(state_value INSTALL_DIR)
workspace=$(state_value WORKSPACE_DIR)
[ "$format" = 1 ] && [ "$recorded_install" = "$SQUAREBOX_DIR" ] || exit 64
case "$workspace" in /*) ;; *) exit 64 ;; esac
[ "$workspace" != / ] && sudo test -d "$workspace" \
  && sudo test ! -L "$workspace" || exit 64

git_identity="$SQUAREBOX_DIR/.squarebox/identity/git"
lazygit_config="$SQUAREBOX_DIR/.config/lazygit"
starship_config="$SQUAREBOX_DIR/.config/starship.toml"
sudo test -d "$git_identity" && sudo test ! -L "$git_identity" || exit 1
sudo test -d "$lazygit_config" && sudo test ! -L "$lazygit_config" || exit 1
sudo test -f "$starship_config" && sudo test ! -L "$starship_config" || exit 1

owner="$(id -u):$(id -g)"
sudo chown -R --preserve-root -- "$owner" "$git_identity" "$lazygit_config"
sudo chown --no-dereference -- "$owner" "$starship_config" "$workspace"
PUID="$(id -u)" PGID="$(id -g)" "$SQUAREBOX_DIR/install.sh"
```

Do not replace these resolved paths with the home directory, the install root,
or another broad recursive target.

## Safe lifecycle deletion

Install and uninstall operations consume the persisted Install identity.
Containers and volumes are labeled with that identity, and destructive actions
verify ownership before removal. Recorded directories require a Squarebox
marker; an unrelated directory or resource with a familiar fixed name is not
authority to delete it.

`FORMAT` versions each lifecycle adapter's native state contract; it does not
make Bash/Git Bash and PowerShell Install-identity files interchangeable. Use
the matching adapter family for rebuild and uninstall operations, or explicitly
convert it with `scripts/migrate-windows-adapter.ps1`. The converter parses the
closed field set as data, verifies Box and Managed-home ownership, and
atomically transfers profile ownership; it never evaluates state or copies
Workspace, Managed home, or private keys.

If the runtime is unreachable, uninstall reports incomplete cleanup and returns
nonzero instead of treating the engine as empty. Host-only shell cleanup and
legacy-resource adoption require explicit operator choices.

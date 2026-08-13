# ADR 0009: Explicitly convert Windows adapter state

Status: Accepted

## Context

Git Bash and native PowerShell share the closed `FORMAT=1` field set, but paths
and shell-profile ownership are adapter-native. Letting either normal lifecycle
reader reinterpret the other's state would weaken fail-closed uninstall and
profile ownership checks.

Windows OpenSSH exposes a named pipe while Linux Boxes consume a Unix socket.
Neither Docker Desktop nor Podman documents one common supported bridge. Agent
forwarding is therefore tracked separately as an opt-in prototype rather than
being coupled to state migration.

## Decision

`scripts/migrate-windows-adapter.ps1` is the only cross-adapter conversion path.
It parses `FORMAT=1` as a closed data set, validates path/resource/source/image
identities, verifies the live Box and Managed-home ownership, and rejects
malformed, foreign, or already-target-native state.

The command translates only Windows path spelling and shell ownership. It does
not recreate the Box, retag its image, or copy, delete, or reconstruct Workspace
or Managed home. It snapshots both adapters' profile files, installs the target
entrypoint, removes source-owned blocks, and atomically replaces Install state.
Any handled failure restores every snapshotted file.

Normal install and uninstall readers remain unchanged and continue to reject
foreign adapter state. This preserves an explicit authority boundary and makes
migration auditable rather than implicit.

## Consequences

Migration requires PowerShell 7, even when Git Bash is the target. It is a local
metadata/profile transaction and does not require network access. Native Windows
tests cover parsing and the conversion safety contract; real Windows UAT covers
both directions, custom/non-ASCII paths, Docker Desktop, and Podman.

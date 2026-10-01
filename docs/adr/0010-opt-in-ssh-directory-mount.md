# ADR 0010: Make the SSH directory mount an opt-in Install identity setting

Status: Accepted

## Context

When no SSH agent socket was available, the Bash adapter mounted the host's
entire `~/.ssh` directory read-only into the Box. The native PowerShell adapter
never forwards an agent and always mounted `%USERPROFILE%\.ssh` when present.
That directory normally contains private keys. AI assistants can run unattended
inside the Box (the `*-yolo` aliases), so any Box process could read those keys
without the operator having chosen that exposure.

The choice must survive rebuilds like other lifecycle settings, so it belongs
in the Install identity. ADR 0007 requires a new format, a documented migration,
and cross-language fixtures before a field is added.

## Decision

Neither adapter mounts the `~/.ssh` directory by default. Agent forwarding in
the Bash adapter, with its read-only `~/.ssh/config` and `~/.ssh/known_hosts`
mounts, is unchanged because those files contain no private keys. When no agent
is forwarded and the opt-in is off, install prints how to enable it or use an
agent.

`SQUAREBOX_MOUNT_SSH=1` (both adapters) or `-MountSsh` (native PowerShell)
opts in to the previous read-only directory mount when no agent is forwarded.
`SQUAREBOX_MOUNT_SSH=0` or `-MountSsh:$false` opts out. Any other value fails
before lifecycle mutation.

The effective preference is recorded as `MOUNT_SSH=0|1` in a new `FORMAT=2`
Install identity, appended after `HOME_VOLUME_ADOPTED`. It records the operator's
preference, not whether a mount occurred on that run, because agent availability
can differ between rebuilds.

- Writers emit only `FORMAT=2`.
- Readers accept `FORMAT=2`, where `MOUNT_SSH` is required, and `FORMAT=1`,
  where `MOUNT_SSH` must be absent and reads as `0`. Every other format fails
  closed.
- The next successful rebuild republishes a `FORMAT=1` record as `FORMAT=2`.
  `scripts/migrate-windows-adapter.ps1` does the same when it converts state.
- Ownership rules from ADR 0004 and ADR 0009 are unchanged: path and profile
  values remain adapter-native and creator-owned.

`scripts/lib/install-state-schema.json` lists the `FORMAT=2` field order and
the defaults a `FORMAT=1` record omits. The verifier and shared fixtures cover
both formats in all four adapters.

## Consequences

Existing installs that relied on the implicit fallback lose `~/.ssh` inside the
Box on their next rebuild until they start an agent or opt in. The release notes
document this as a behavior change.

An older adapter cannot read `FORMAT=2` state and fails closed, so going back to
an older release needs a fresh install identity or a reviewed manual edit of the
state file. This matches the ADR 0007 rule that readers reject formats they do
not recognize.

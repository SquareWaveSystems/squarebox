# ADR 0008: Promote Box replacements transactionally

Status: Accepted

## Context

Rebuild and reset previously removed the canonical Box before its replacement
was created. They also published Install identity before later configuration or
requested provisioning could fail. A handled late failure could therefore leave
Workspace and Managed home intact but no runnable Box, with checkout source,
image alias, configuration, and state describing different attempts.

## Decision

Lifecycle adapters use a prepare/promote transaction for Docker and Podman.

During prepare they resolve and check out the Candidate source, acquire its
image, update installer-owned configuration, create the replacement under a
bounded `<box>-candidate-<install-id>` name, and complete requested provisioning.
The canonical prior Box remains present throughout prepare. Workspace and the
Managed-home volume may be mounted and used, but rollback never copies, deletes,
or reconstructs either data tier.

Promotion is the commit protocol:

1. rename the canonical Box to `<box>-rollback-<install-id>`;
2. rename the validated Candidate to the canonical name;
3. atomically replace `install-state` with the validated Candidate identity;
4. disarm rollback and remove the prior Box.

Before step 3, a handled error restores the prior Box name, source revision,
image alias, host shell integration, and prior state. Candidate resources are
then removed only after their Install-identity label is verified. Cleanup errors
are warnings and never replace the original failure status or diagnostic. If a
runtime rename cannot be completed, the adapter prints the exact candidate,
rollback, and canonical names needed for recovery.

Installer-owned configuration is prepared before promotion so invalid source or
profile content cannot replace a working Box. User-modified configuration is
still preserved by the existing blob trackers. Selection and Managed-home
contents are deliberately outside rollback: provisioning may have made useful
forward changes there, and treating user data as disposable transaction state
would be more dangerous than retaining it.

`SQUAREBOX_FAIL_AT` is a test-only deterministic fault hook at the checkout,
image-alias, Managed-home creation, managed-config, Candidate creation,
provisioning, prior-Box rename, Candidate promotion, and state-publication
boundaries. Both native adapters implement the same named boundaries.

## Crash consistency

Handled rollback is not crash atomicity. A kill, host reboot, or runtime failure
between the two renames and state publication can leave candidate or rollback
names behind. The bounded names and unchanged Install identity make that state
inspectable without guessing, and adapters refuse to overwrite stale transaction
names. Automated discovery and resume/rollback of interrupted operations is a
separate recovery protocol rather than an unsafe inference in this transaction.

## Consequences

Rebuild temporarily consumes space for two Box metadata/layers, while Workspace
and Managed home remain shared. Successful promotion has only the runtime's
short rename interval without a canonical name. Unsupported or failed rename
does not delete the prior Box and produces an actionable recovery path.

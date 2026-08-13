# Fail closed when installing release artifacts

Every artifact installation treats release resolution, exact asset selection,
digest verification, extraction, destination replacement, and cleanup as one
authoritative operation. Image-tier artifacts use Squarebox's pinned SHA-256
manifest. Managed-home GitHub artifacts use the `sha256` digest on the one
exactly named asset of the exact release tag returned by GitHub's Releases API;
missing, duplicate, or malformed metadata fails before artifact download.
Maintainer refresh applies the same exact-asset digest check before publishing
new image-tier pins and checksums; hashing downloaded bytes alone is not enough.
Prepared digests are bound to the Tool identity, metadata caches are private,
and extraction rejects unsafe links, special files, and ambiguous executable
matches. Unsupported architectures and invalid Tool-tier/destination pairings
fail during validation rather than falling through to an amd64 or
non-transactional install path.

Multi-output user installs stage and validate every output before replacing
any destination. They refuse an unexpected destination type instead of moving
and recursively deleting it, and an install-scope lock prevents concurrent
transactions from interleaving outputs. If a later rename or post-install
output fails, the installer rolls all earlier destinations back and returns the
original failure. This is not crash atomicity: process termination or power
loss during a multi-path commit can leave destination-local stages or backups
requiring inspection.

The updater retains Managed-home backups and its install lock until the full
Observed output set and installed version pass post-install verification. A
mismatch rolls the complete output set back. Broken primary probes and missing
Yazi, Helix, or Neovim companion outputs are repairable state, not “current.”

Runtime image-tier updates are applyable only when the Candidate manifest's
exact artifact checksum equals GitHub's digest for the resolved release asset.
A newer upstream release that is not authorized by that manifest requires a
new Candidate and Box rebuild; it is not advertised as an in-place update.
`dpkg` is also outside this rollback guarantee because package maintainer
scripts and the package database can mutate before `dpkg` reports failure.

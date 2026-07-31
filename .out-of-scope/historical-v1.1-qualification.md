# Historical v1.1 qualification work

Squarebox does not treat the open v1.1 qualification briefs as reusable gates
for later Releases.

## Why this is out of scope

Those issues describe one version-specific Candidate and its exact source,
image, asset, and Evidence identity. The immutable v1.1.0 Release is already
published, so missing manual evidence cannot be retroactively attached as
though it authorized those bytes before publication. Re-running the same
checklists now would also not qualify the different source revision and image
digest intended for v1.2.

The historical issues are therefore closed as incomplete rather than marked as
passed. Each new Release gets fresh qualification issues bound to its own
Candidate identity, while the old discussions remain available as an audit
trail.

## Prior requests

- #99 — Validate v1.1 Linux Docker and interactive setup
- #100 — Validate v1.1 rootless Podman on Fedora SELinux
- #101 — Validate v1.1 on macOS Docker Desktop
- #102 — Validate v1.1 Windows PowerShell and Git Bash lifecycle
- #103 — Validate v1.1 Dev Containers and Codespaces
- #105 — Qualify the v1.1 Candidate on physical amd64 and arm64

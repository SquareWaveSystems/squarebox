# Publish immutable release identities

A Release is discoverable only after one Candidate's source revision,
multi-architecture image digest, matched installer assets, and required Evidence
are verified together. Promotion reuses that Candidate identity instead of
rebuilding or discovering an untested raw Git tag.

Repository administrators must keep GitHub immutable releases enabled and the
active, no-bypass `Protect release tags` ruleset on `refs/tags/v*`, blocking tag
updates and deletion while still allowing creation. The immutable-release
settings endpoint requires repository Administration access, which the Actions
`GITHUB_TOKEN` cannot request, so verifying both controls is an operator
prerequisite before creating a release tag. The workflow also checks that the
peeled remote tag still equals the Candidate source during preparation and
again after the approval wait.

For a stable version, maintainers create the final version tag before physical
qualification. The automated gates build that tag once, sign its Candidate
digest and release assets, upload them to a non-discoverable draft GitHub
Release, and verify the downloaded draft assets through the same Release
adapter used by consumers. The workflow then stops at the `v1.1-production`
environment. That environment must have a required human reviewer. Approval is
the authorization to publish those already-prepared bytes; the publication job
downloads and verifies them again after the wait and never rebuilds the image.
If qualification fails, the protected tag is not retargeted: fix the defect and
prepare a new version.

Prerelease tags follow the same build, signing, draft, and verification path,
then publish automatically through the intentionally unprotected
`v1.1-prerelease-auto` environment. Environment protection is repository
configuration, so the stable reviewer rule is a release prerequisite rather
than something this workflow file can enforce by itself.

Publishable versions use `vMAJOR.MINOR.PATCH` with an optional SemVer
prerelease suffix and are at most 128 characters, matching the OCI tag limit.
Build metadata is excluded because `+` is not an OCI tag character and build
metadata has no precedence for choosing one authoritative `latest`.
Final GitHub publication and GHCR alias mutation are serialized across all
tags. Before changing a draft, the workflow calculates whether it is the
greatest stable SemVer and supplies that answer in the one publication update;
an immutable published rerun verifies metadata but never tries to edit it.
Publication must produce GitHub's immutable flag and signed Release attestation
before any convenience alias changes. GitHub's latest Release and GHCR's
`latest` alias identify the greatest published stable version; rerunning an
older tag may repair its own version aliases but must not rewind `latest`. Draft
preparation does not hold that global mutation lock because it creates no
discoverable Release or convenience alias.

# Squarebox v1.2.1 release checks

Automated release assertions are defined in `scripts/e2e-required.tsv` and
reported from exact Evidence by `.github/workflows/e2e.yml`. That automated
Candidate workflow is the v1.2.1 release gate. A per-platform manual
qualification matrix is not required for this release.

Native PowerShell remains a separate adapter and does not claim `SSH_AUTH_SOCK` forwarding;
adapter boundaries are covered by automated/static checks.

Record the Candidate version, source SHA, image digest, and result for any
optional follow-up run.

Release tracker: [v1.2.1 #125](https://github.com/SquareWaveSystems/squarebox/issues/125).
Optional primary-Linux follow-up: [#126](https://github.com/SquareWaveSystems/squarebox/issues/126).
Final Candidate and publication: [#131](https://github.com/SquareWaveSystems/squarebox/issues/131).

## Optional primary-Linux follow-up

- [ ] Fresh Bash installer: launch, interactive setup, exit, resume, rebuild, uninstall
- [ ] Existing v1.1 Managed home upgrade: no repeated prompts; Selections reconcile
- [ ] Genuine host UID/GID other than 1000: default identity, Workspace, and managed files remain host-owned through rebuild and purge
- [ ] Unprivileged Linux PUID/PGID mismatch fails before checkout, config, Install-state, or runtime mutation; a stale recorded identity can be adopted to the current account
- [ ] Root-run rootful Docker/Podman PUID/PGID override starts with lifecycle-managed read-only files mounted beneath `/home/dev`
- [ ] Custom install path, Workspace, and Managed-home volume survive rebuild and purge correctly
- [ ] Purge refuses an unrelated directory/container/image/volume with a colliding name
- [ ] Docker daemon unavailable during uninstall produces a clear nonzero partial-cleanup result

## Candidate promotion

- [ ] Verify the version file, MOTD, Git source ref, and `release.json` agree
- [ ] Confirm the active release-tag ruleset rejects update/deletion of the `v*` tag and that its peeled remote commit still equals the Candidate source SHA
- [ ] Download the non-discoverable draft assets with authenticated `gh release download` and verify their hashes and Cosign identity signature
- [ ] Run the automated Candidate suite and confirm all required Evidence passes
- [ ] Confirm stable installers cannot discover the Release until all gates pass
- [ ] Record the qualification evidence and explicit promote/no-promote decision in [issue #131](https://github.com/SquareWaveSystems/squarebox/issues/131)
- [ ] Approve the waiting `stable-release` environment deployment to publish the tested Candidate without rebuilding different image bytes
- [ ] After publication, run `gh release verify <tag>` and confirm GitHub reports a valid immutable-Release attestation
- [ ] Confirm GitHub Release and GHCR `latest` identify the greatest published stable version
- [ ] Rerun an older stable workflow (or its equivalent dry-run check) and confirm neither `latest` pointer can rewind

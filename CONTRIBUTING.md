# Contributing

Squarebox changes affect host installers, a disposable Box filesystem, a
persistent Managed home, and several runtime adapters. Read `CONTEXT.md` and
the relevant decisions under `docs/adr/` before changing lifecycle behavior.

## Prerequisites

- Docker with Buildx
- Git and Bash
- `jq`
- A current GitHub CLI with `gh release verify`, plus Cosign, when preparing or
  independently verifying a Release
- ShellCheck for local static analysis
- Ruby (YAML parsing) and Go (the pinned actionlint validator)
- PowerShell 7 when changing PowerShell lifecycle adapters
- Podman on a real rootless/SELinux host when changing Podman behavior

## Deterministic tests

Run every executable module test:

```bash
set -euo pipefail
mapfile -t test_files < <(
  find tests -maxdepth 1 -type f -name 'test-*.sh' -perm -u+x | sort
)
test "${#test_files[@]}" -gt 0
for test_file in "${test_files[@]}"; do
  "$test_file"
done
```

Parse tracked Bash scripts and configuration:

```bash
mapfile -t project_files < <(
  git ls-files --cached --others --exclude-standard
)
shell_files=()
for file in "${project_files[@]}"; do
  [ -f "$file" ] || continue
  case "$file" in
    *.sh) shell_files+=("$file") ;;
    *)
      first=$(head -n 1 "$file" 2>/dev/null || true)
      case "$first" in '#!'*bash*) shell_files+=("$file") ;; esac
      ;;
  esac
done
for file in "${shell_files[@]}"; do bash -n "$file"; done
shellcheck --severity=error "${shell_files[@]}"

jq empty .devcontainer/devcontainer.json
ruby -e 'require "yaml"; ARGV.each { |f| YAML.parse_file(f) }' \
  .github/dependabot.yml .github/workflows/*.yml scripts/lib/tools.yaml
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
```

CI runs these checks on every pull request. Tests should cross the same deep
module interface used by production callers. Prefer local fake adapters for
GitHub, runtimes, and filesystems; do not test past the interface by duplicating
implementation steps in a workflow.

## Image and E2E tests

```bash
docker build --build-arg SQUAREBOX_VERSION=dev -t squarebox:test .
docker run --rm \
  -v "$PWD/scripts:/workspace/scripts:ro" \
  squarebox:test bash -c 'scripts/e2e-test.sh smoke'
```

`scripts/e2e-test.sh all` includes network-backed optional tool provisioning;
use `smoke` for the base image. Assertions write machine-readable Evidence when
`SQUAREBOX_EVIDENCE_DIR` is set. The release report refuses missing required
Evidence rather than inferring a pass from job status.

Changes to persistence, setup, ownership, Compose, Dev Containers, Windows, or
Podman must update the automated scenarios where possible and the remaining
manual matrix in `uat-checklist.md`.

## Project structure

| Path | Purpose |
| --- | --- |
| `CONTEXT.md` | Squarebox domain language |
| `docs/adr/` | Hard-to-reverse architecture decisions |
| `Dockerfile` | Default Box image |
| `install.sh`, `install.ps1` | Host lifecycle adapters and Install identity creation |
| `uninstall.sh`, `uninstall.ps1` | Ownership-checked lifecycle cleanup |
| `setup.sh` | Selection/Observed-state reconciliation |
| `scripts/lib/tools.yaml` | Tool metadata and verification policy |
| `scripts/lib/tool-lib.sh` | Verified artifact installation module |
| `scripts/squarebox-update.sh` | Installed-tool update module |
| `scripts/release-identity.sh` | Candidate/Release identity validation |
| `scripts/e2e-evidence.sh` | Assertion Evidence writer |
| `scripts/e2e-report.sh` | Required-Evidence report and gate |
| `tests/` | Deterministic module-interface tests |

## Tool changes

Every registry entry declares its Tool tier and verification policy.

- Image-tier direct downloads use pinned versions and `sha256`; missing or
  mismatched checksums must fail closed.
- Managed-home GitHub release downloads use the SHA-256 digest on the exact
  release asset. Missing, malformed, duplicate, or mismatched digests fail
  before installation mutates the destination.
- Box-tier packages must be reconciled after Box replacement; a saved Selection
  is not proof the package exists.

Use `scripts/update-versions.sh` for image-tier refreshes. It generates and
validates checksums and Dockerfile pins transactionally. Review upstream release
notes and the complete diff before accepting a refresh.

Adding a tool requires updating every behavior represented by registry metadata
or adding metadata so derived inventories remain consistent. Add deterministic
tests for artifact naming on amd64 and arm64, failure propagation, version
probing, installed-state detection, and the intended update lifecycle.

## Release changes

Before creating any release tag, an administrator must verify that immutable
releases are enabled and that the active, no-bypass `Protect release tags`
ruleset targets `refs/tags/v*` with update and deletion protection. The first
check requires repository Administration access and therefore cannot run with
the workflow's `GITHUB_TOKEN`:

```bash
test "$(gh api -H 'X-GitHub-Api-Version: 2026-03-10' \
  repos/SquareWaveSystems/squarebox/immutable-releases --jq .enabled)" = true

ruleset_id=$(gh api repos/SquareWaveSystems/squarebox/rulesets \
  --jq '.[] | select(.name == "Protect release tags" and .enforcement == "active" and .target == "tag") | .id')
test -n "$ruleset_id"
gh api "repos/SquareWaveSystems/squarebox/rulesets/$ruleset_id" | jq -e '
  (.conditions.ref_name.include | index("refs/tags/v*")) != null and
  ([.rules[].type] | index("update")) != null and
  ([.rules[].type] | index("deletion")) != null and
  (.bypass_actors | length) == 0
' >/dev/null
```

Version tags must use `vMAJOR.MINOR.PATCH[-prerelease]`. The Candidate workflow builds and pushes
one multi-architecture digest, attaches SBOM/provenance, scans both architecture
variants, runs exact
assertions, and produces `release.json`. It signs the digest and matched assets,
creates a non-discoverable draft GitHub Release, and verifies the downloaded
draft before publication can run. There is no release rebuild.

Prerelease tags publish automatically after those automated gates. For a stable
release, create the immutable final-version tag before physical qualification,
test the prepared digest and draft assets, then approve the separate
`publish-release` job. Repository administrators must configure
`v1.1-production` with a required human reviewer and leave
`v1.1-prerelease-auto` unprotected. Approval publishes the exact prepared bytes;
if qualification fails, do not retarget or reuse the tag—fix forward with a new
version. The workflow checks the peeled remote tag before draft preparation and
again after approval, then requires GitHub's immutable flag and signed Release
attestation before changing any GHCR alias.

Do not add a second release rebuild, resolve stable from raw tags, or map a
successful job to behavior it did not execute. Keep final GitHub publication
and all GHCR convenience-alias mutations under the shared global concurrency
group so a historical rerun cannot race or rewind `latest`. Determine SemVer
latest before publishing the draft and pass it in that one mutable update;
published immutable reruns must verify metadata without editing it.

## Style

- Shell scripts use `set -euo pipefail` unless a sourced library documents why
  it cannot.
- Existing production shell files use tabs for indentation; preserve local style.
- Every fallible command in integrity and lifecycle code has explicit status
  handling. Do not rely on `errexit` inside conditionals.
- Preserve the original failure when cleanup also runs.
- Use `apply_patch`-sized focused changes and keep unrelated user work intact.

## Pull requests and issues

Keep commits outcome-oriented and explain why the change is needed. Include
tests, Evidence IDs, supported migration behavior, and any remaining manual UAT.

GitHub Issues is the tracker. A ready implementation issue contains reproduction
or design evidence, acceptance criteria, dependencies, and the relevant triage
role from `docs/agents/triage-labels.md`.

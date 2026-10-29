# ADR 0011: Offer an opt-in egress allowlist enforced outside the Box

Status: Proposed

## Context

The Box has unrestricted outbound network access. AI assistants can run
unattended inside it (the `*-yolo` aliases), and they can read the Workspace
and the credentials persisted in the Managed home. Any reachable host is
therefore a path for exfiltrating source, tokens, or conversation history, and
on cloud hosts `169.254.169.254` can hand out instance credentials.

Setting `HTTP_PROXY`/`HTTPS_PROXY` inside the Box is not a control: any process
can ignore those variables. Enforcement only holds if the proxy is the sole
network path out of the Box, and the allowlist lives where Box processes
cannot edit it. NVIDIA OpenShell uses this shape (a per-sandbox network
namespace whose only route is a policy-checking CONNECT proxy).

The Box still has to install and update tools at runtime: `setup.sh`,
`sqrbx-update`, mise SDK backends, npm assistants, the Claude installer, and
Box-tier APT reconciliation all need the network. A mode that breaks them is
not usable.

## Decision

Add an opt-in egress mode selected at install or rebuild time and recorded in
the Install identity:

- `SQUAREBOX_EGRESS=open` (default): current behavior.
- `SQUAREBOX_EGRESS=audit`: all traffic goes through the proxy and is allowed,
  but requests not on the allowlist are logged as would-be denials.
- `SQUAREBOX_EGRESS=allowlist`: requests not on the allowlist are refused.

Native PowerShell takes the same values through `-Egress`. Any other value
fails before lifecycle mutation.

In `audit` and `allowlist` modes the adapter creates, as Managed resources
labeled with the Install identity:

- an `internal` network with no route off the host, which is the Box's only
  network;
- a proxy container attached to both that network and an egress network,
  whose image is pinned by digest in the Candidate like other image inputs.

The Box gets `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` pointing at the proxy for
convenience, but enforcement does not depend on them. The proxy filters
CONNECT and plain HTTP by destination hostname and port. It does not terminate
TLS and never sees request bodies or credentials.

The proxy always refuses loopback, link-local (including `169.254.169.254`),
and unspecified addresses after DNS resolution, whatever the allowlist says.
Private RFC 1918 destinations are refused unless an exact hostname is listed.

The effective allowlist is the union of:

1. a Squarebox-owned default list shipped with the Candidate, covering the
   hosts that Squarebox's own setup, update, and reconcile flows contact
   (derived from `scripts/lib/tools.yaml`, the APT sources, mise backends, the
   npm registry, and supported assistant API hosts);
2. an operator list at `<SQUAREBOX_DIR>/.squarebox/egress-allowlist`, one
   hostname or `*.suffix` pattern per line.

The operator list is mounted read-only into the proxy only. It is never
mounted into the Box and never stored in the Workspace or Managed home, so an
assistant cannot widen its own access. Proxy logs are readable from the host
with a lifecycle command (for example `sqrbx-egress log`).

The Box must not resolve external names directly; the proxy resolves them.
Acceptance tests must show that DNS lookups, direct IP connections, and
non-proxied TCP from inside the Box all fail in `allowlist` mode.

Recording the mode requires a new Install identity format under ADR 0007:
`FORMAT=3` appends `EGRESS=open|audit|allowlist`. `FORMAT=2` and `FORMAT=1`
records read as `EGRESS=open`. The verifier and shared fixtures cover every
accepted format in all four adapters.

## Consequences

This makes egress a security control for operators who choose it, but the
SECURITY.md posture is unchanged: the Box remains a development environment,
not a hostile-code sandbox. Allowed hosts are still exfiltration paths. Most
code-hosting and package registries accept arbitrary uploads, and an agent with
a GitHub token can push data to any repository that token can write.

Host-level filtering cannot restrict HTTP methods or paths, and cannot keep
credentials out of the Box. Both would need TLS termination with a per-Box CA,
which this ADR rejects as too invasive for a development environment.

Every new tool, SDK backend, or assistant can need a default-list update.
`audit` mode is the migration path: operators run in `audit`, review the
would-be denials, and then switch to `allowlist`.

Compose and the Dev Container need equivalent definitions. GitHub Codespaces
controls its own networking, so this mode is not offered there.

Rootless Podman needs internal-network and proxy coverage on Ubuntu CI and
manual UAT on Fedora with SELinux enforcing, as for other Podman changes.

# Mechanically verify one Install identity schema

## Context

The four lifecycle adapters must read the same closed `FORMAT=1` field set and
enforce equivalent shared constraints. They run in different bootstrap
environments: Bash and native PowerShell must validate existing state before a
checkout or optional parser is available. Their path and profile values are
adapter-native and, under format 1, only the creating adapter may consume them.

Duplicating native parsers is therefore necessary, but manually duplicating the
contract is not. Field-list checks alone previously missed semantic drift: Bash
accepted repeated path separators that native PowerShell rejected as
non-normalized.

## Decision

`scripts/lib/install-state-schema.json` is the authoritative format-1 contract.
It owns canonical field order and names the shared semantic rules. The install
and uninstall adapters retain self-contained native readers and validators; no
runtime lifecycle operation depends on Python, JSON tooling, a checkout, or
generated code.

`scripts/verify-install-state-schema.py` mechanically verifies all four native
readers, both writers, and the implementation anchors for shared rules. The
lifecycle fixture suites exercise valid and adversarial state through the real
adapters. CI must run both the verifier and those fixtures, so changing the
schema, a writer, or a native validator independently fails closed.

Format 1 remains a data-only `KEY=VALUE` record. Readers reject unknown,
missing, duplicate, malformed, unsafe, or semantically inconsistent data and
never source or evaluate it. CRLF input remains readable. Field names and shared
constraints are cross-adapter contracts; path syntax, path case comparison, and
shell-profile values remain creator-adapter contracts.

Before adding any field or changing its meaning, maintainers must introduce a
new format, document its migration and ownership rules in an ADR, add
cross-language fixtures, and preserve explicit format-1 compatibility. A
format-1 reader must reject an unrecognized future format rather than infer it.

## Consequences

The bootstrap adapters stay portable and reviewable in their native languages.
The repository gains one review surface for schema evolution and CI detects
hand-diverged field sets, writer order, and shared invariant implementations.
Semantic behavior still needs executable fixtures; static verification is not
treated as proof that a native parser behaves correctly.

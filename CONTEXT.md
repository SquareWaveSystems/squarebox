# Squarebox

Squarebox is a portable, containerized development environment whose installation, persistent user state, optional tools, and published releases must behave as one managed system across Docker, Podman, Compose, and Dev Containers. Published Candidate bytes are immutable by digest; rebuilding mutable base/APT inputs is not promised to reproduce those bytes.

## Language

**Box**:
A runnable Squarebox development environment made from an image, persistent home, workspace, and managed configuration.
_Avoid_: Container, sandbox, instance when referring to the complete user environment

**Candidate**:
An exact source revision, multi-architecture image digest, and matched installer assets being evaluated for publication.
_Avoid_: Build, tag when the complete releaseable identity is meant

**Release**:
A Candidate that passed its required evidence and is discoverable through published release metadata.
_Avoid_: Raw tag, latest commit

**Install identity**:
The durable record of the runtime, paths, resource names, source revision,
host identity, and observed image identity managed by one Squarebox
installation. Release pulls record an immutable digest; source/edge builds
record their local image ID and reference.
_Avoid_: Installer environment, defaults

**Managed resource**:
A file, directory, container, image reference, or volume whose ownership by an Install identity has been recorded and verified.
_Avoid_: Any resource with a familiar fixed name

**Managed home**:
The persistent user-home volume that survives Box replacement and holds user-owned configuration, authentication, toolchains, and history.
_Avoid_: Home directory when persistence semantics matter

**Workspace**:
The host-owned project tree exposed inside a Box for development work.
_Avoid_: Squarebox state directory

**Selection**:
A user's desired optional tools, SDKs, multiplexers, and shell for a Box.
_Avoid_: Installed state

**Observed state**:
The tools and generated configuration actually present and usable in the current Box and Managed home.
_Avoid_: Saved Selection

**Evidence**:
A machine-readable assertion emitted by the exact scenario that exercised a release requirement.
_Avoid_: Green job, inferred pass

**Tool tier**:
The lifecycle that owns a tool: image tier, Box tier, or Managed-home tier.
_Avoid_: Core/optional when update and persistence behavior is meant

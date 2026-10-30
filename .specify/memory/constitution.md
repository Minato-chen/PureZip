<!--
Sync Impact Report
- Version change: (template, unversioned) → 1.0.0
- Modified principles: all template placeholders replaced (initial ratification)
- Added principles:
  I. Clean-Room Implementation (NON-NEGOTIABLE)
  II. Stop Boundaries
  III. Streaming & Constant Memory
  IV. Volume-Family Naming Consistency
  V. Extension Independence
  VI. Compact, Truncation-Safe UI
- Added sections: Open Source & Legal Constraints; Development Workflow & Quality Gates; Governance
- Removed sections: none
- Templates: plan/spec/tasks templates read the constitution at runtime; no edits required
- Follow-up TODOs: none
-->

# PureZip Constitution

## Core Principles

### I. Clean-Room Implementation (NON-NEGOTIABLE)

PureZip learns from the best features of other archive tools, but every line of code and every
asset MUST be original work.

- Decompiled code, disassembly, pseudo-code, or code "translated" from third-party closed-source
  binaries MUST NOT be committed, pasted, or used as a direct reference while writing code.
- Third-party proprietary binaries, icons, images, UI assets, sounds, copy text, and localization
  strings MUST NOT be included in the repository or in shipped builds.
- Analysis of other products (including reverse-engineering work done with REA tooling) MAY only
  produce **behavioral descriptions**: what a feature does, how users interact with it, and
  file-format facts needed for interoperability. These descriptions go into `spec.md`.
- Implementation MUST be written from the spec, not from analysis artifacts. Raw analysis output
  (decompiled listings, dumps, captures) MUST stay outside the repository.
- Open-source code MAY be reused only when its license is compatible with the project license,
  with attribution and license text preserved.
- Public docs, README, release notes, and marketing MUST NOT claim that features were
  "reverse-engineered from" a named product, and MUST NOT use competitors' trademarks except for
  factual compatibility statements (e.g. "opens RAR archives").

Rationale: features and interaction ideas are not copyrightable, but code and assets are. A
documented spec-first, clean-room process keeps the open-source project legally defensible.

### II. Stop Boundaries

Before changing any local area (a dialog layout, a single engine call), the change boundary MUST be
assessed. Local fixes MUST NOT break main-window lifecycle, Capsule/Desk dual-mode switching, or
Finder communication.

### III. Streaming & Constant Memory

All new file reading, hashing, text extraction, and stream processing MUST use `FileHandle` or
chunked streaming. Loading whole files into memory is prohibited.

### IV. Volume-Family Naming Consistency

Every extraction flow MUST derive output names through `ArchiveVolumeFamily`. Raw volume names
such as `.001` MUST NOT be used as folder names.

### V. Extension Independence

App Extension entry points (`PureZipFinderSync`, `PureZipQuickLook`) MUST be owned solely by
`NSExtensionMain()`. Blocking code or independent run loops MUST NOT be introduced.

### VI. Compact, Truncation-Safe UI

The Pure Capsule floating window height stays locked around 440 pt. All buttons MUST carry
`.lineLimit(1)` and `.fixedSize()` protection across languages and window sizes so CJK text never
wraps or truncates.

## Open Source & Legal Constraints

- The project is distributed as open source; every dependency's license MUST be recorded and be
  compatible with the project license (watch LGPL/GPL obligations, e.g. 7-Zip/p7zip components).
- Archive-format support MUST rely on public specifications, open-source libraries, or
  interoperability analysis documented as behavior/format facts per Principle I.
- The product name is "PureZip" (with sub-features `Pure Shelf`, `Pure Capsule`, `Pure Desk`, and
  `Pure Actions`) across code, bundle identifiers, UI, and docs. Legacy or external names MUST NOT
  appear in source, UI strings, or shipped artifacts.

## Development Workflow & Quality Gates

- New features follow the Spec Kit flow: `speckit-specify` → `speckit-plan` → `speckit-tasks` →
  `speckit-implement`. Specs describe behavior only and cite no decompiled material.
- Every plan MUST include a Constitution Check confirming: no third-party code/assets, license
  compatibility of new dependencies, streaming memory use, and extension independence.
- Code review MUST reject any change containing decompiled/derived code, unlicensed assets, or
  public wording that violates Principle I.

## Governance

This constitution supersedes other practices, including the red-line section of `README.md`.
Amendments require a documented change to this file with a version bump:
MAJOR for removing or redefining principles, MINOR for adding principles or materially expanding
guidance, PATCH for clarifications. All reviews and plans MUST verify compliance; any deviation
MUST be justified in the plan's Complexity Tracking.

**Version**: 1.0.0 | **Ratified**: 2026-10-30 | **Last Amended**: 2026-10-30

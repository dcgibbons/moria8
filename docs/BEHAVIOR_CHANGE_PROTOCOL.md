# Behavior Change Protocol

Load this document only for gameplay, lifecycle, generation, rendering, or
C128 memory/banking changes routed here by `AGENTS.md`.

## Risk Tier

Choose the smallest tier that fits:

| Tier | Trigger | Required record |
| --- | --- | --- |
| Routine/local | Implementation under a settled contract; no state-transition, lifecycle, representation, RNG or ownership change | Success criterion, affected invariant, focused verification |
| Behavioral | State transition, numeric formula, RNG behavior, lifecycle or shared gameplay semantics changes | Full change record below |
| Architectural | Cross-domain pipeline, memory/banking, loader, copied code, platform ownership or contract change | Full record plus applicable verification rows from every matching domain contract |

Escalate tiers when investigation reveals broader effects. Routine work does not
require ceremonial `N/A` entries.

## Authority Precedence

Explicit current-task user direction governs requested product behavior unless
it conflicts with higher-level instructions. A requested change to shipped or
committed product behavior is durable by default: update any affected settled
ledger rule before implementation. Directions about task scope, investigation,
or implementation procedure are task-local and do not change product policy.
If the maintainer explicitly labels a behavior experiment temporary, record it
only in the change record; it must not be merged or declared complete under the
settled contract unless the maintainer later approves it as durable.

For gameplay semantics:

1. accepted Moria8 decision in the applicable domain contract
2. explicit Moria8 design/deviation document linked by that contract
3. VMS Moria as the default upstream gameplay oracle
4. Umoria when VMS Moria is unclear or materially divergent
5. current implementation and tests as evidence, not silent specification

For platform mechanics, use hardware constraints, executable ownership/layout
assertions, accepted Moria8 decisions, then implementation/runtime evidence.
VMS Moria and Umoria are not authorities for Commodore banking, VDC, loaders or
physical rendering.

Pinned upstream revisions used by this repository:

- VMS Moria: `https://github.com/dungeons-of-moria/vms-moria`, revision
  `adce6c8898ea280181f1277b47f104e2b1f387a8`
- Umoria: `https://github.com/dcgibbons/umoria`, revision
  `2a2a6b791f084cac97db85f5b78739e913dd3572`

When upstream consultation is required and no checkout at the verified revision
is available, acquire one outside this repository so it cannot pollute source
status:

```sh
UPSTREAM_ROOT="${UPSTREAM_ROOT:-../moria8-upstream}"
mkdir -p "$UPSTREAM_ROOT"
git clone https://github.com/dungeons-of-moria/vms-moria.git "$UPSTREAM_ROOT/vms-moria"
git -C "$UPSTREAM_ROOT/vms-moria" checkout adce6c8898ea280181f1277b47f104e2b1f387a8
git -C "$UPSTREAM_ROOT/vms-moria" cat-file -e adce6c8898ea280181f1277b47f104e2b1f387a8^{commit}
git clone https://github.com/dcgibbons/umoria.git "$UPSTREAM_ROOT/umoria"
git -C "$UPSTREAM_ROOT/umoria" checkout 2a2a6b791f084cac97db85f5b78739e913dd3572
git -C "$UPSTREAM_ROOT/umoria" cat-file -e 2a2a6b791f084cac97db85f5b78739e913dd3572^{commit}
```

Domain ledgers are authoritative for deliberate Moria8 deviations and for
resolutions of open or disputed project choices. Upstream, hardware, and
mathematical invariants may instead cite their primary authority directly.
Update a ledger when changing a settled project rule or resolving an open
choice, not for every repair that restores an existing rule. A ledger row must
name an ID, owner, date, scope, selected rule, evidence, enforcement, and any
superseded decision. A commit or PR link is provenance, not durable policy.
An `Accepted` row must also identify approval provenance: an explicit
maintainer decision recorded by the row, a linked design/issue, or a superseding
accepted row. "Explicit design approval" means one of those durable artifacts,
not agent inference.

## Required Change Record

Complete applicable fields for behavioral and architectural changes before
implementation. Mark safety-critical irrelevant fields `N/A` with evidence.

```text
Problem and success criteria:
State being changed:
Search scope and terms:
Relevant readers/writers found and known exclusions:
Initialization, reset and persistence points:
Affected production sequence through the changed transition:
Contract decision or selected upstream oracle with source locations:
Intentional Moria8 deviations:
Input/intermediate widths, signedness, carry, range and overflow policy:
RNG reduction and bias, if applicable:
Affected platforms, overlays, banks and owners:
Required production-path tests:
Known behavior explicitly out of scope:
Unresolved uncertainty and risk:
```

Unknowns that could change semantics, representation, ownership, memory safety,
or verification block implementation. Other uncertainty may remain only when
its risk is explicit. Do not claim global completeness.

For multi-part repairs, stabilize and verify one contract-level transition at a
time. Do not combine unrelated semantics merely because they share a module.

## Verification Rules

- Add a failing behavioral/lifecycle test before or alongside the fix where
  practical.
- At least one regression must execute the changed production routine through
  its real dispatch, trampoline, overlay, banking and renderer path as relevant.
- A test-local copy proves harness behavior only.
- Select normal, boundary, negative, overflow/underflow and stale-state cases
  according to affected invariants. Explain omitted apparently relevant cases.
- Assert transitions and invariants, not only messages or glyphs.
- Shared code or shared-contract changes require affected-platform parity or an
  evidence-based exemption.
- Every assertion encoding changed semantics must cite a contract decision,
  upstream fixture/trace, or independent mathematical invariant. A captured
  production regression may prove execution and preserve a reproduction, but
  its expected result must still derive from one of those semantic authorities.
  A helper copying the product formula is not an independent oracle.
- Run focused tests during iteration and the authoritative affected-platform
  gates before completion.
- For filtered commands, confirm the output names the expected suites and
  reports a nonzero selected total. A successful zero-suite run is not evidence.
- Review the complete final diff against the change record and domain contract.

## Enforcement Boundary

Prose cannot prove compliance. Existing assembler assertions and runtime suites
remain executable gates. New mechanically checkable invariants should become
assertions or tests in the same change; do not leave them only in documentation.
Adding a repository-wide manifest/CI checker is a separate infrastructure task,
not permission to expand an unrelated product fix.

Current process-enforcement gaps:

| Requirement | Status |
| --- | --- |
| Automatic validation that changed files were routed to every applicable contract | `NOT IMPLEMENTED` |
| Automatic validation that the required change record is complete | `NOT IMPLEMENTED` |
| Automatic validation that a settled decision change updated its ledger | `NOT IMPLEMENTED` |
| Automatic proof that cited tests execute the production path rather than a test-local copy | `NOT IMPLEMENTED` |
| Harness-wide rejection of a filtered run selecting zero suites | `NOT IMPLEMENTED`; verify suite names and nonzero totals manually |

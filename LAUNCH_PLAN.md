# Moria8 Public Launch Plan

This plan outlines the steps to transition the private `moria8` repository into a clean, public-facing, BFDL-led project. The goal is to maximize technical signal and remove all social/process noise.

## 1. Documentation Restructuring
- [ ] Create `/docs` directory.
- [ ] Move `commodore/ARCHITECTURE.md` to `/docs/ARCHITECTURE.md`.
- [ ] Move `commodore/DESIGN.md` to `/docs/DESIGN.md`.
- [ ] Consolidate C128 architecture details from `commodore/c128/ARCHITECTURE.md` into `/docs/ARCHITECTURE.md`.

## 2. Internal Mandates (Agent & Technical Hub)
- [ ] Create `docs/INTERNAL_MANDATES.md` as the unified technical "Source of Truth."
- [ ] Consolidate all hardware invariants (Zero Page ownership, segment boundaries, I/O hole restrictions) from the various `GEMINI.md` files and `ARCHITECTURE.md`.
- [ ] Consolidate all AI agent instructions (Plan Mode, Verification Gates, Subagent Strategy) from `AGENTS.md` and `.clauderules`.
- [ ] This file is for developers and AI agents to ensure architectural integrity without cluttering the project root.

## 3. Root Sanitization (The "Spartan" Tree)
- [ ] **README.md**: Rewrite to be 100% technical and user-focused.
    - Remove "AI Team Instructions."
    - Focus on game mechanics, build instructions (`make`), and hardware requirements (C64/C128).
- [ ] **Delete**:
    - `GEMINI.md` (Root)
    - `AGENTS.md`
    - `.clauderules`
    - `commodore/c128/GEMINI.md`
    - `commodore/common/GEMINI.md`
- [ ] **No CONTRIBUTING.md / No Code of Conduct**: Total silence on social/process rules. The project follows a BFDL (Benevolent Dictator For Life) model — the project lead (Chadwick) has final authority on all technical decisions.

## 4. Cleanup & Sanitization
- [ ] **Delete Ephemeral Logs**:
    - `BUILDPLAN.md`
    - `BUILDPLAN_HISTORY.md`
    - `commodore/c128/10.7_plan.md`
    - `commodore/c128/10.8_plan.md`
    - `commodore/c128/C2_PLAN.md`
    - `commodore/c128/C4_PLAN.md`
- [ ] **Path Scan**: Verify that the `Makefile` and `tools/` do not contain any hard-coded local paths (e.g., `/Users/chadwick/`).

## 5. Release Infrastructure
- [ ] **CHANGELOG.md**: Create a technical log for public versioning.
- [ ] **RELEASE_CHECKLIST.md**: Create in `/docs` to guide the manual production of `.d64` and `.d71` binary releases.

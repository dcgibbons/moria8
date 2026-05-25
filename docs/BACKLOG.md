# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Commodore Ports

### Audit screen clear and shared-screen ownership paths

The Home screen currently reuses the store renderer, then overrides the store
footer. That produced stale footer text such as `Q)uituit` because the store
renderer drew row 18 first and Home replaced it with shorter text afterward.
The immediate fix clears row 18 before drawing the Home footer, but the cleaner
design is to stop making Home call a renderer that draws the wrong footer in the
first place.

Required work:

- Split shared store/Home drawing so the item/body layout and footer/menu
  drawing have separate ownership.
- Replace local row-clearing patches with explicit draw contracts where a view
  owns each row it writes.
- Audit all screen clear, row clear, modal redraw, and overlay redraw paths
  across C64, C128, and Plus/4 for similar stale-text or inherited-state
  behavior.
- Pay special attention to code that writes shorter text over longer text,
  reuses another view's renderer, or relies on prior full-screen clears to make
  later partial redraws safe.
- Add focused regression coverage for any discovered cases where stale text,
  color residue, or previous-view state can survive a redraw.

Acceptance target:

- Screen redraw behavior is owned by explicit view contracts, not incidental
  cleanup, and no UI path depends on hidden stale-text assumptions.

### Friendlier Commodore I/O error messages

The current storage HAL diagnostics preserve useful raw data, but the in-game
error text is still too developer-oriented on space-constrained targets. For
example, `Disk error! 74` correctly reports the drive status code, but it should
also tell a player that the drive is not ready and what to check.

The C64 bootloader has an even earlier version of this problem: it hardcodes
the program disk to device 8, so booting with the disk attached as drive 9 can
fall back to BASIC with no useful explanation before the main game's disk setup
or storage diagnostics exist.

Required work:

- Add a compact C64 bootloader error path for main-program load failure that
  tells the player to attach the boot disk as drive 8, or otherwise reports a
  clear load failure before returning to BASIC.
- Keep raw diagnostic bytes available: DOS status, KERNAL `$ST`, phase, and
  device number.
- Add a compact platform-owned classifier that maps common storage failures to
  player-facing text.
- Preserve the raw fallback for unmapped failures so debugging does not regress.
- Avoid bloating resident code or destabilizing C64/C128 storage behavior.
- Cover C64, C128, and Plus/4 with storage-error tests or smoke cases.

Acceptance target:

- Common failures such as no disk/drive not ready, write protect, disk full,
  missing file, and wrong save disk show clear end-user messages while retaining
  enough diagnostic detail for debugging.

### Promote `V` to an in-game Version/System Info command

The C64 product currently has a hidden `V` diagnostic command for proving C64
Ultimate turbo behavior. That key was previously unused in gameplay and maps to
the dormant `CMD_VERSION` command slot. This should eventually become a real
cross-platform Version/System Info command instead of a one-off C64U probe.

The command is likely text-heavy enough to justify a platform-owned overlay or
paged modal rather than forcing all details into resident message-line code.

Required work:

- Define the shared `V` command behavior across C64, C128, and Plus/4.
- Show game version/build identity, platform, save-format version, and relevant
  runtime hardware details.
- On C64, include machine identity, KERNAL revision, REU size, C64 Ultimate
  detection, turbo-register availability, and optionally the measured turbo
  probe result.
- On C128 and Plus/4, show platform-appropriate equivalents without implying
  unsupported C64U/REU capabilities.
- Decide whether the implementation lives in an existing UI overlay or a new
  dedicated diagnostics/version overlay.
- Preserve the current hidden C64U timing probe until it is replaced by the
  polished command.
- Add focused tests for command routing and platform-specific displayed fields.

Acceptance target:

- Pressing `V` in gameplay opens a clear Version/System Info view on every
  supported Commodore platform, with enough diagnostic detail for user support
  and hardware-feature verification.

### Investigate C64U SoftwareIEC fast runtime asset loading

Hardware testing showed that C64U SoftwareIEC/UCI fast-loading is not safe
enough to ship. Early REU preload experiments appeared dramatically faster, but
later real-hardware tests produced corrupted dungeon/runtime assets: unknown
monster names rendered as `?`, and changing dungeon levels could show a
checkerboard-corrupted screen with overlay filenames such as `64.start`,
`64.town`, and `64.spell`.

Boot-time UCI `LOAD_SU` was also tested against a loose-file C64U package on
USB. BASIC could load `UCIPROBE` from SoftwareIEC device 11, proving the visible
SoftwareIEC directory was correct, but UCI `LOAD_SU` returned status `$01`
(`FILE NOT FOUND`) for all tested request forms, including `MORIA64`,
`UCIPROBE`, and `$`. This means BASIC device-11 visibility does not imply that
UCI target `$05` can resolve the same file context on the tested C64U
configuration/firmware.

Observed monitor state while testing:

```text
m 0852 0856
0852: 0B 00 00 00 0C
```

Required work:

- Prefer hyperspeed KERNAL/JiffyDOS-style loading on C64U instead of UCI
  `LOAD_SU`/`LOAD_EX` unless new firmware documentation or example code proves a
  working path.
- Keep the product runtime loader on the known-good KERNAL path.
- If UCI loading is revisited, start from a standalone probe that validates both
  file resolution and byte-for-byte RAM/REU contents against known-good
  KERNAL-loaded data before enabling it in product.
- Confirm the exact command sequence, status handling, response acceptance, DMA
  mode, target address behavior, banking state, and SoftwareIEC filesystem
  context on real C64U hardware.
- Add an explicit hardware-test checklist covering REU preload, dungeon
  transition, visible monster names, stores, spells, and overlay-heavy actions.

Acceptance target:

- C64U SoftwareIEC/UCI loading is only re-enabled after real hardware shows
  working file resolution, clean byte validation, and normal gameplay across
  runtime overlay/tier transitions. Until then, C64U acceleration should use the
  hyperspeed KERNAL path.

### Expand monster catalog toward full Umoria roster

Moria8 currently ships with 120 selected creatures from Umoria's 279-creature
catalog. Expanding toward the full roster requires more than adding data files.

Required work:

- Redesign creature tier partitioning beyond the current four dungeon tiers.
- Add stable global creature IDs instead of relying only on active-tier-local
  creature indices.
- Rework monster recall persistence around global creature identity.
- Adjust C128 tier cache/preload ownership or switch to selective tier loading.
- Review C64 disk/REU tier loading for larger or more numerous tier files.
- Expand imported monster attack/spell behavior where current mappings collapse
  Umoria effects into simplified Commodore behavior.

Acceptance target:

- Full or substantially expanded Umoria creature roster can appear at the
  appropriate dungeon depths without breaking C64/C128 memory, loading, save,
  recall, or monster behavior contracts.

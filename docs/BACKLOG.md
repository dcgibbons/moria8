# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Commodore Ports

### Friendlier Commodore I/O error messages

The current storage HAL diagnostics preserve useful raw data, but the in-game
error text is still too developer-oriented on space-constrained targets. For
example, `Disk error! 74` correctly reports the drive status code, but it should
also tell a player that the drive is not ready and what to check.

Required work:

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

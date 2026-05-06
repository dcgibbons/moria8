# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Commodore Ports

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

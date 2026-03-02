# Moria8 C128 — Plan C4 Tasks

## Phase C4: Resolve Map/Program Collision

- [x] **C4.0 Baseline Snapshot**
    - [x] Record memory layout and padding.
    - [x] Document risks and identified failure modes.
    - [x] Output `C4_BASELINE.md`.
- [x] **C4.1 Add C128 Banking Test Harness**
    - [x] Create `test_memory128.s`.
    - [x] Create `test_dungeon128.s`.
    - [ ] Create `test_monster128.s`.
    - [x] Create `run_tests128.sh`.
    - [x] Add `make test128` target.
- [x] **C4.2 Introduce MMU Primitives With IRQ-State Preservation**
    - [x] Implement `mmu_select_bank1`, `mmu_select_bank0`.
    - [x] Ensure `php/sei/plp` or `bit $01` / `bne` IRQ preservation.
- [ ] **C4.3 Relocate Map Constants Only**
    - [ ] Move `MAP_BASE` to `$4000` in Bank 1 (C128 only).
    - [ ] Update `MAP_END`.
- [ ] **C4.4 Migrate Map Access Paths to Atomic Wrappers**
    - [ ] Add `map_get_tile` and `map_set_tile` in `common/dungeon_data.s` or `memory128.s`.
    - [ ] Convert direct `MAP_BASE,x` or `(zp_ptr0),y` accesses.
- [ ] **C4.5 Add Bulk Map Helpers and Replace Hot Loops**
    - [ ] Implement `map_clear_all`, `map_fill_rect`.
- [ ] **C4.6 Bootloader and Common-RAM Validation**
- [ ] **C4.7 Stress and Soak**
- [ ] **C4.8 Documentation Lock**

# DESIGN_PLAN.md — Item Selection and Filtering Re-indexing

## 1. Objective
Align item selection (letters) and filtering behavior with the original Moria (VMS/UMoria) projects to improve usability and provide an "authentic" feel.

## 2. Current vs. Target Behavior

### 2.1 Equipment
- **Current:** Uses fixed letters A-H corresponding to absolute equipment slots 22-29.
- **Target:** Re-index letters `a`, `b`, `c`, etc., based only on **non-empty** slots.

### 2.2 Filtered Inventory (The Pack)
- **Current:** Uses fixed letters A-V based on absolute pack slots 0-21. Filtered views (e.g., "Quaff which potion?") skip non-matching items but keep their original letters (e.g., `B) Potion`, `F) Potion`).
- **Target:** Filter the letters down to a contiguous sequence (`a`, `b`, `c`...) when a filter is active, mapping them back to the underlying physical slots.

## 3. Proposed Changes

### 3.1 Equipment Re-indexing
- **File:** `commodore/common/ui_inventory.s`
    - Update `ui_equip_display` to maintain a separate "display letter" counter.
    - Only increment and print the letter for non-empty slots.
- **File:** `commodore/common/player_items.s`
    - Update `item_takeoff` and other equipment-selection routines.
    - Instead of `sbc #$41` (direct mapping), iterate through equipment slots to find the *n-th* non-empty slot matching the user's input.

### 3.2 Filtered Inventory Re-indexing
- **File:** `commodore/common/ui_inventory.s`
    - Update `ui_inv_display` to use a contiguous letter sequence (`a`, `b`, `c`...) when `uinv_filter` is active.
- **File:** `commodore/common/player_items.s`
    - Update `item_quaff`, `item_read`, `item_use`, `item_aim`, `item_wear`, etc.
    - When a filter is active (usually indicated by the command context), map the user's input letter to the *n-th* item in the inventory that passes the filter.

### 3.3 Inventory Sorting/Compaction (Optional)
- **File:** `commodore/common/item.s`
    - If full "original" behavior is desired, implement `inv_sort_pack` and ensure `inv_add_item` / `inv_remove_item` keep the pack compact.
    - *Decision:* Defer full sorting/compaction for now to minimize risk to the stable `inv_add_item` logic, focusing on the UI/mapping layer first.

## 4. Verification Plan

### 4.1 Automated Tests
- **New Test File:** `commodore/common/tests/test_ui_indexing.s` (or add to `test_item.s`).
- **Test Cases:**
    1. Wear only a shield (slot 24); verify `Take Off` shows it as `a)`.
    2. Have potions in slots 1 and 5; verify `Quaff` shows them as `a)` and `b)`.
    3. Verify selecting `b)` in the filtered `Quaff` view correctly selects the potion in slot 5.
    4. Verify selecting `a)` in the `Take Off` view correctly selects the shield in slot 24.

### 4.2 Manual Verification (VICE)
- Create a character, acquire a single piece of equipment (not a weapon), and verify it is labeled `a)` in the equipment screen.
- Acquire two non-contiguous potions, use the `q` command, and verify they are labeled `a)` and `b)`.
- Ensure `?` (inventory list) during a command correctly reflects the re-indexed letters.

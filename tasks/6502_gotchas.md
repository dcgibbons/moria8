# Common 6502 Assembly Gotchas

Working in 6502 assembly requires a lot of manual bookkeeping, making it easy to introduce subtle bugs. Here are some of the most common gotchas and pitfalls you'll encounter in 6502 programming.

### 1. The `BIT` Instruction Clobbering Flags
The `BIT` instruction is extremely useful because it tests memory against the accumulator without modifying the accumulator. However, `BIT` *always* sets the Overflow (`V`) flag and the Negative (`N`) flag based on bits 6 and 7 of the target memory location, respectively—regardless of what is in the accumulator.
* **The Bug:** Doing a `BIT` test right before a `BVC`/`BVS` or `BPL`/`BMI` branch that was relying on an earlier state, thinking `BIT` only affected the Zero (`Z`) flag.

### 2. Forgetting to clear/set Carry before Arithmetic
The 6502 only has `ADC` (Add with Carry) and `SBC` (Subtract with Carry). There are no basic `ADD` or `SUB` instructions.
* **The Bug:** Forgetting to explicitly use `clc` (Clear Carry) before an `ADC` or `sec` (Set Carry) before an `SBC`. If the carry flag happens to be set from a previous operation (like an unrelated `CMP`), your math will be off by 1.

### 3. Pushing and Pulling Out of Order or Imbalanced
The 6502 stack is relatively small (256 bytes) and has no automatic frame pointers.
* **The Bug:** Pushing registers to the stack (e.g., `pha`, `txa`, `pha`, `tya`, `pha`) but pulling them back in the wrong order or forgetting a pull on early return paths. This immediately corrupts the return address for `rts`, causing the CPU to jump to a random memory address and crash (JAM).

### 4. Overwriting Zero Page Pointers
Zero Page (ZP) addresses (`$00`-`$FF`) are essential because they are the only way to do indirect indexed addressing (e.g., `lda (zp_ptr),Y`).
* **The Bug:** A subroutine uses a shared zero page pointer (like `$fb`/`$fc`) but calls another subroutine (or gets interrupted by an IRQ) that also uses that *exact same* zero page pointer. When control returns, the pointer has changed.
* **The Fix:** Strict discipline about which routines own which ZP addresses, or saving/restoring them to the stack if they must be shared.

### 5. Branching out of Range
The 6502 conditional branches (`BNE`, `BEQ`, `BCC`, `BCS`, etc.) use relative addressing and can only jump between -128 and +127 bytes.
* **The Bug:** Writing a huge subroutine where a `BNE` needs to jump 150 bytes away. The assembler will throw a "Branch out of range" error, forcing you to rewrite the logic using a trampoline (e.g., branching over a massive `JMP` instruction).

### 6. Off-by-One in `Y` Index Loops
When copying blocks of data, developers usually loop backwards because the `BNE` (Branch on Not Equal) automatically triggers when `Y` hits 0.
```assembly
    ldy #$10
!loop:
    lda source,y
    sta dest,y
    dey
    bne !loop-
```
* **The Bug:** The loop terminates immediately when `Y` reaches 0, meaning the byte at index 0 is *never copied*.
* **The Fix:** If you need to copy 0-indexed data upwards, use `cpy #MAX \ bne`. If going downwards including 0, you must `dey \ bpl` or use a slightly offset source/dest pointer.

### 7. Missing `#` for Immediate Values
* **The Bug:** Writing `lda 5` instead of `lda #5`.
* **The Result:** Instead of putting the number 5 into the accumulator, the CPU fetches whatever value is stored at memory address `$0005`. This is insidious because `$0005` might happen to hold a value that makes the code *appear* to work sometimes!

### 8. The Indirect JMP Page Boundary Bug (Original Hardware Bug)
If you use the indirect jump instruction exactly on a page boundary (e.g., `JMP ($12FF)`), you would expect it to read the jump vector from `$12FF` and `$1300`.
* **The Bug:** Due to a hardware design flaw in the original NMOS 6502, it actually reads from `$12FF` and `$1200` (it wraps around the same page instead of incrementing the high byte). While modern assemblers often warn about this, it can lead to devastating crashes if computed at runtime.

### 9. Decimal Mode Not Cleared
The 6502 supports BCD (Binary Coded Decimal) math when the Decimal (`D`) flag is set.
* **The Bug:** Interrupts (like the NMI) don't automatically clear the Decimal flag on the original 6502. If an interrupt fires while the main code is doing decimal math, the interrupt handler will also do decimal math unless it explicitly uses `cld`. Likewise, if main code forgets to `cld` after doing score calculations, all subsequent standard hex `ADC`/`SBC` math will break.

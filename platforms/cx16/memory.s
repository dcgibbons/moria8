#importonce
// memory.s - Commander X16 memory and bank macro contract.
//
// CX16 does not have C64-style hidden RAM under KERNAL ROM. These macros are
// currently no-ops so shared code can assemble while CX16 tier storage is still
// being wired to the machine's RAM-bank model.

.const BANKED_DATA_BASE = $e000
.const BANKED_DATA_END  = $ffff
.const BANK1_DB_BASE    = $e000
.const MAP_END          = $4eff
.const FLOOR_ITEM_BASE  = $4f00
.const FLOOR_ITEM_END   = $4fff
.const CREATURE_BASE    = $5000
.const CREATURE_END     = $50ff

.macro BankOutBasic() {}
.macro BankInBasic() {}
.macro BankOutKernal() {}
.macro BankInKernal() {}
.macro BankOutAll() {}
.macro BankRestoreDefault() {}
.macro MachineRestoreDefault() {}
.macro MachineRestoreAllRam() {}
.macro EnterKernal() { php }
.macro ExitKernal() { plp }

#importonce
// dungeon_module_contract.s - fixed ABI for the CX16 dungeon generator module.

.const CX16_DUNGEON_MODULE_LOAD_BASE = $a000
.const CX16_DUNGEON_MODULE_LOAD_END = $bfff
.const CX16_DUNGEON_MODULE_ENTRY = CX16_DUNGEON_MODULE_LOAD_BASE
.const CX16_DUNGEON_MODULE_MAGIC_A = $d6
.const CX16_DUNGEON_MODULE_MAGIC_X = $16
.const CX16_DUNGEON_MODULE_VERSION = $01

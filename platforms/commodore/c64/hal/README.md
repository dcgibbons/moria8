# C64 HAL

Platform-owned C64 implementations will move here behind the contracts in
`commodore/hal`. Until adapters are wired, the existing C64 code remains in its
current files to preserve behavior.

`manifest.json` records the current C64 capability and layout contract. Keep it
in sync with `memory.s`, `config.s`, and platform-owned HAL adapters.

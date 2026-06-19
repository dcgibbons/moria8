# C64 HAL

Platform-owned C64 implementations will move here behind the contracts in
`platforms/commodore/hal`. Existing C64 code remains in this platform tree to
preserve behavior while adapters are wired.

`manifest.json` records the current C64 capability and layout contract. Keep it
in sync with `memory.s`, `config.s`, and platform-owned HAL adapters.

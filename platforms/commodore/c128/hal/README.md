# C128 HAL

Platform-owned C128 implementations will move here behind the contracts in
`platforms/commodore/hal`. Existing C128 code remains in this platform tree to
preserve behavior while adapters are wired.

`manifest.json` records the current C128 capability and layout contract. Keep it
in sync with `memory128.s`, `config128.s`, and platform-owned HAL adapters.

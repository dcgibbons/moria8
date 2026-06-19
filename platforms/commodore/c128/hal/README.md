# C128 HAL

Platform-owned C128 implementations will move here behind the contracts in
`commodore/hal`. Until adapters are wired, the existing C128 code remains in
its current files to preserve behavior.

`manifest.json` records the current C128 capability and layout contract. Keep it
in sync with `memory128.s`, `config128.s`, and platform-owned HAL adapters.

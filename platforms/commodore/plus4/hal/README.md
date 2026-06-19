# Plus/4 HAL

Platform-owned Plus/4 implementations will move here behind the contracts in
`commodore/hal`. Plus/4 storage, banking, input, sound, and TED display code
must not be aliases to C64 services.

`manifest.json` records the current Plus/4 capability and layout contract. Keep
it in sync with `memory.s`, `config.s`, and platform-owned HAL adapters.

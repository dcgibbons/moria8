#importonce
// Overlay/assets contract.
//
// Required exports per platform:
//   hal_asset_load
//
// `hal_asset_load` wraps the platform's KERNAL LOAD equivalent.
//
// Input:
//   A = 0 for LOAD, nonzero for VERIFY
//   X/Y = caller-selected load address when the secondary address does not
//         request the PRG header address
//
// Output:
//   Carry clear = success
//   Carry set = failure
//
// Platform code owns banking, OS visibility, target-bank setup, and any
// post-load runtime resync required after the ROM call.

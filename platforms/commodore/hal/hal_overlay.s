#importonce
// Overlay/assets contract.
//
// Required exports per platform:
//   hal_asset_load
//   hal_asset_load_prg_header
//   hal_asset_load_title
//   hal_asset_close_channel
//
// Service contracts:
// - hal_asset_load: wraps the platform's KERNAL LOAD equivalent.
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
//
// - hal_asset_load_prg_header: wraps the common PRG-header load transaction
//   for runtime assets.
//
// Input:
//   A = filename length
//   X = filename pointer lo
//   Y = filename pointer hi
//
// Output:
//   Carry clear = success
//   Carry set = failure
//
// Platform code owns SETNAM, SETLFS, LOAD, CLOSE, CLRCHN, destination-bank
// setup, OS visibility, and post-load display/runtime cleanup.
//
// - hal_asset_load_title: loads the platform title-art asset into MAP_BASE.
//
// Input:
//   none
//
// Output:
//   Carry clear = success
//   Carry set = failure
//
// Platform code owns title filename selection, SETNAM, SETLFS, LOAD, CLOSE,
// CLRCHN, destination-bank setup, OS visibility, and post-load cleanup.
//
// - hal_asset_close_channel: closes the platform asset-load logical channel
//   and restores default I/O channels.
//
// Input:
//   none
//
// Output:
//   none
//
// Platform code owns OS visibility and whichever KERNAL/wrapper close and
// CLRCHN sequence is valid for the target.

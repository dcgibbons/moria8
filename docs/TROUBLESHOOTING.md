# Troubleshooting

## Commodore I/O Errors

Moria8 storage failures can come from two places:

- The Commodore DOS status returned by the drive command channel.
- The KERNAL status byte (`$ST`) plus a Moria8 phase byte that identifies which
  storage step failed.

The current compact messages preserve diagnostic data. They are not the final
friendly text design.

### Current Display Forms

| Message form | Meaning |
| --- | --- |
| `Disk error! 74` | The drive returned Commodore DOS status code `74`. |
| `Disk code $00 phase $83` | The drive did not report a DOS error, but Moria8 failed during phase `$83`. |
| `Disk ST $xx phase $yy` | KERNAL `$ST` was nonzero during phase `$yy`. |
| `Wrong Save Disk.` | The disk responded, but the Moria8 save marker was missing or did not match. |
| `Need Save Disk.` | Disk Setup has not selected or validated save media for this session. |

### Commodore DOS Codes

These are the high-value drive status codes currently worth mapping to friendlier
text first.

| Code | Meaning | Useful player text |
| --- | --- | --- |
| `00` | OK | Not a drive failure by itself. Check the Moria8 phase. |
| `26` | Write protect on | Disk is write-protected. Use a writable disk. |
| `62` | File not found | Save file or marker was not found. Check the save disk. |
| `72` | Disk full | Disk is full. Use another save disk. |
| `74` | Drive not ready | Drive is not ready. Insert/attach a disk and check the drive. |

### Moria8 Storage Phases

Phase bytes are Moria8 diagnostics, not Commodore DOS status codes.

| Phase | Context |
| --- | --- |
| `$81` | Save marker open/check start failed. |
| `$82` | Save marker input channel setup failed. |
| `$83` | Save marker read/compare failed. |
| `$92` | Save marker create/open failed. |
| `$93` | Save marker output channel setup failed. |
| `$94` | Save marker write failed. |
| `$95` | Save marker close failed. |
| `$96` | Save marker DOS status check failed. |
| `$97` | Save marker scratch/delete failed. |
| `$a1` | Save file open failed. |
| `$a2` | Save file output channel setup failed. |
| `$a3` | Save file write failed. |
| `$b1` | Save file load/open failed. |
| `$b2` | Save file input channel setup failed. |
| `$b3` | Save file read failed. |
| `$c1` | High-score load failed. |
| `$c2` | High-score save failed. |

### Backlog

The next UI improvement is to classify common DOS codes and phase groups into
short friendly text while keeping the raw code/phase fallback for unmapped
failures.

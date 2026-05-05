# Release Checklist

## Clean Build

```sh
make clean
make disk
```

Expected disk artifacts:

- `commodore/out/moria8-c64.d64`
- `commodore/out/moria8-c128.d71`

## Automated Gates

```sh
make test
```

For focused C128 launch checks:

```sh
make test128-fast
make test128-fast-smoke
```

`make test` remains the release gate.

## Manual Smokes

- Boot the C64 disk in VICE or on hardware.
- Confirm the C64 loading/title path reaches the title screen.
- Start a new C64 game and enter town.
- Boot the C128 disk in VICE or on hardware.
- Confirm the C128 loading/title path reaches the title screen.
- Start a new C128 game and enter town in the intended display mode.
- Confirm save/load media prompts are readable.
- Confirm no unexpected disk error appears during boot or first town entry.

## Artifact Review

- Verify disk image names and version metadata.
- Confirm generated outputs are not staged as source.
- Confirm no monitor logs, local paths, private planning notes, or agent process
  files are present in the public tree.

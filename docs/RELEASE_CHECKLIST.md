# Release Checklist

## Release Candidate Tag

Create an annotated release-candidate tag from the commit intended for release:

```sh
git tag -a v1.1.0-rc1 -m "Moria8 v1.1.0 release candidate 1"
git push origin v1.1.0-rc1
```

If the candidate fails release validation, fix the issue on `main` and create a
new candidate tag:

```sh
git tag -a v1.1.0-rc2 -m "Moria8 v1.1.0 release candidate 2"
git push origin v1.1.0-rc2
```

Do not move a public release-candidate tag after pushing it.

## Clean Tag Worktree

Build, test, checksum, and upload artifacts from a clean checkout of the tag,
not from a dirty development worktree:

```sh
git fetch --tags
git worktree add ../moria8-v1.1.0-rc1 v1.1.0-rc1
cd ../moria8-v1.1.0-rc1
git status --short
```

Expected status before release validation:

```text
```

The empty output matters. Do not build release artifacts from a worktree with
untracked files, unstaged edits, local planning docs, or generated leftovers.

## Clean Build

```sh
make clean
make artifacts
```

`make artifacts` signs with GPG and is intended to run from your own
interactive terminal after preparing or unlocking the signing key. Use
`make artifact-checksums` when you only need to rebuild images and
`SHA256SUMS` without touching GPG.

Expected disk artifacts:

- `commodore/out/moria8-c64.d64`
- `commodore/out/moria8-c64.zip`
- `commodore/out/moria8-c128.d64`
- `commodore/out/moria8-c128.d71`
- `commodore/out/moria8-c128.d81`
- `commodore/out/moria8-plus4.d64`
- `commodore/out/SHA256SUMS`
- `commodore/out/*.asc`
- `commodore/out/c64-dist/` staging directory for the C64 Ultimate loose-file distribution

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
- Verify `commodore/out/SHA256SUMS` covers all uploaded artifacts.
- Verify detached GPG signatures for uploaded artifacts and `SHA256SUMS`.
- Confirm generated outputs are not staged as source.
- Confirm no monitor logs, local paths, private planning notes, or agent process
  files are present in the public tree.

## Final Release Tag

After one release candidate passes validation, create the final tag on the exact
same commit:

```sh
git tag -a v1.1.0 -m "Moria8 v1.1.0" v1.1.0-rc1
git push origin v1.1.0
```

Verify the final tag and accepted candidate point to the same commit:

```sh
git rev-parse v1.1.0^{commit}
git rev-parse v1.1.0-rc1^{commit}
```

Those two commit hashes must match.

Do not force-move a public final release tag.

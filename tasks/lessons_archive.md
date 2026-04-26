# Lessons Archive

Historical postmortems and detailed incident writeups moved out of `tasks/lessons.md`
so the active file can stay short and operational.

# Lessons Learned

## 2026-03-31 — Do not “fix” a renderer fast-path bug by disabling the fast path when performance is part of the contract

- **Issue:** I temporarily fixed `BUG-C128-TOWN-TOPROW-RECUR` by forcing vertical C128 scroll delta to fall back to a full redraw. That removed the visible corruption but made repeated town scrolling noticeably slower.
- **Root Cause:** I optimized for immediate correctness and treated the fast path as optional, even though the user-facing regression was specifically in scrolling behavior and the platform already had a working delta-scroll design.
- **Resolution:** Restore the fast path, identify the real state leak inside or immediately after that path, and prove the corrected fast path with targeted tests plus the broader C128 gates.
- **Rule:** **When a bug lives inside an intended performance path, closure requires preserving the performance contract unless the user explicitly approves a slower fallback.**

## 2026-03-31 — Do not present theory as if the live repro supports it

- **Issue:** While chasing `BUG-C128-TOWN-TOPROW-RECUR`, I described likely causes from code reading and automated gates even after the manual `make run128` first-`j` repro was still red.
- **Root Cause:** I let plausible mechanism theories outrun the actual evidence. Source inspection can guide the next experiment, but it does not upgrade a still-failing manual gate into support for a theory.
- **Resolution:** Separate observed facts from inference explicitly, and treat every proposed root cause as unproven until the exact live repro moves in the expected direction.
- **Rule:** **When the user says I am guessing, strip the status back to direct evidence only: what repro fails, what command passes, and what hypothesis remains unproven.**

## 2026-03-31 — If the user says a previously green harness regressed after my change, I own that regression until the exact harness is green again

- **Issue:** After my first-pass `BUG-C128-TOWN-TOPROW-RECUR` fix, `TEST_FILTER='main_loop128' bash commodore/c128/run_tests128.sh` started crashing/timing out, and I initially treated that as a harness-trustworthiness problem while leaning on broader runtime smokes.
- **Root Cause:** I let partial runtime signal compete with the repo rule and the user’s explicit correction. Once the user said that harness worked before my edits, the failure was presumptively mine.
- **Resolution:** Reopen the work immediately, make the exact failing harness an active gate in `tasks/todo.md`, and do not defend the regression as environment noise until that specific command is passing again.
- **Rule:** **When the user says an exact harness worked before my change and is now failing, treat it as my regression and keep that exact command red/green until fixed.**

## 2026-03-31 — If a disk-image boot sector is patched into a filesystem sector, reserve that sector before writing files

- **Issue:** After adding the C128 boot-art helper file, the native C128 build started hanging after `128.RUNTIME` even though the runtime loader code itself had not meaningfully changed.
- **Root Cause:** The earlier mixed-image design patched the native C128 boot sector into Track 1 / Sector 0 without reserving that sector in the filesystem first. Adding one more file shifted allocation enough that `128.RUNTIME` could land on `1/0`, and the boot-sector patch then corrupted it.
- **Resolution:** Treat patched boot sectors as owned media, not just “bytes written later.” Reserve the sector before file allocation or move the boot sector to a deliberately non-filesystem-owned location.
- **Rule:** **Do not patch CBM boot code into a live filesystem sector unless that sector is reserved before any file writes.**

## 2026-03-31 — Center text against the visible interior, not the full row, when a bordered title card defines the real layout

- **Issue:** I added the title-screen version line and centered it against the nominal 40-column row, which left it visibly one column off inside the bordered card on both C64 and C128.
- **Root Cause:** I centered against the full screen width instead of the actual 36-column bordered interior that the eye reads as the layout container.
- **Resolution:** When a title card or border creates the real visual frame, compute centering against that interior width and offset, not the raw row width.
- **Rule:** **For boxed title cards, center content inside the interior frame, not the full line width.**

## 2026-03-30 — When a build input disappears after stashing WIP, check the stash’s untracked payload before treating it as missing from the repo

- **Issue:** I treated a missing stashed build input as an external blocker even though the user had already stashed the experiment that carried the file.
- **Root Cause:** I checked only the normal stash diff surface first, which hid the untracked stash payload where the file actually lived.
- **Resolution:** When a recently stashed branch seems to have “lost” a build input, inspect the stash with untracked files included (`git stash show -u`, `stash@{n}^3`) before concluding the file is absent.
- **Rule:** **After stashing WIP, do not call a missing build input “gone” until you have checked the stash’s untracked tree as well as the tracked diff.**

## 2026-03-30 — When the user changes the product target, freeze the old architecture and keep new implementation spikes scoped

- **Issue:** After landing the unified dual-boot disk, I was still at risk of treating that mixed-image architecture as the default vehicle for the next boot-art feature even after the user explicitly changed the requirement to separate platform images.
- **Root Cause:** I had already invested heavily in the mixed-disk path, so it was easy to let that finished architecture keep driving implementation decisions for the next feature.
- **Resolution:** Once the user changes the product target, record the new target immediately in the planning docs and scope any interim spikes explicitly. If a current spike still uses the old build path for expediency, label it as temporary validation only and do not let that silently redefine the shipping goal.
- **Rule:** **When the user changes the product target, stop optimizing the old architecture by inertia. Capture the new target in docs immediately and keep any interim spike on the old path explicitly temporary.**

## 2026-03-30 — If a cosmetic direction is not landing, back it out cleanly instead of forcing incremental polish

- **Issue:** I expanded the directory art to include usage instructions, but the result was visually worse than the original title card and the user immediately wanted the extra lines removed.
- **Root Cause:** I kept iterating on a presentation direction before the visual premise was actually validated.
- **Resolution:** For cosmetic/UI copy changes, if the first presentation misses the mark, revert to the known-good baseline quickly and wait for a fresh design direction instead of defending or slowly sanding the wrong concept.
- **Rule:** **When an aesthetic change clearly is not working, revert to the stable baseline first. Do not keep the wrong visual direction in the tree while searching for a better one.**

## 2026-03-30 — Do not leave speculative unsupported UX paths in a shipping bootloader

- **Issue:** I added native-C128 detection and courtesy messaging to the C64 `MORIA8` loader even after the user’s real C128 manual-load command had already shown the entry contract was wrong for that path.
- **Root Cause:** I kept a speculative “nice to have” branch in a critical boot path instead of removing it once the user proved it was not a supported contract.
- **Resolution:** When the user proves a boot path is unsupported, remove any speculative helper logic for that path from the shipping bootloader instead of letting dead-end fallback behavior linger.
- **Rule:** **Do not keep unsupported courtesy branches in boot code. If a manual path is not part of the supported contract, document that and keep the bootloader simple.**

## 2026-03-30 — When the user asks to add UX guidance, preserve the existing presentation unless they asked to replace it

- **Issue:** I replaced the existing `MORIA` directory title card with instruction lines when the user wanted the instructions added as a second block beneath the existing header.
- **Root Cause:** I optimized for the new information and ignored the existing presentation value, even though the user had only asked for an add-on.
- **Resolution:** Preserve the current title/art block by default and append the new guidance separately unless the user explicitly asks for a replacement.
- **Rule:** **If the user asks to add instructions or guidance to an existing UI/header/art treatment, extend it first; do not replace the original presentation without explicit approval.**

## 2026-03-30 — Do not assume a C128 manual-load shortcut exercises the same contract as plain BASIC `LOAD ...,8` plus `RUN`

- **Issue:** I treated the new native-C128 courtesy path in `MORIA8` as if it covered the real user-facing manual-load case, but the user's `/*` JiffyDOS test still hung.
- **Root Cause:** I assumed the manual shortcut was equivalent to the plain BASIC-load semantics I had in mind, instead of treating the user's actual command as the contract to verify. On this repo, exact-address, autostart-like, and shortcut-driven entry paths are not interchangeable.
- **Resolution:** Treat native C128 `BOOT` / autoboot as the supported contract, and only describe any `MORIA8` courtesy behavior as best-effort unless the exact manual command the user cares about has been proven.
- **Rule:** **Do not generalize a Commodore manual-load UX claim from one load mode to another. If the user names a shortcut like `/*`, that exact command is the gate.**

## 2026-03-30 — When a visual regression reappears after a seam-specific fix, check sibling render paths before assuming the original fix was lost

- **Issue:** After the dual-entry disk work, the user showed the same town-top garbage artifact on C128 and asked whether the earlier fix had been dropped.
- **Root Cause:** I initially framed the earlier closure as if it had solved the whole symptom class, but the actual March 29 fix only guarded the ordinary-movement C128 scroll-delta path. Shared gameplay code still has sibling scroll-delta entry points, and a visually identical regression can return through one of those paths even when the original fix remains intact.
- **Resolution:** When a previously fixed visual symptom reappears, verify whether the original guarded seam is still present, then audit sibling entry points that call the same renderer under slightly different command tails before concluding the fix was lost.
- **Rule:** **If a rendering artifact returns after a seam-specific fix, do not assume the patched code regressed. First check whether another path still reaches the same renderer without the same guard.**

## 2026-03-29 — Do not conflate `LOAD ...,8` with `LOAD ...,8,1` for Commodore BASIC program portability

- **Issue:** I told the user that a BASIC program saved on one machine would not auto-relocate and therefore could not load cross-platform as a universal BASIC front-end.
- **Root Cause:** I collapsed two different KERNAL/BASIC load modes into one mental model. `LOAD ...,8,1` uses the file header address directly, but ordinary BASIC load via `LOAD ...,8` is different and can place the BASIC program into the current machine's BASIC area.
- **Resolution:** When evaluating universal Commodore boot options, treat `LOAD ...,8` and `LOAD ...,8,1` as different entry contracts. A universal BASIC loader may be viable for ordinary BASIC load+`RUN`, even if it is not viable for exact-address `,8,1` machine-language load.
- **Rule:** **Never reason about Commodore BASIC portability without first separating `LOAD ...,8` from `LOAD ...,8,1`. They are not interchangeable.**

## 2026-03-29 — An identical BASIC PRG is not automatically a valid cross-platform boot artifact when the platforms use different BASIC text origins

- **Issue:** I kept trying to make one identical `MORIA8` PRG autostart on both C64 and native C128 by tweaking loader internals, even though the user’s observed behavior never materially changed.
- **Root Cause:** I was fighting loader symptoms before re-checking the platform entry contract itself. This repo already documents that native C128 BASIC-entry programs live at `$1C01`, while `BasicUpstart2` hardcodes a C64-style BASIC stub at `$0801`. An identical BASIC PRG built around `$0801` is therefore structurally suspect as a native C128 boot artifact before any loader logic even runs.
- **Resolution:** Before spending more time on “universal bootloader” internals, verify that the requested artifact shape is valid on both platforms. If the platforms require different BASIC entry origins, either use a non-BASIC machine-entry boot mechanism or relax the “one identical PRG” assumption.
- **Rule:** **Do not keep patching bootloader logic when the platform entry contract itself may be impossible. Check whether the requested artifact shape is valid on each machine before debugging deeper.**

## 2026-03-29 — For boot artifacts, the first executable byte after the BASIC stub is part of the autostart contract

- **Issue:** I rearranged the universal `MORIA8` source so the intended `boot_entry` label existed, but I still let a raw `chain_stub` occupy `$080E`, the first executable byte after the BASIC stub. The result matched the user’s failures: autostart could land in the raw loader stub before the setup code ever ran.
- **Root Cause:** I focused on the BASIC `SYS` target label and forgot that emulator/autostart flows can machine-enter at the first post-stub code address as a separate contract. In a bootloader, source order and emitted address order both matter.
- **Resolution:** For any autostart PRG, make the real setup entrypoint the very first emitted code after the BASIC stub. Do not place copied stubs, helper routines, or data ahead of the true entry code unless that address is also safe as a direct machine-entry path.
- **Rule:** **On bootloaders, verify both the BASIC `SYS` target and the first emitted code byte after the stub. If autostart can land at `$080E`, `$080E` must be the real entrypoint.**

## 2026-03-29 — A universal stage-0 bootloader should stay silent and hand off cleanly; do not duplicate child-loader UI or leak its KERNAL file handle

- **Issue:** I made the shared `MORIA8` stage-0 do its own clear-screen / cursor / status message work and then jump straight into child loaders after `LOAD`, which produced C128 startup breaks and an invalid two-stage handoff contract.
- **Root Cause:** I treated stage-0 like a user-facing bootloader instead of what it really is: a tiny dispatcher that must preserve platform-native startup assumptions for the real child bootloaders. I also let stage-0 keep file `#2` open across the handoff even though `LOAD` does not remove it from the file table.
- **Resolution:** Keep the universal stage-0 minimal and silent. Let `BOOT64` / `BOOT128` own platform-specific screen setup and messages. After stage-0 `LOAD`s the child, explicitly `CLOSE` the file before the jump, and use the platform-appropriate surviving chain-stub location rather than forcing one address on both machines.
- **Rule:** **For chained bootloaders, stage-0 should only detect platform, load the child, close its file handle, and jump. Do not add user-facing screen/UI work or reuse one survivor-stub address across machines without proving it is safe on both.**

## 2026-03-29 — A “universal” C128 stage-0 loader cannot bypass the repo’s known-safe KERNAL/MMU wrapper contract just because it is tiny

- **Issue:** I treated the identical `$0801` `MORIA8` stage-0 as simple enough to call raw C128 KERNAL entry points directly, outside the repo’s established wrapper discipline.
- **Root Cause:** I optimized for byte-identical artifact shape and ignored the local design rule that C128 `SETNAM`/`SETLFS`/`SETBNK`/`LOAD` transactions must use the known-good KERNAL/MMU entry contract rather than a second custom path.
- **Resolution:** For universal bootloader work, artifact identity is not a license to bypass the C128 wrapper model. If a shared stage-0 needs C128 file I/O, either enter the proven wrapper contract correctly or keep the universal stage-0 thin enough to hand off to a proven child without recreating raw KERNAL transaction logic.
- **Rule:** **Do not create a second custom C128 KERNAL/MMU transaction in a universal bootloader when the repo already has a proven wrapper-based contract.**

## 2026-03-29 — Byte-identical artifacts do not close a universal bootloader milestone if the real autostart paths still fail

- **Issue:** I treated matching `moria8boot.prg` hashes as if that nearly closed the universal `MORIA8` requirement, but the user’s real disk boots immediately disproved that: C64 fell back to BASIC and native C128 hit `BREAK $0831`.
- **Root Cause:** I over-valued artifact identity relative to the real behavioral gate. One identical file is necessary, but it is not sufficient if the machine-specific autostart contract is still wrong.
- **Resolution:** For universal bootloader work, require both conditions together before claiming success: identical emitted artifact and passing real autostart behavior on each target machine.
- **Rule:** **Do not call a universal bootloader “working” just because the binaries match. The real autostart paths on every target platform must also pass.**

## 2026-03-29 — Shared source is not the same thing as one valid universal bootloader artifact

- **Issue:** I treated the shared `moria8boot.s` source as if it had already satisfied the universal `MORIA8` requirement, even though the emitted C64 and C128 binaries were still different files.
- **Root Cause:** I blurred “shared implementation source” with “one identical on-disk program.” For a bootloader feature whose whole point is one `MORIA8`, artifact identity matters, not just code sharing.
- **Resolution:** For any “single bootloader” milestone, compare the emitted binaries directly and refuse to count platform-specific outputs from shared source as closure.
- **Rule:** **If the requirement is one universal program, verify the emitted artifacts are byte-identical. Shared source alone does not satisfy the requirement.**

## 2026-03-29 — When the same C128 boot symptom survives multiple contract patches, replace the handoff with the proven loader instead of continuing to nibble at the seam

- **Issue:** The experimental shared C128 masterboot kept reproducing the same immediate `BREAK` / `JAM` even after multiple local fixes to the raw child-chain path.
- **Root Cause:** I kept treating the bootloader like a sequence of independent small contract bugs, but the path itself was too brittle: a hand-rolled C128 `LOAD` and jump into `boot128` was not the repo’s proven startup shape.
- **Resolution:** After repeated identical failures, stop stacking micro-fixes on the same raw C128 handoff. Replace it with the known-good `boot128` implementation or its exact transaction model.
- **Rule:** **If a C128 boot handoff still shows the same `BREAK` / `JAM` after several contract fixes, stop patching around it and switch to the proven loader path.**

## 2026-03-29 — A C128 post-`LOAD` chain stub is not safe just because its address is low; prove common-RAM ownership and post-load MMU state

- **Issue:** The shared C128 masterboot still failed after fixing the filename-register clobber around `SETNAM`.
- **Root Cause:** I treated `$0B00` as inherently safe for a surviving post-`LOAD` stub because `boot128` uses that address, but `boot128` only uses it after explicitly claiming 4KB bottom common RAM and later restoring a known execution MMU view. The shared loader had neither guarantee.
- **Resolution:** For any C128 stub meant to survive a KERNAL `LOAD` and then jump into a child program, establish bottom-common ownership before copying the stub there and reassert the intended execution MMU/bank state before the final jump.
- **Rule:** **On C128, do not use a low-RAM chain stub unless you explicitly make that region common and restore the child’s expected MMU/bank view after `LOAD`.**

## 2026-03-29 — In C128 boot code, never insert `SETBNK` between staging `A/X/Y` for `SETNAM` and the `SETNAM` call

- **Issue:** The experimental shared C128 masterboot path still BREAKed after a first-pass Bank-0 `SETBNK` change.
- **Root Cause:** I put `SETBNK` in the middle of the filename setup sequence, so the loader staged `A/X/Y` for `SETNAM`, clobbered those registers with `SETBNK`, and then called `SETNAM` with garbage arguments.
- **Resolution:** In C128 loader paths, perform bank-selection setup before loading `A/X/Y` with the filename, or explicitly save and restore those registers around any prep call.
- **Rule:** **On C128, treat `SETNAM` inputs as fragile. Do not put `SETBNK` or any other register-clobbering setup between filename register staging and the `SETNAM` call.**

## 2026-03-29 — On C128 boot/load failures, audit `SETBNK` and visible execution bank before blaming stub addresses

- **Issue:** I chased the shared masterboot BREAK as if the surviving chain stub location were the main culprit, but the stronger risk in `moria8boot.s` was that the child loader transaction never claimed the C128 KERNAL load bank at all.
- **Root Cause:** I focused on where the copied stub survived instead of the full C128 runtime-loaded-code contract: PRG header, load destination bank, visible execution bank, and the jump target all have to agree together.
- **Resolution:** For any C128 boot chain that raw-loads another PRG, check `SETBNK` first and prove the child is loaded into the same bank the chain stub will execute from before changing relocation addresses.
- **Rule:** **When a C128 bootloader `LOAD`s a child PRG and then jumps to a fixed address, verify the child load bank and execution bank match before treating low-RAM stub placement as the root cause.**

## 2026-03-29 — Do not claim a bootloader fix is verified until I reproduce the user’s exact boot entry path, not just a monitor-based title breakpoint

- **Issue:** I concluded the shared C128 master bootloader was working based on smoke tests and monitor breakpoints, but the user immediately reproduced the same live BREAK / `JAM $1000A` behavior on the actual autoload and direct `moria8.128` paths.
- **Root Cause:** I over-trusted indirect boot evidence. Reaching a later symbol under a harness or monitor script did not prove the exact user-visible entry path was healthy, especially for boot code that depends on KERNAL/autostart behavior and startup machine state.
- **Resolution:** For bootloader work, treat the user’s real boot entry path as the authoritative gate. Reproduce the actual autoload and direct-load paths, and do not close the work until those exact entry methods are green.
- **Rule:** **Never mark bootloader work verified on breakpoint/harness evidence alone when the user’s real autoload or direct-load path is still failing. Reproduce the exact boot entry path before claiming success.**

## 2026-03-29 — Before inventing a new owner seam for a C64 full-screen residue bug, check whether the path is still using raw `screen_clear`

- **Issue:** I spent time on restore-tail and generation-I/O theories for the remaining `GENERATING...` residue bug before checking whether the busy screen was still using the repo's known-safe C64 full-screen clear helper.
- **Root Cause:** I treated the symptom as a new orchestration problem instead of first comparing the affected path against the existing residue-safe pattern in `ui_clear_full_screen_safe`.
- **Resolution:** For C64 full-screen transition residue bugs, inspect the clear primitive first. If the path still uses raw `screen_clear`, prefer the existing row-by-row safe helper before widening the fix into game-loop or I/O ownership changes.
- **Rule:** **On C64, if a full-screen transition bug survives blank/clear/draw/unblank ordering, audit the clear primitive itself first. Check `ui_clear_full_screen_safe` before designing a larger shared-flow fix.**

## 2026-03-29 — When the user widens the repro beyond the first visible trigger, redesign around the shared owner instead of the narrow symptom label

- **Issue:** I was at risk of treating `BUG-GEN-STALE-TOWN-C64` like another town-exit-only busy-screen bug even after the user clarified it also happens on other level-generation transitions.
- **Root Cause:** I anchored on the backlog label and the earlier `BUG-GEN-CLEAR-C64` fix instead of re-checking which shared seam actually owns the broader transition.
- **Resolution:** When the user says a repro is broader than the first named path, re-scope the bug immediately around the shared owner and keep the design generic enough to cover every caller of that seam.
- **Rule:** **Do not design to the first visible trigger if the user broadens the repro. Re-anchor on the shared owner and write the fix/test plan against that generic seam.**

## 2026-03-29 — A passing host-order test does not close a visual transition bug if the user’s real screenshot still shows the symptom

- **Issue:** I closed `BUG-GEN-STALE-TOWN-C64` after a restore-side host test passed, but the user immediately showed a live screenshot with stale rows still visible during `GENERATING...`.
- **Root Cause:** I over-trusted the narrow synthetic order test and did not keep the bug anchored on the user-visible symptom. The test proved one hypothesis, not the actual bug closure.
- **Resolution:** For visual transition bugs, treat the user’s real screenshot or repro as the source of truth. A host test can pin one contract, but it cannot by itself prove the symptom is gone if the live display still shows it.
- **Rule:** **Do not close a visual bug on host-call-order evidence alone when the user can still reproduce it on the real transition. Reopen immediately and re-anchor on the live frame evidence.**

## 2026-03-28 — Do not claim a regression is "separate" unless I compare against the user's actual pre-change state

- **Issue:** I claimed the `test_player` failure was separate because it reproduced on `a3470fa`, even after the user explicitly told me the suite was green before my code edits.
- **Root Cause:** I used the wrong baseline. A repo commit that predates my patch is not automatically the same as the user's actual pre-change working state. In a dirty tree or fast-moving local workflow, that comparison is insufficient to clear my change.
- **Resolution:** When the user says the gate was green before my edits, I must treat the regression as mine until I prove otherwise against the exact pre-change state they were using, not an approximate historical commit.
- **Rule:** **Never argue a failure is unrelated based only on an approximate baseline commit. If the user says the suite was green before my change, I own the regression until I verify against the exact pre-change state.**

## 2026-03-28 — When a C64 test hangs after my assembly change, the first hypothesis must be a memory/layout overlap in the code I changed

- **Issue:** I started talking about unrelated suite noise before proving whether the post-change `save` hang was a layout regression caused by my own edits.
- **Root Cause:** I let the clean `main.s` build and an obviously pre-existing `test_player` assembly failure distract me from the project-specific pattern the user has already called out: on this codebase, C64 test hangs/timeouts after an assembly edit usually mean a segment shift, overlap, or breakpoint/layout contract break in the changed code.
- **Resolution:** Treat every new post-change C64 test hang as a memory/layout regression until proven otherwise. Compare current vs baseline assembly maps for the affected test, check bootstrap/BRK/boundary assumptions, and only then talk about unrelated failures.
- **Rule:** **If a C64 test hangs after my patch, first diff the affected test's memory map/layout against baseline and look for overlap in the code I changed. Do not blame the harness first.**

## 2026-03-28 — A failed C64 load must be treated as hostile partial corruption, not as a polite branch back to the title loop

- **Issue:** I initially designed `BUG-LOAD-C64` around abandoning the bad session and redrawing the title, but I had not made the Zero Page, IRQ, and VIC-bank contamination risk explicit enough.
- **Root Cause:** I was reasoning at the transaction/UI level and under-specified the machine-state fallout of a mid-stream C64 load failure. On this platform, a failed read can leave title-critical ZP bytes, interrupt state, and `$DD00` banking assumptions in garbage states even if the visible next step is just "go back to the title screen."
- **Resolution:** Treat any partial C64 load failure as hostile state corruption. Recovery must explicitly reinitialize all title-critical ZP/UI state, re-establish IRQ and VIC-bank postconditions, and prove those invariants under a real disk-backed title-load smoke rather than assuming a redraw alone is enough.
- **Rule:** **On C64, never model failed load recovery as "show the title again." Model it as "rebuild a known-good title machine state from scratch," including Zero Page, IRQ, and `$DD00` ownership.**

## 2026-03-27 — C128 hook refactors need residency checks for every newly exposed callable path, not just the hot paths covered by fast units

- **Issue:** After the `REF-HAL` phase-1 refactor, the C128 Home-store path could `JAM` because `home_enter` had drifted into `$D000-$DFFF`, and the initial verification still missed a real cursor-key town-input regression the user hit interactively.
- **Root Cause:** I leaned too heavily on `test128-fast` plus the standard town overlay smoke, which reaches ordinary `store_enter` via scripted eastward movement but does not prove Home-store residency or real cursor-key behavior. I also failed to extend the C128 callable-residency manifest when the layout shifted.
- **Resolution:** For C128 shared-hook/layout changes, verify every affected callable surface against `io_contracts.s`, especially Home/banked entrypoints, and include at least one runtime check that matches the real input family the user is likely to use, not just vi-key/keybuf scripts.
- **Rule:** **When a C128 refactor adds or moves shared runtime/input seams, do not stop at fast units or one happy-path town smoke. Audit every affected callable in `io_contracts.s` and verify the real interactive path class the change touches.**

## 2026-03-27 — On C128, residency checks must cover the whole callable module, not just the entry label

- **Issue:** The spell list could `JAM` at `$D023` even though `spell_list_display` itself still linked below `$D000`.
- **Root Cause:** I only audited the top-level spell entrypoints. The rest of `player_magic.s` had grown past `$D000`, so later code and even spell-list string data were executing or being read from the I/O hole while the entry label still looked safe.
- **Resolution:** When a C128 callable surface is intended to stay resident or banked, keep the whole module inside one valid residency window or split it explicitly. Entry-label checks alone are not enough if the body can spill into `$D000-$DFFF`.
- **Rule:** **For C128 callable modules, never treat “the entrypoint is out of the I/O hole” as sufficient. Verify the full module body and data stay inside the intended residency region, or move the whole surface into a banked/overlay owner.**

## 2026-03-27 — Platform-specific UI expansions must preserve the original modal contract, not just fit the screen

- **Issue:** My first C128-specific help rewrite used the 80-column width, but it still failed the actual product contract: it wrapped badly, removed the second page entirely, and disk-loaded help each time instead of preloading it with the overlay cache.
- **Root Cause:** I optimized for “fit more text now” and treated the help overlay as low-frequency enough to skip cache ownership, instead of preserving the existing pager behavior and looking for a real Bank 1 slot for the new overlay class.
- **Resolution:** When widening a shared modal UI for C128, keep the behavioral contract intact first: if help was paged, keep it paged; if overlays are supposed to preload/cache, give the new overlay a real cache slot and verify the boot/preload path after the layout change.
- **Rule:** **Do not treat a platform-specific wider layout as permission to change paging or preload behavior opportunistically. Preserve the modal contract, then use actual owned memory to support the new overlay.**

## 2026-03-27 — Fixed-row UI page data should be generated to the declared line count, not hand-counted

- **Issue:** C128 page 2 showed junk and the renderer could walk into adjacent table bytes because the help page claimed to be a fixed 23-line page but the data file stopped early.
- **Root Cause:** The page-2 data hand-counted its blank tail and emitted only 8 blank rows while the renderer always consumes 23 rows. That let the reader fall through into the following metadata table and display garbage.
- **Resolution:** For fixed-row UI page formats, generate the blank tail programmatically or otherwise assert the exact row count. Do not trust manual counting when the renderer consumes a hard-coded number of rows.
- **Rule:** **If a modal UI renderer consumes a fixed number of rows, the data producer must emit that exact count mechanically or prove it with an assertion. Hand-counted filler rows are not reliable enough.**

## 2026-03-26 — Shared modal-UI changes are not verified until the real platform trampolines and key contracts are exercised

- **Issue:** I initially reported the paged-help work as fixed even though the live C64 help path could still JAM, the C128 second page could still render junk, and C128 `ESC` still did not dismiss help.
- **Root Cause:** The coverage I leaned on was too renderer-focused and did not prove the real target-specific runtime contract: overlay load, bank visibility, resident-vs-overlay page pointers, and platform-specific keycodes (`KEY_ESC` on C128, `$1B` on C64).
- **Resolution:** Keep the pager in resident common code, keep the overlay draw-only, seed overlay-local page tables explicitly through the target trampolines, and verify modal-help behavior through affected-platform command-flow tests and full platform suites before claiming the feature works.
- **Rule:** **For shared modal UI work, do not treat direct renderer tests as sufficient. Prove the real platform trampoline path, the live keycode contract, and the authoritative affected-platform suites before saying the fix is done.**

## 2026-03-26 — Shared C64/C128 UI changes are not verified until both target builds pass

- **Issue:** I closed the help-paging work after the C64 fix and targeted C128 tests, but I had not re-run the authoritative C128 build after changing shared help data and overlay composition.
- **Root Cause:** I treated the change like a mostly C64 memory problem after the resident overflow pivot, and I let the earlier C128 fast-suite result stand in for a fresh post-change layout check. That missed the fact that `OVL.UI` had grown to `4532` bytes and no longer fit the C128 `$E000-$EFFF` slot.
- **Resolution:** After any shared UI/data change that affects overlay contents, rebuild both live targets and re-read the memory-map output before calling the work verified. Runtime tests are not a substitute for a fresh overlay-size check.
- **Rule:** **For shared C64/C128 UI or overlay changes, do not stop at one target or at pre-change test results. Rebuild C64 and C128, check the live overlay sizes, and only then trust the test suite results.**

## 2026-03-26 — Shared UI growth can break large C64 test images even when the main game still fits

- **Issue:** After the help-paging change, I treated the later C64 suite stall as an open verification gap instead of immediately proving whether one of the large test images had crossed a hard segment boundary.
- **Root Cause:** I verified the main game and several changed suites, but I did not re-check the largest downstream unit images that import broad common-module sets. `commodore/c64/tests/test_score.s` pulled in the full new help renderer even though help is not under test there, which pushed its resident test body to `$D00A` and into the I/O hole.
- **Resolution:** When a shared UI/common module grows, inspect any large C64 test image memory maps, especially suites like `test_score.s` that import many subsystems. If a suite does not exercise the new UI path, stub it locally instead of linking the full renderer.
- **Rule:** **After shared C64 UI growth, verify not only the main image but also the largest unit-test images for `$D000`/`$A000` boundary drift. Do not keep unused full-screen UI modules linked into tests that never call them.**

## 2026-03-25 — Rebuild the exact C128 target before trusting artifact-budget regressions

- **Issue:** I treated one `c128_artifact_budget` failure as proof that the haggle change had pushed callable code into the `$D000-$DFFF` I/O hole.
- **Root Cause:** I read the guard output before forcing a fresh rebuild of the exact C128 target, and I missed that the authoritative runner could be reusing stale variant outputs in `out/moria128.prg` / `out/main.vs`.
- **Resolution:** When a C128 layout or artifact-budget guard trips, rebuild the exact base target first and then re-read the emitted addresses before deciding whether the current code change actually caused the drift.
- **Rule:** **Do not diagnose a C128 layout regression from stale outputs. Force a fresh `build128`/`test128` build of the current tree before trusting the reported symbol addresses.**

## 2026-03-25 — Use the repo's Makefiles to provision KickAss instead of reaching into sibling workspaces

- **Issue:** I tried to assemble against a `KickAss.jar` from a sibling checkout after the local test runner failed to find `tools/kickass/KickAss.jar`.
- **Root Cause:** I optimized for a quick local workaround instead of following the repository's documented toolchain path, which already knows how to bootstrap KickAss correctly for this workspace.
- **Resolution:** When this repo needs KickAss and `tools/kickass/` is missing, use the Makefile-driven build/test path first and let it provision the assembler. Only look for alternate jars if the user explicitly asks for that or the Makefile path is proven broken.
- **Rule:** **In this repo, do not bypass missing KickAss by borrowing jars from sibling checkouts before trying the Makefile path that auto-downloads/provisions it.**

## 2026-03-25 — Any unit test past 30 seconds is a breakage signal, not a slow pass

- **Issue:** I let the broader C64 regression keep running after it stopped producing progress for well over 30 seconds.
- **Root Cause:** I treated a stalled suite like a potentially slow runtime path instead of applying the repository rule that unit tests do not legitimately hang here.
- **Resolution:** If any unit test or unit-suite stage exceeds 30 seconds, stop waiting, treat it as broken immediately, and isolate the specific test/layout issue.
- **Rule:** **In this repo, a unit test taking more than 30 seconds means something is broken, likely memory/layout related; stop the run and debug the breakage instead of waiting it out.**

## 2026-03-25 — Do not leave VICE/x128 processes running after an interrupted or stalled test attempt

- **Issue:** I stacked repeated C128 test attempts and left multiple `x128` processes running long enough for the user to have to kill them manually.
- **Root Cause:** I focused on isolating the next failure but did not clean up the previous emulator processes before rerunning adjacent test commands.
- **Resolution:** After any aborted, stalled, or user-stopped VICE/C128 test run, explicitly terminate the existing emulator/test-runner processes before launching another attempt.
- **Rule:** **Never launch another C64/C128 emulator-backed test while a prior VICE process from my own run may still be alive; clean up first.**

## 2026-03-25 — `make test128` timeout after my change is my regression until proven otherwise

- **Issue:** After the haggle change, `make test128-fast-smoke` and `make test128-fast` were green but `make test128` timed out, and I drifted into treating that as mainly a harness/debugging problem instead of the default assumption that my change had introduced a memory/layout regression.
- **Root Cause:** I did not apply the repo's existing timeout lessons strictly enough at the suite level. In this repo, a `make test128` timeout is failure evidence and should be treated as a regression from the current diff until isolated away.
- **Resolution:** When the authoritative suite times out after my change, keep the burden of proof on my diff. Use narrower repros only to isolate the regression, not to downgrade the timeout into a tooling issue.
- **Rule:** **If `make test128` times out after my change, treat it as my memory/layout regression until I can prove a narrower unrelated harness bug with evidence. Do not call the work verified before that suite is green or the regression is explicitly isolated.**

## 2026-03-25 — Do not label a regression “flaky” without proof

- **Issue:** I saw `test_render.s` fail after the CA-03 hunger refactor and immediately described it as the project’s “known flaky render suite.”
- **Root Cause:** I leaned on an old narrative in the runner instead of treating the new failure as a real regression from my current changes. In this project, that assumption is dangerous because layout shifts and memory corruption are common failure modes and must be proven absent, not hand-waved away.
- **Resolution:** Treat every fresh test failure as caused by the current diff until the failure is reproduced as pre-existing on the same tree state. Do not use “flaky” as an explanation without direct evidence.
- **Rule:** **When a suite fails after my change, assume I broke it. Do not call it flaky unless I can prove the same failure exists independently of the current diff.**

## 2026-03-25 — Test timeouts in this repo mean hang, not patience

- **Issue:** I let C64 test runs continue far past the project’s stated timeout limits while trying to distinguish a slow suite from a failing one.
- **Root Cause:** I treated missing output as an observability problem instead of honoring the repo’s explicit rule that tests here do not legitimately run that long. In this codebase, a long-running test is itself diagnostic evidence of a hang, usually from memory overwrite/corruption in the assembly.
- **Resolution:** Treat `>30s` as presumptive hang/failure and `>60s` as absolute failure. Stop extending waits, stop rationalizing elapsed time, and pivot immediately to runtime corruption / overwrite diagnosis.
- **Rule:** **For this repo, no test should ever be allowed to run past 60 seconds, and anything past 30 seconds should already be treated as a likely hang. Long runtime is failure evidence, not a reason to wait longer.**

## 2026-03-24 — Similar full-screen C64 UI bugs may need different local fixes

- **Issue:** I treated the C64 game-over / save-and-quit menu clear bug as if it had the same root cause as the recently fixed `GENERATING...` screen bug and applied only the same blank/unblank ordering fix.
- **Root Cause:** I matched on symptom shape too quickly. The generation bug was a visible preparation-order problem, but the game-over menu still leaked the bottom status rows in the final frame, which points to the prompt's actual clear path rather than only its visibility timing.
- **Resolution:** For C64 full-screen UI residue bugs, do not stop at “same symptom, same fix.” Verify the final displayed frame and be ready to switch that specific path to the safer row-by-row clear helper when the bulk clear is insufficient.
- **Rule:** **When a C64 full-screen prompt still shows stale rows after a blank/clear/draw/unblank fix, treat that as evidence the local clear primitive is wrong for that path. Move the prompt to the safer row-by-row clear helper instead of assuming all similar bugs share the same root cause.**

## 2026-03-24 — Escalate as soon as the memory map proves a feature does not fit

- **Issue:** I kept trying to optimize the oversized `look` rewrite locally instead of surfacing the memory-map failure as soon as the build proved it.
- **Root Cause:** I stayed in fix-it-first mode and treated the overage as something to clean up before reporting, even after the C64 main image had already crossed `MAP_BASE`.
- **Resolution:** When a feature trips a hard segment boundary, state the exact addresses and overage immediately and get direction before doing more speculative cleanup.
- **Rule:** **If the memory map or `.assert` output shows a feature no longer fits, stop spinning and escalate with the exact segment addresses before doing more local optimization.**

## 2026-03-24 — Split Umoria-only behavior from VMS baseline before porting a large gameplay feature

- **Issue:** I treated `look` as if only the all-directions `5` mode differed between Umoria and VMS-Moria, then built a large interactive cone/recall implementation around that assumption.
- **Root Cause:** I checked one visible feature delta, but I did not finish the side-by-side comparison of the whole command contract before writing the port. Local VMS-Moria's `look` is much smaller than Umoria's: straight-ray, non-interactive, and no recall handoff.
- **Resolution:** Re-anchor the task on the local primary sources and separate the shared baseline from Umoria-only enhancements before committing to an implementation shape.
- **Rule:** **When porting a large gameplay/UI command, compare the full local Umoria and VMS-Moria implementations first. Lock the shared baseline separately from Umoria-only enhancements before spending memory budget on the richer path.**

## 2026-03-24 — Check the known local third-party source tree before reaching for network access

- **Issue:** I started to request a network fetch of upstream Umoria even though this workspace already has a local upstream checkout at `~/Projects/thirdparty/umoria`.
- **Root Cause:** I anchored on the earlier web/manual lookup and did not verify whether the repo's known local third-party mirror was already available before escalating.
- **Resolution:** For source-parity work against upstream projects, check the existing local third-party trees first and treat them as the primary source when present.
- **Rule:** **Before requesting network access for upstream source code, search the local `~/Projects/thirdparty/` mirrors and any project-documented vendor paths.**

## 2026-03-24 — Full-screen clears must invalidate the status cache

- **Issue:** On C64, returning from the character sheet left the status rows blank until a later gameplay update happened to redraw them.
- **Root Cause:** `screen_clear` wiped the status rows, but `status_draw` saw unchanged cached values and skipped repainting because no force-redraw flag was set.
- **Resolution:** Any full-screen clear that can erase the status area must set the status force-redraw bit so the next `status_draw` repaints even when player values are unchanged.
- **Rule:** **When a UI path uses `screen_clear` and then returns to gameplay, invalidate or force the status redraw explicitly. Do not rely on cached-value changes to redraw erased rows.**

## VDC Hardware Fill (C128)

- **Issue:** Using VDC hardware fill (Reg 30) for `screen_clear` and `screen_clear_row` caused a fatal CPU crash (JAM) during character creation (after pressing 'N' on the title screen).
- **Symptom:** CPU jumps to an invalid address (e.g., $A94E) and executes an operand as an opcode.
- **Root Cause:** Likely a timing or race condition between the VDC's internal hardware fill operation and the CPU's subsequent register access, or an interaction with the KERNAL's interrupt-driven VDC access (even with `sei`). VDC hardware fill takes several milliseconds; if not polled correctly or if a register is selected mid-operation, the VDC status or data register state can become corrupted.
- **Resolution:** Revert to streaming loops for block clears. While slower, streaming with `vdc_wait` per byte is deterministic and avoids the complexity of managing the VDC's internal state during autonomous hardware operations.
- **Rule:** **Prefer streaming loops over hardware fill (Reg 30)** for block operations unless the performance gain is absolutely critical and the busy-state management is exhaustively verified.

## Overlays and Banked Payload Overlap (C128)

- **Issue:** A CPU JAM (crash) at $76CB (inside `item_get_name_ptr`) occurred when entering the dungeon from town.
- **Root Cause:** The `DungeonGenOverlay` (loaded at $E000-$EFFF) was overwriting the beginning of the `banked_payload` (relocated to $EB00). Specifically, `ego_items.s` was being corrupted. When `item_spawn_level` called `tramp_roll_ego_type`, it jumped into the overwritten memory, leading to an eventual crash in the main segment code.
- **Resolution:** Moved `special_rooms.s` and `ego_items.s` to the end of the `banked_payload` block. Since the total payload size is ~4.6KB and it starts at $EB00, the last ~700 bytes (which include these critical shared routines) now reside at $F900+, safely beyond the largest 4KB overlay.
- **Rule:** **Always verify overlay overlap with resident banked code.** On the C128, ensure that any code in the $EB00-$EFFF range is truly disposable while an overlay is active. If shared code is needed *during* overlay execution, it must be placed at $F000+ or included within the overlay itself.

## C128 Zero Page KERNAL Collisions

- **Issue:** Intermittent garbled text appearing dynamically on the VDC screen during combat and UI printing.
- **Root Cause:** C128 utilizes `$02-$08` for hardware operations and pointer temp storage, particularly the `JSRFAR` routines executing during `IRQ` contexts (like screen editor blinking, and timers). The game allocated hot global pointers (`zp_ptr0`, `zp_ptr1` etc) to `$06`-`$0B` which meant background tasks or routines indirectly invoking ROM would silently clobber data strings right in the middle of long decoding loops (e.g. printing `Take off which item...`).
- **Resolution:** Relocated the vital pointers upwards to the `$13-$1F` boundaries which are completely reserved and out of scope of C128 MMU primitives.
- **Rule:** **Never use `$02-$0C` on the C128 for volatile pointers**. Treat it as effectively hazardous since the Kernel expects it available when handling interrupts.

## Verifying Implementations Against Documentation

- **Pattern:** I falsely claimed that features (Black Market and Player Home) were missing because I found old references/TODOs in `AUDIT.md` or `BUILDPLAN.md` without verifying the actual source code or `BUILDPLAN_HISTORY.md` which contained the completion status.
- **Rule:** Before claiming a feature is missing or unimplemented based on a TODO list or design document, ALWAYS `grep_search` the codebase for the feature name (e.g., "Black Market", "Home") to confirm if the code actually exists. Documentation can be stale, but the source code is the ultimate truth.

## Test-First Principle for Memory and Banking

- **Pattern:** Drafted a complex optimization plan (VDC Line Buffers) without including unit tests for the core new routine (`mmu_copy_map_row`) in the initial proposal.
- **Root Cause:** Focused purely on the algorithmic solution (Painter's Algorithm, unrolled loops) instead of the project's strict `AGENT.md` mandate: "Never mark a task complete without proving it works" and "Write plan to tasks/todo.md with checkable items... verify before implementation." For low-level memory operations, failure to test in isolation inevitably leads to invisible overwrites and CPU JAMs.
- **Rule:** **If writing a new memory manipulation, banking, or copy routine, the very first step in the implementation plan MUST be to write an isolated unit test for it.** Prove the routine handles boundaries correctly and doesn't clobber surrounding RAM *before* integrating it into the game loop.

## Processor Status (`plp`) clobbering Carry Flag Returns

- **Issue:** `clc` or `sec` used to return a success/failure status from a subroutine is immediately wiped out by a subsequent `plp` instruction right before the `rts`.
- **Root Cause:** A subroutine starts with `php` to save the caller's processor status. Before returning, it sets or clears the carry flag to indicate a result to the caller. However, if `plp` is executed *after* setting the flag and *before* `rts`, it restores the original processor status from the stack, completely overwriting the newly set/cleared carry flag. This causes the caller to receive whatever the carry flag happened to be when the subroutine was entered, rather than the intended result, leading to silent logical failures like cache misses.
- **Resolution:** If a subroutine uses `php`/`plp` and uses the carry flag for its return value, the `plp` must occur *before* the `clc` or `sec` instruction. (e.g., `plp` then `clc` then `rts`).
- **Rule:** **Never place `plp` immediately after `clc` or `sec`** when those flags are intended as return values. Always execute `plp` first to restore the original state, and *then* modify the specific flag(s) you are using to return status.

## Stop Patching Before Reconfirming the Failing Region

- **Issue:** I kept changing the summary/display path even after monitor traces no longer pointed there.
- **Root Cause:** I let an early hypothesis drive several edits instead of re-anchoring on the latest evidence from the monitor. Once the PC moved to `$E58A` inside the startup overlay, the active failure domain was chargen background generation, not summary display.
- **Resolution:** When low-level debugging produces a new PC / backtrace, treat that as the current source of truth and rebuild the plan around that region before making more code changes.
- **Rule:** **If the latest trace points to a different subsystem than the current hypothesis, stop editing and re-plan from the new trace before proceeding.**

## 2026-03-18 lesson 2
- When a new monitor trace moves the failure to a different address range, stop attributing it to the prior subsystem. Re-anchor the investigation on the new PC/backtrace before proposing next steps.

## 2026-03-18 lesson 3
- On C128, do not assume a low address like `$1000` is callable just because the symbol resolves there. First prove which bank is visible at the call site and whether the address lies in common RAM or bank-private RAM.

## Low-RAM Runtime Code vs. Bank Ownership (C128)

- **Issue:** A long-running C128 `JAM` after character creation looked like chargen/summary corruption, but the active crash was a direct `JSR $1000` into garbage during the first town render.
- **Root Cause:** `viewport_update` / `render_viewport` were linked at low RAM `$1000`, `runtime.low.prg` had no real Stage 2 runtime loader, and the initial repair loaded it into **Bank 1** even though normal gameplay runs in `MMU_ALL_RAM` (**Bank 0**) and `$1000-$3FFF` is not bottom common RAM. The callsite was correct; the residency assumption was wrong.
- **Resolution:** Prove the execution context first: identify the visible bank at the callsite, confirm whether the target address is common or bank-private, then make the loader/header match that execution model. In this case, `runtime.low.prg` needed a `$1000` PRG header and a startup loader into **Bank 0** low RAM, not Bank 1.
- **Rule:** **For any callable low-RAM segment on C128, verify all three together before patching: (1) symbol address, (2) visible bank at the callsite, and (3) common-vs-private RAM ownership.** Never infer one from the others.

## PETSCII Disk Names vs. Source-Friendly Names

- **Issue:** I renamed the low-RAM runtime payload to `runtime_low.prg`, but the C128 directory display rendered `_` as a shifted graphic, not a readable underscore.
- **Root Cause:** I optimized for source readability instead of the actual PETSCII on-screen filename that users see in the disk directory and preload list.
- **Resolution:** For user-visible C64/C128 disk asset names, prefer characters that render cleanly in PETSCII directory listings. In this case, the host artifact can remain `128.runtime.prg`, but the on-disk Commodore filename should be the bare dotted stem `128.runtime` with PRG type.
- **Rule:** **When renaming a Commodore disk file, verify the actual PETSCII directory rendering, not just the source string or host filename.**

## Corrections From the 2026-03-18 Inventory-Help Regression

- **Issue:** I changed the banked payload copy routine based on the inventory-help IRQ trace, but the new helper caused an earlier startup `BRK` before overlays loaded.
- **Root Cause:** I optimized around the vector-overwrite symptom without preserving the original page-`$FF` copy contract. On C128, `$FF00` is the MMU control register, so a naive tail copy into `$FF00-$FFC4` is not safe even if it avoids `$FFFA-$FFFF`.
- **Resolution:** When page `$FF` is involved, enumerate every special address in that window (`$FF00`, RAM vectors, ROM-shadowed helpers) before replacing an existing copy strategy. In this case the safer repair is to restore runtime vectors on banked UI exit, not redesign the copy loop under pressure.
- **Rule:** **If a fix touches C128 page `$FF`, prove every special address in `$FF00-$FFFF` remains safe before changing the routine. Do not replace a specialized copy strategy with a generic one on inference alone.**

## Banked Payload Source vs. Runtime Window (C128)

- **Issue:** Help/inventory/equipment screens could blank or half-render only after overlay activity, even though the resident banked UI code itself lived safely at `$F000-$FFFA`.
- **Root Cause:** I focused on the resident runtime addresses but missed that the **source bytes** for `init_copy_banked` were staged in the main image across `$D6xx-$E6xx`. Because that source span overlaps the overlay load window at `$E000-$EFFF`, any later recopy after an overlay load can silently reintroduce corruption into the otherwise-safe resident `$F000` banked window.
- **Resolution:** For any copied resident block, verify both:
  1. the destination/runtime window is safe, and
  2. the source/staging window does not overlap transient overlay or loader regions that can mutate before the next copy.
- **Rule:** **On C128, overlay-safety analysis must cover both the resident destination and the staged copy source. A resident block can still be corrupted if its recopy source overlaps `$E000-$EFFF`.**

## I/O-Hole Placement Drift (C128)

- **Issue:** Town -> dungeon descent `JAM`ed during `item_spawn_level`, even though the trampoline path itself stayed below `$D000`.
- **Root Cause:** I only asserted the trampoline placement and missed that the callee (`roll_ego_type`) had drifted to `$D310`, inside the `$D000-$DFFF` I/O hole. The PRG contained code there, but runtime execution with I/O visible read garbage.
- **Resolution:** For any banked/trampolined C128 call path, verify both sides of the jump: the caller/trampoline location and the callee’s runtime residency. If the callee must execute with I/O visible, it cannot live in `$D000-$DFFF`.
- **Rule:** **On C128, “trampoline below `$D000`” is not enough. Every callable target in that path must also be asserted out of the I/O hole or explicitly executed with a no-I/O banking mode.**

## Harness Optimizations Need Runtime Verification

- **Issue:** I changed `run_tests128.sh` for `OPT-TEST`, and `bash -n` passed, but the real runner broke badly: helper functions were not visible inside `xargs` worker shells, and a layout guard still enforced an obsolete banked-UI contract.
- **Root Cause:** I treated syntax validation and ad hoc sourcing as enough proof for a shell harness change. That missed two real execution contexts: exported functions in child shells and stale assertions inside the harness itself.
- **Resolution:** For shell-runner changes, always validate the actual execution mode:
  1. run the real target (`make -C commodore/c128 test128` or a focused sourced runner path),
  2. check any `xargs` / subshell worker paths explicitly, and
  3. update harness assertions when the underlying architecture contract has changed.
- **Rule:** **A shell harness change is not verified by `bash -n`. It must be exercised through the same subshell/worker path the real test runner uses.**

## Shell Passes Do Not Imply Snapshot Readiness

- **Issue:** I initially treated `memory128`, `msg_prompt128`, and `tier128` as ready for the Python Gate C.4 batch harness because they passed under the shell moncommands runner.
- **Root Cause:** The shell path (`load` + `r pc=` + `until`) and the Python cold/snapshot paths do not reproduce the same machine state. A test can be valid under the shell harness yet still be invalid under the current ready-snapshot contract or the Python reset model.
- **Resolution:** Promote a test into the default Python batch set only after it passes in both:
  1. direct Python cold mode, and
  2. Python snapshot mode using the current prepared snapshot contract.
  If either path is not trustworthy, mark the test explicitly unsupported instead of leaving it in the default compare set.
- **Rule:** **For Gate C.4, shell-harness success is necessary but not sufficient. A test is only “snapshot-ready” after direct Python cold/snapshot verification.**

## Moncommands Paths Must Match Exactly

- **Issue:** I initially classified several Gate C.4 tests as incompatible with the Python batch harness when they were really failing because the Python moncommands path did not match the shell harness execution contract.
- **Root Cause:** The Python moncommands runner omitted `+remotemonitor +binarymonitor` and the per-test `-limitcycles` budget. That left VICE alive at the monitor prompt and produced false timeout failures.
- **Resolution:** When reproducing a shell-based VICE flow in Python, mirror the full invocation contract before concluding a test is incompatible. For moncommands-driven tests, carry over the shell runner’s flags and cycle budgets explicitly.
- **Rule:** **If a Python VICE harness disagrees with the shell harness, compare the exact emulator invocation first. Missing VICE flags or cycle budgets can look like test failures.**

## Symbol Width Is Not Enough To Choose A Harness Path

- **Issue:** I initially assumed only wrapped/wide symbol addresses needed the moncommands fallback. `input128` disproved that assumption.
- **Root Cause:** The `symbols_need_moncommands()` heuristic only captures one class of incompatibility. Some tests with ordinary 16-bit symbols still require the shell-style moncommands contract to execute correctly.
- **Resolution:** Treat moncommands-vs-socket execution mode as explicit per-test metadata once a test proves it needs that path. Do not rely on symbol width alone as the selector.
- **Rule:** **For Gate C.4, “4-digit symbols” does not imply “safe for socket-run execution.” Use explicit per-test execution metadata when needed.**

## Closed Technical Fixes vs Misleading Names

- **Issue:** I answered as if the low-RAM runtime payload issue was fully “done,” but the user was pointing at the still-misleading artifact name, not just the runtime loader contract.
- **Root Cause:** I collapsed two separate concerns into one: the runtime fix (load/address contract) and the naming/architecture clarity problem.
- **Resolution:** When a historical bug involved both runtime behavior and confusing naming, answer both explicitly: what is fixed in code, and what remains misleading in naming/docs. Then actually clean up the naming so future work does not preserve the confusion.
- **Rule:** **Do not call a historically expensive issue “fully fixed” if the naming still contradicts the runtime contract. Distinguish behavioral closure from naming/architecture clarity, and fix both when possible.**

## Commit Policy Must Be Explicit

- **Issue:** I committed the running fix as soon as verification was complete without waiting for explicit user approval.
- **Root Cause:** I treated the repository's frequent commit cadence as implicit permission instead of checking for an explicit "OK to commit" signal in the current task.
- **Resolution:** Treat commit authority as opt-in for the current task unless the user has clearly told me to commit when done. Verification and documentation can complete before that point, but the final `git commit` must wait for explicit approval.
- **Rule:** **Do not commit changes in this repo until the user explicitly says to commit, even if the code is done and fully verified.**
- **Follow-up:** The recent town-entry regression and subsequent fix were committed before the user said “OK,” so this is a second reminder that every task ends with an explicit approval step.

## 2026-03-20 — Bank 1 cannot execute bank 0 code

- **Issue:** Entering town after the row-buffer changes triggered a JAM in `mmu_select_bank1` (`C:$01F8`) because the new loop executed while Bank 1 was active, so the CPU fetched the wrong instructions.
- **Root Cause:** `map_bulk_enter` was called before the `row_char_buf` copy loop, leaving Bank 1 selected while the renderer kept executing Bank 0 code; the bytes under Bank 1 at the same addresses were not valid instructions, so the CPU fell into an illegal opcode.
- **Resolution:** Use the `mmu_copy_map_row` helper to pull the entire row into the shared scratch buffer while Bank 1 is active, return to Bank 0, and then copy from `SCREEN_RAM` into `row_char_buf`; this keeps us executing Bank 0 code with Bank 0 visible and relies on the bank-safe helper for the single transition.
- **Rule:** **Whenever a bank switch is required for data access, either run the affected code entirely from a helper located in that bank/common area or switch back before executing Bank 0 code; do not run Bank 0 instructions while Bank 1 is still selected.**
## Premature Running Stop Needs Runtime Diagnosis First

- **Issue:** I treated the user's "running stops too early" report as a corridor-stop-policy problem and patched `run_check_stop` / `run_check_intersection`, but manual testing showed the real symptom did not change.
- **Root Cause:** I anchored on the static code discrepancy (missing floor-item stop and oversensitive side-junction logic) without first proving that the observed stop was actually coming from those branches. The reported fixed-distance stop in both town and dungeon suggests the real cause is in run continuation/cancel handling, not corridor geometry.
- **Resolution:** For movement/running bugs, first classify the symptom by behavior pattern: geometry-sensitive stop, sight-sensitive stop, or fixed-distance/cancel stop. If the stop distance is roughly constant across town and dungeon, inspect input/run-cancel state before touching map-intersection logic.
- **Rule:** **Do not patch running stop-policy code until the observed stop pattern has been tied to that code path. A fixed-distance stop pattern points to run continuation/cancel logic first.**

## One-Sample Run-Cancel Edges Are Too Fragile

- **Issue:** I left the running cancel path on a one-sample edge detector after the earlier fix. After the 10.3 map expansion, the user immediately hit early running cancellation again.
- **Root Cause:** The run-cancel detector treated any single nonzero sample as a fresh cancel edge once armed. That is too fragile for direct keyboard scanning, especially when frame cadence changes and scan noise gets more opportunities to land as a transient sample.
- **Resolution:** Normalize run-cancel samples to boolean held/not-held state and require a newly-stable pressed state before emitting a cancel edge. Keep the logic shared across C64/C128 so behavior does not drift again.
- **Rule:** **For direct-scan run cancel, do not use a one-sample raw-key edge. Use a debounced boolean held-state edge detector.**

## Running Must Use Physical Held State, Not Decoded PETSCII

- **Issue:** After the debounce fix, C128 running still stopped after a few steps while C64 behaved correctly.
- **Root Cause:** The C128 running path was still sampling `cia_scan_petscii` for held/cancel state. Shifted run movement depends on PETSCII decoding staying visible, but running logic only cares whether the initiating keys are physically still down.
- **Resolution:** Use a raw matrix-held helper for `input_run_key_held` and `input_run_cancel_check` on C128, matching the C64 contract. Keep PETSCII decoding for command entry, not held-state detection.
- **Rule:** **For held/cancel polling, sample physical key state. Do not route running through PETSCII decoding on C128.**

## Corridor door placement must reflect actual tunnel penetration

- **Issue:** `add_corridor_doors` used to synthesize lateral doors whenever a corridor tile ran next to a room wall, which cluttered hallways with phantom doors and confused both running heuristics and dungeon semantics.
- **Resolution:** Make the helper a compatibility stub, remove the `dungeon_generate` call, and rely on `carve_h_corridor` / `carve_v_corridor` plus `random_door_type` to place doors only when a corridor actually breaches a wall. The new `commodore/c64/tests/test_dungeon.s` cases prove adjacency alone does not produce a door while actual penetration still does.
- **Rule:** **Door placement must always occur during corridor carving; never add a door solely because a corridor tile lies adjacent to a room wall. Tests must guard the contract on both adjacency and penetration conditions.**

## 2026-03-21 — Respect explicit revert requests

- **Issue:** After a user observed the new OPT-VDC stack hung the dungeon/town creation code and demanded a rollback, I continued the work rather than pausing to revert everything that wasn’t the 2 MHz tweak.
- **Resolution:** Roll back all OPT-VDC changes before making any other edits, even if debugging traces look promising, and keep only the CPU speed toggle the user explicitly ordered to keep.
- **Rule:** **When a user explicitly orders “revert everything except…”, stop implementing new features, revert the tracked/untracked files to the requested state, and log the correction in `tasks/lessons.md` immediately (with a reminder to obey future direct corrections).**

## 2026-03-22 — Check room-level and tile-level lighting state together

- **Issue:** The long-standing dark-room "flash" on item pickup or monster death looked like a redraw bug, but the real failure was stale lighting state.
- **Root Cause:** `room_lit[]` and per-tile `FLAG_LIT` could drift apart, so a forced full redraw after pickup/kill would render the room as lit even though the room tiles had not been synchronized to that state.
- **Resolution:** Add one authoritative helper to light an entire room and make room-light effects use it, so room-level and tile-level lighting state stay synchronized before investigating renderer-specific causes.
- **Rule:** **When a visibility or redraw bug affects entire rooms, check room-level state (`room_lit[]`, room caches) against per-tile flags before changing renderer logic.**

## 2026-03-22 — Close completed work in both active and history docs

- **Issue:** After fixing BUG-LIT and adding the completed history entry, I still left the active build plan stale, so the resolved bug was not reflected in `commodore/BUILDPLAN.md`.
- **Root Cause:** I treated `BUILDPLAN_HISTORY.md` as sufficient for closure and did not re-check whether the active status summary also needed to be updated to reflect the completion.
- **Resolution:** When closing a task that is mentioned in planning docs, update both the archival completion record and the active build-plan state in the same pass, then verify the result with a direct grep.
- **Rule:** **If a bug or phase is closed, do not stop at `BUILDPLAN_HISTORY.md`. Also reconcile `commodore/BUILDPLAN.md` so the active plan no longer contradicts the completion record.**

## 2026-03-22 — Do not close a multi-cause bug after fixing only one trigger

- **Issue:** I declared BUG-LIT fixed after correcting the `room_lit[]` / `FLAG_LIT` drift, but the user immediately reproduced another dark-room pickup case that still revealed hidden room tiles.
- **Root Cause:** I treated one verified sub-cause as if it exhausted the whole bug class, without requiring a broader repro matrix or a test that matched the original gameplay symptom closely enough.
- **Resolution:** Reopen the bug as soon as a real repro survives, keep the partial fix, and do not mark the overall issue complete until at least one targeted test or manual matrix covers the remaining symptom family.
- **Rule:** **For long-standing rendering bugs with multiple plausible causes, do not close the umbrella bug after fixing one trigger. Keep it open until the original gameplay repro family is actually covered.**

## 2026-03-22 — Do not generalize a bad tool invocation into a global environment claim

- **Issue:** After my C64 headless test invocation crashed, I claimed that VICE itself was broken in this environment.
- **Root Cause:** I inferred a broad environment failure from one failing command sequence without validating the simpler counterexample: whether `/opt/homebrew/bin/x64sc` itself ran normally outside my exact headless/autostart setup.
- **Resolution:** Treat failures like this as invocation-specific until proven otherwise. Separate "this command line crashed" from "the tool is broken," and say exactly which invocation failed.
- **Rule:** **Never claim a tool/environment is generally broken when only one scripted invocation has failed. State the exact failing command path and keep the scope narrow until independently confirmed.**

## 2026-03-22 — Keep umbrella bug status narrower than individual trigger fixes

- **Issue:** BUG-LIT turned out to have multiple trigger paths, and after fixing the pickup/full-redraw path I still needed the docs to reflect "one trigger fixed, umbrella still open."
- **Root Cause:** I had already made the mistake in the opposite direction earlier by declaring the whole bug fixed after one sub-cause. The durable rule needs to be symmetric: doc status must match the exact scope of what was just proven.
- **Resolution:** When a multi-cause bug is partially fixed, record exactly which trigger is closed and keep the umbrella item open until the remaining trigger family is rechecked.
- **Rule:** **For multi-trigger bugs, document the exact trigger path that is fixed. Do not collapse partial progress into either "fully fixed" or "still unchanged."**

## 2026-03-22 — Keep BUILDPLAN for backlog, not guardrails

- **Issue:** I reorganized `commodore/BUILDPLAN.md` into a single open-items table, but I mixed real backlog items with merge guardrails like “keep the suite green” and “preserve memory ownership,” which made the table harder to read and less useful.
- **Root Cause:** I treated every true project constraint as if it belonged in the same artifact as actionable work. That conflates two different purposes: planning outstanding tasks versus recording engineering discipline.
- **Resolution:** Keep `BUILDPLAN.md` for actual open bugs, features, phases, and cleanup work. Put “don’t break this” operational rules in `AGENTS.md`, `tasks/lessons.md`, asserts, and tests instead.

## 2026-03-23 — Do not invent cross-platform input portability doubts without evidence

- **Issue:** I pushed back on a fixed `Ctrl+W` Wizard Mode hotkey by speculating that the key might not be portable across C64 and C128.
- **Root Cause:** I ignored established project knowledge: the platforms differ in polling implementation, but the actual command-key identity layer is already aligned.
- **Resolution:** Treat proven command-mapping parity as the default. Only argue for an implementation-defined hotkey if the actual key identity differs in code or observed behavior.
- **Rule:** **Do not raise speculative cross-platform input objections when the repo already standardizes the key mapping across platforms. Require evidence before arguing for a flexible hotkey.**

## 2026-03-22 — Do not repurpose the live `$E000` overlay window for resident compute code

- **Issue:** I moved `player_magic.s` into a reloadable `$E000` compute payload because the symbol layout and fast C128 suite looked good, but live gameplay immediately corrupted character creation and town/spell paths.
- **Root Cause:** `$E000-$EFFF` is not an abstract “free reloadable code window.” It is the active startup/town/death/dungeon-generation overlay execution region, and those overlays are live earlier and more often than the focused tests proved. Recopying spell compute code there destroyed the active overlay image.
- **Resolution:** Reject `$E000` as a general-purpose resident compute relocation target for shared gameplay code. Any future relocation must use a region that is not the active overlay execution window, or it must come with explicit overlay coexistence proof in real gameplay.
- **Rule:** **On C128, do not move shared gameplay compute code into `$E000-$EFFF` just because it is reloadable. Treat the overlay window as owned by overlays unless coexistence is explicitly proven in live game flows, including startup/chargen.**
- **Rule:** **Do not put ongoing engineering guardrails into the active backlog table. `BUILDPLAN.md` should answer “what is left to do?”, not “what must always stay true?”**

## 2026-03-22 — Assert the whole callable routine, not just its entry label

- **Issue:** Casting still JAMmed at `$D013/$D023` even after the relocation work looked clean and the old C128 assert said `trace_step < $D000`.
- **Root Cause:** That assert only checked the routine entry label. `trace_step` started at `$CFF7` but its body extended into `$D000-$DFFF`, so runtime execution still fetched garbage from the I/O hole.
- **Resolution:** Treat I/O-hole safety as a whole-routine placement problem. In this case the right fix was to relocate the projectile helper routines into the copied common combat window and update the assert to cover that actual residency contract.
- **Rule:** **On C128, never assert only that a callable symbol starts below `$D000`. Also prove the routine body cannot execute into `$D000-$DFFF`, or relocate the routine into a region with a stronger contract.**

## 2026-03-22 — Do not stack speculative prompt and redraw fixes on top of a working input guard

- **Issue:** After fixing the spell-list entry key edge, I layered on an extra post-selection release wait, a special no-release direction prompt, and an extra `update_visibility` during spell-list restore. That regressed spell casting again and muddied the BUG-LIT signal.
- **Root Cause:** I kept “improving” a narrow input fix without evidence that the first correction was insufficient. That combined three different concerns: key-edge handling, nested prompt behavior, and visibility/redraw state.
- **Resolution:** Roll back the extra nested-prompt and redraw changes, keep only the original spell-selection release guard, and re-test from that narrower baseline.
- **Rule:** **When an input fix works, do not immediately pile on prompt-specialization and redraw-state changes. Keep the minimal guard first, then re-test before changing adjacent systems.**

## 2026-03-22 — `$0800-$0BFF` is not safe permanent executable space for C128 gameplay code

- **Issue:** I relocated the combat/spell spill cluster into a copied common-RAM blob at `$0800-$0BFF`. Spell casting started to work, but the death path still hung deep inside ROM with traces like `C:$E7F2  LDA $0A0F`.
- **Root Cause:** Under `MMU_NORMAL`, those `$E7xx` addresses are KERNAL / Screen Editor ROM, not our overlays. ROM was reading low RAM around `$0A0F`, which the new combat blob had overwritten. So `$0800-$0BFF` is part of ROM workspace expectations during KERNAL-visible flows and cannot be treated as permanently safe code storage.
- **Resolution:** Abandon the `$0800-$0BFF` relocation design entirely and revert the branch to the last stable baseline.
- **Rule:** **On C128, do not treat `$0800-$0BFF` as free permanent executable common RAM for gameplay code unless you have explicit proof it survives all KERNAL/ROM paths. A ROM trace reading that region is evidence the design is invalid, not a cue to patch around it.**

## 2026-03-22 — Shared C64/C128 file splits must preserve the non-C128 import path

- **Issue:** Splitting `player_magic_tail.s` out for C128 banked placement broke the C64 build because `mage_effect_dispatch` and `priest_effect_dispatch` disappeared from the non-C128 link path.
- **Root Cause:** I treated a shared-file split as if only the C128 placement changed, but the shared source graph changed too. C64 still imported only `player_magic.s`, so the split silently removed required symbols there.
- **Resolution:** When factoring shared code for C128-only residency, explicitly retain the non-C128 import path in the shared source and immediately rebuild C64 before treating the change as valid.
- **Rule:** **Any C128-only relocation that splits a shared source file must preserve the non-C128 import graph and be followed immediately by a C64 build check.**

## 2026-03-23 — Runtime-installed busy shims must be proven live, not just referenced

- **Issue:** The generation spinner logic was wired into `game_loop.s` and `turn.s`, but the player still only saw the old `Loading...` message and never the full-screen `GENERATING...` UI.
- **Root Cause:** The gameplay path called `generation_busy_*_api`, but those symbols still assembled to default `RTS` stubs because startup never patched them live. I verified the call sites and not the installed shim bytes.
- **Resolution:** Convert the busy API to an explicit startup-installed jump table, patch it during platform startup, and use the shared `generation_busy_active_api` state for any suppression logic that depends on the UI being active.
- **Rule:** **For startup-installed shim APIs, verify both that the game calls the shim and that startup patches the shipped stub bytes before gameplay begins. Referenced symbols alone do not prove the feature is live.**

## 2026-03-23 — Do not inject UI helpers into generation inner loops that still own live scratch state

- **Issue:** After the busy UI finally appeared, the initial town map came up corrupted.
- **Root Cause:** I had added `generation_busy_tick` calls inside dungeon-generation inner loops (`place_rooms`, `connect_rooms`, `place_streamers`). Those loops still owned generator scratch/register state, and the UI helper clobbered it.
- **Resolution:** Keep progress UI calls only at coarse, explicitly safe phase boundaries unless the callee contract is proven re-entrant with the generator’s scratch usage.
- **Rule:** **For long-running generation/codegen loops, do not call screen/UI helpers from inside inner loops unless scratch/register ownership has been audited end-to-end. Prefer outer phase boundaries.**

## 2026-03-23 — C64 `msg_print` strings must be screen-coded, and banked UI fixes must be re-budgeted immediately

- **Issue:** C64 Wizard actions like Reveal and Generate Item showed junk text (`8&>e`) instead of the expected completion message, and the follow-up fix work kept brushing against the C64 banked-vector ceiling.
- **Root Cause:** I introduced Wizard strings in a shared/common file with plain `.text` bytes while the C64 message renderer expects screen-code strings. Separately, I treated small common/UI tweaks as if they were “free,” even though the C64 banked payload was already only a few bytes from `$FFFA`.
- **Resolution:** Emit C64-facing Wizard/message strings with the correct screen-code encoding, then immediately rebuild and read the banked payload boundary after any shared banked-UI change. If space is needed, trim low-value banked UI text rather than touching logic again.
- **Rule:** **On C64, any string that goes through `msg_print` or `screen_put_string` in gameplay UI must be verified as screen code, not assumed from `.text`. After any shared banked UI change, re-check `banked_code_end` before assuming the fix is safe.**

## 2026-03-23 — C128 fast command input can race on modifier chords

- **Issue:** `Ctrl+W` worked on C64 but on C128 it fell through to a plain gameplay command instead of opening Wizard Mode.
- **Root Cause:** The C128 fast command-entry path accepts the first stable key-down sample immediately. For a chord like `Ctrl+W`, the `W` sample can arrive one scan before the Ctrl modifier settles, so the command path locks in plain `W` unless the chord is normalized after acquisition.
- **Resolution:** Recheck live Ctrl state for `W` immediately after fast key acquisition and normalize it to the Wizard pseudo-key before PETSCII-to-command decode. Keep the runtime fix compact, and cover the pure normalization rule in a unit test.
- **Rule:** **On C128, do not assume modifier chords are stable on the first fast input sample. For any modifier-based command, verify whether the command-entry path needs a post-acquisition normalization step.**

## 2026-03-23 — Do not merge Magic Mapping and global light into one Wizard reveal action by guesswork

- **Issue:** Wizard Reveal was implemented by setting `FLAG_VISITED | FLAG_LIT` across the whole map, forcing every room lit and piggybacking on the visibility-update redraw tail. On C64 that produced incorrect-looking results and led to a post-reveal crash.
- **Root Cause:** I guessed at the semantics of “reveal” instead of checking the actual classic behavior split. In Umoria, Magic Mapping and global overhead light are separate Wizard commands, so collapsing them into one blanket-lighting action was too blunt.
- **Resolution:** Make Wizard Reveal do mapping-only semantics (`FLAG_VISITED` without global `FLAG_LIT` / `room_lit` mutation), redraw through the plain gameplay restore path, and only add a separate global-light command later if we explicitly want it.
- **Rule:** **When cloning classic Wizard/debug commands, verify whether upstream separates “map memory” from “global light” before implementing a one-step reveal action.**

## 2026-03-23 — Overlay-resident C128 UI code cannot keep running after loading a different overlay

- **Issue:** C128 Wizard level jump reached generation and then got stuck on the busy screen. The monitor trace showed the game back in `input_get_command`, meaning control had returned to the main loop without restoring the gameplay view.
- **Root Cause:** `ui_wizard_cmd_level_jump` lived in `OVL.UI` at `$E000`, but it tried to call `overlay_load(OVL_DUNGEON_GEN)` and then continue executing more Wizard code from the same overlay window. Once the new overlay was loaded, the remaining Wizard code in `$E000` was no longer valid.
- **Resolution:** Move the actual level-jump execution tail into main-resident code and let the overlay UI only collect input and then jump to that stable main routine.
- **Rule:** **On C128, any command handler that lives in an overlay must not continue executing after swapping in a different overlay. Collect input in the overlay, then transfer control to main- or banked-resident code before `overlay_load` of another overlay.**

## 2026-03-23 — If Wizard Mode is meant to force an outcome, call the shared effect helper directly

- **Issue:** Wizard `Gain Level` kept doing nothing in manual play even though the code path looked equivalent to normal XP-driven level-up.
- **Root Cause:** I kept routing Wizard `Gain Level` through `combat_check_levelup` because the threshold/XP setup looked correct on inspection. That was the wrong level of abstraction for a forced Wizard action, and I trusted code symmetry over manual evidence.
- **Resolution:** Extract the actual level-up body into `combat_apply_levelup` and have Wizard `Gain Level` call that shared helper directly after seeding XP, instead of reusing the ordinary threshold gate.
- **Rule:** **When a Wizard/debug action is supposed to force a state transition, do not keep it behind the normal gameplay eligibility wrapper once manual testing disproves that path. Extract and call the real shared effect helper directly.**
- Wizard/debug commands should reuse existing gameplay reveal/effect helpers where possible; ad hoc map-flag edits miss side effects like secret-door conversion.
- For map-reveal/debug features, do not mark the whole map `FLAG_VISITED` blindly; that exposes solid-rock filler and produces misleading layouts on deep levels. Reveal the floor plan, then add corridor boundaries and reuse existing door/trap reveal helpers.

## 2026-03-23 — When a rare C128 gameplay helper does not fit low runtime, prefer an overlay over forcing it into resident banks

- **Issue:** I moved `magic_check_new_spells` out of the I/O hole by pinning it in `RuntimeLowData`, which fixed the immediate `$D023` JAM but immediately overflowed the `$1000-$19FF` low-runtime ownership fence at `FLOOR_ITEM_BASE`.
- **Root Cause:** I treated “low runtime is resident” as the default safe destination without re-checking its real ownership budget. That region is tightly bounded by floor-item and creature tables, so a one-off helper there can be just as wrong as leaving it in the I/O hole.
- **Resolution:** Move the helper into `OVL.UI` and make the C128 trampoline load that overlay before calling it. For low-frequency helpers like learned-spell updates, overlay residence is safer than overfilling either low runtime or the resident `$F000` payload.
- **Rule:** **On C128, when relocating a low-frequency helper out of the I/O hole, do not force it into `RuntimeLowData` or the resident banked payload by default. First ask whether an existing overlay is the safer ownership match.**

## 2026-03-23 — Verify sentinel assumptions against live table indexing before patching a display path

- **Issue:** After adding save/restore protection for the death source, the death screen still showed `Unknown Causes` for some Wizard deaths.
- **Root Cause:** I assumed `zp_death_source == 0` meant "alive/unknown" because of a stale zeropage comment and matching fallback branch in `score.s`. In reality, monster index `0` is a valid creature (`White Harpy`), so the death screen was misclassifying real monster deaths as unknown.
- **Resolution:** Check the actual indexed table owner (`monster.s`) before trusting sentinel comments, then treat any non-special `zp_death_source` as a monster id in the death screen.
- **Rule:** **Whenever a byte is documented as a sentinel-bearing enum, verify that claim against the real indexed data tables before writing fallback logic around value `0`.**

## 2026-03-23 — When shuffling room order, keep all parallel room metadata arrays in lockstep

- **Issue:** Lit rooms started behaving like dark rooms even with a lantern equipped; only torch/LoS visibility still worked.
- **Root Cause:** `shuffle_rooms` was only swapping `room_x`, `room_y`, `room_w`, and `room_h`. It left `room_lit[]` behind, so the room geometry and the “this room is lit” flag drifted apart after generation.
- **Resolution:** Treat `room_lit[]` and other room-parallel metadata as part of the shuffled room record, and extend the dungeon test to verify the metadata stays aligned with the shuffled geometry.
- **Rule:** **Whenever SoA room records are reordered, audit every parallel array (`room_*`) and update the shuffle/copy path for all of them, not just geometry.**

## 2026-03-23 — Wizard item generation must reuse the real item-initialization path

- **Issue:** Wizard `Generate Item` reported `FAIL` for ordinary items like `Brass Lantern`, and even a “successful” raw spawn would have created unusable lights/wands/staves with zero charges.
- **Root Cause:** The Wizard command was hand-writing a bare floor item entry with `p1=0` and relying on floor placement success. That skipped the normal item initialization path (`roll_enchantment`, charges, ego rolls, ammo stack sizing) and made the command depend on floor-slot state instead of producing a usable test item.
- **Resolution:** Route Wizard item generation through the normal item-creation helpers, prefer inventory placement for non-gold items, and only fall back to floor placement if inventory insertion fails.
- **Rule:** **Wizard/debug item creation should not hand-assemble raw item structs unless the intent is explicitly “broken placeholder item.” Reuse the normal item initialization helpers so charges, enchantment, ego flags, and stack sizing stay coherent.**

## 2026-03-23 — Do not claim original-game behavior without a primary source

- **Issue:** I talked about the current carried-light radius as if it were plausibly faithful to original Umoria, even though I had not verified the original game’s exact numeric behavior.
- **Root Cause:** I generalized from the current port implementation and broad manual language about lamps/torches instead of checking whether the original game actually specified the radius or differentiated torch vs lantern reach.
- **Resolution:** When the user asks for original-game parity, either verify the exact behavior in primary Umoria sources or say explicitly that the precise rule is still unverified and needs research.
- **Rule:** **For historical-faithfulness questions, do not infer a specific gameplay parameter from the current port. Verify it in primary sources or turn the gap into explicit backlog research.**

## 2026-03-23 — When shared gameplay code gains a new helper dependency, update the shared C64 test stubs immediately

- **Issue:** The BUG-RECALL refactor made `turn.s` call `level_change_generate_current`, and a large set of C64 unit suites started failing at assembly with `Unknown symbol 'level_change_generate_current'`.
- **Root Cause:** I updated the focused recall test, but I did not audit the broader C64 test harness pattern where many suites import `turn.s` plus `ui_trampoline_stubs.s` and rely on that file as the common stub surface for game-only helpers.
- **Resolution:** Add a shared no-op `level_change_generate_current` stub to `commodore/common/ui_trampoline_stubs.s` so the non-transition tests assemble again, while keeping focused tests free to override it locally.
- **Rule:** **Whenever a shared gameplay file gains a new call into main-loop/overlay transition helpers, audit the common C64 test stub surface (`ui_trampoline_stubs.s`) in the same change. Do not assume only the focused test needs updating.**

## 2026-03-23 — Test doubles must preserve the real helper contract, not just compile

- **Issue:** `test_main_loop` kept failing after the recall refactor even though the gameplay stairs path was fine.
- **Root Cause:** The test stub for `check_stairs_at_player` returned the raw tile byte (`$90`) while the real helper returns the extracted tile-type nibble (`9`). That made the harness report “no stairs” even though the real game contract was unchanged.
- **Resolution:** Make the stub mirror the real helper semantics by shifting the tile byte down before returning it, then re-run the suite under VICE to prove the failure disappears.
- **Rule:** **When patching in a test helper, copy the behavior contract as well as the symbol name. A stub that returns the wrong representation creates fake regressions and wastes debugging time.**

## 2026-03-23 — The authoritative affected-platform suite is the gate, not partial evidence

- **Issue:** I made shared-code changes, saw partial/focused test evidence, and continued working even after the user's local authoritative suite was failing.
- **Root Cause:** I treated narrower checks, partial platform coverage, and environment-specific debugging evidence as sufficient to keep moving. That violated the real contract: the repository's authoritative suite for the affected platform is the release gate.
- **Resolution:** If a change affects C64 behavior, require a clean local `make test` before calling the work done, ready, verified, or committable. If a change affects C128 behavior, require `make test128-fast`, and require `make test128` for high-risk banking/layout work. If my environment disagrees with the user's local failing run, treat the user's failing run as authoritative and keep working until that exact suite is green again.
- **Rule:** **Do not claim completion, readiness, verification, or commit-worthiness for affected-platform work until the authoritative suite for that platform passes. When the user's local run fails, that failing run is authoritative until I make the same suite pass.**

## 2026-03-23 — C64 runtime suites must keep the final BRK at the end of the "Test Code" segment

- **Issue:** `test_render.s` failed as `0/4` even though the test logic itself was fine.
- **Root Cause:** The whole suite body lived inside the `"Test Code"` segment, so `run_tests.sh` extracted the wrong breakpoint address and stopped on a helper return instead of the final BRK after copying `tc_results` to `$0400`.
- **Resolution:** Use the standard C64 bootstrap/exit-trampoline pattern: a small `"Test Code"` segment with the startup jump and exit copy loop, and keep the final BRK at the end of that segment.
- **Rule:** **If a C64 suite is run by `run_tests.sh`, the `"Test Code"` segment must end at the exit BRK that copies results to `$0400`. Do not leave the whole suite body inside `"Test Code"`.**

## 2026-03-23 — Large C64 suites that touch the dungeon map must assert they stay below MAP_BASE

- **Issue:** `test_effects.s` timed out because it silently overwrote itself.
- **Root Cause:** The suite grew into the `$C000` map region. Later dark-room/map-fill tests wrote through the dungeon map helpers and corrupted live test code/data.
- **Resolution:** Move large scratch buffers into a separate segment and add an explicit assert proving the executable test body stays below `MAP_BASE`.
- **Rule:** **For C64 suites that import map-generation/render code and also carry bulky local buffers, keep the executable test body below `MAP_BASE` and assert that contract directly.**

## 2026-03-23 — For bad-merge backlog questions, compare the merged branch against the named source branch first

- **Issue:** I started proving the stale build-plan bugs from local history/code evidence before checking the exact branch the user identified as the pre-merge source of truth.
- **Root Cause:** I anchored on the merged result first instead of diffing the bad target branch against the known-good source branch immediately. That risks catching stale reopenings while missing legitimate backlog items that were dropped by the merge.
- **Resolution:** When the user names the source branch of a bad merge, compare that branch against the merged target first and use that diff to decide both directions of the repair: what must be removed and what must be restored.
- **Rule:** **For merge-fallout doc repairs, do not patch from memory or partial history. Diff the merged branch against the user-named source branch first so stale reopenings and dropped backlog items are handled together.**

## 2026-03-24 — Before claiming a fix is ready, inspect the whole workspace and remove stray side-track edits

- **Issue:** I reported a good two-file C128 JAM fix while the workspace still contained unrelated uncommitted `main.s` / test-runner changes and a half-finished `special_rooms_banked.s`, which made the user's next local build fail.
- **Root Cause:** I validated the targeted fix but did not re-check `git status` and reconcile unrelated in-flight edits before telling the user the tree was ready to test.
- **Resolution:** Before saying a fix is ready, inspect the full working tree, build from that exact tree, and either revert or explicitly call out any unrelated uncommitted edits that could affect the user's build.
- **Rule:** **Do not present an uncommitted fix as ready until the actual workspace is clean except for intentional files, and the build/test results come from that same exact tree state.**

## 2026-03-24 — Reproduce C128 runtime bugs from the user's exact disk-image path before blaming stale artifacts

- **Issue:** I initially leaned on a "current disk image looks fine" theory even after the user was reproducing the JAM from `make clean128; make disk128`.
- **Root Cause:** I checked assembled overlay bytes and prior smokes before grounding the investigation in the exact build-and-run path the user was actually using.
- **Resolution:** For C128 boot/runtime crashes, first rebuild with the user's exact target sequence and treat that D64 path as the primary truth before narrowing the fault to runtime ownership or control flow.
- **Rule:** **When a user reports a C128 crash from a specific `make ...` disk path, reproduce from that exact path first. Do not spend time on stale-build theories until that path is ruled out.**

## 2026-03-24 — Treat `$E000` ownership as invalid after tier activation unless the overlay is explicitly restored

- **Issue:** Entering dungeon level 1 on C128 could JAM in `spawn_special_room_monsters` even though the dungeon-generation overlay had loaded correctly.
- **Root Cause:** `tier_check_transition` reused `$E000` for tier payloads and invalidated the overlay, but `level_change_generate_current` still called post-generation special-room helpers that lived in the dungeon-generation overlay window.
- **Resolution:** After any C128 tier transition that can reclaim `$E000`, explicitly reload the required overlay before calling helpers that still execute from that window, and add a regression that proves the helper runs after the restore.
- **Rule:** **On C128, once a step like `tier_load` reuses `$E000`, assume overlay-resident helpers are dead until the overlay is explicitly reloaded.**

## 2026-03-27 — In Commodore text UIs, verify glyphs in the active screen-code charset instead of assuming ASCII punctuation survives

- **Issue:** I used source-level `\` characters in the new C64/C128 help diagrams assuming they would render as clean diagonals.
- **Root Cause:** The UI renderer writes screen codes, not PETSCII, and the active Commodore upper/graphics-style charset does not show a plain ASCII backslash for those codes.
- **Resolution:** For pseudo-ASCII UI art, validate each punctuation glyph against the active screen-code charset and prefer screen-code-safe alternatives over “looks right in source” characters.
- **Rule:** **On C64/C128 text screens, do not trust ASCII punctuation by inspection alone. If a glyph matters visually, verify it in the active screen-code charset before shipping it.**

## 2026-03-27 — If the charset makes ASCII-art fragile, switch to a glyph-independent layout instead of stacking more punctuation hacks

- **Issue:** After removing `\`, I still tried to preserve the diagonal look with alternate punctuation, and the result was visibly wrong on the real help screen.
- **Root Cause:** I optimized for “keep the original line art” instead of stepping back and choosing a layout that does not depend on uncertain diagonal glyphs at all.
- **Resolution:** When the active charset makes pseudo-ASCII art unreliable, prefer a clean grid or labeled layout that communicates the same information without fragile connector glyphs.
- **Rule:** **On Commodore text UIs, if a diagram depends on ambiguous punctuation, redesign the diagram around stable glyphs instead of iterating through punctuation substitutes.**

## 2026-03-27 — For UI layout changes, logical correctness is not enough; review the visual spacing as a composition

- **Issue:** The first glyph-independent keypad layout was technically correct but still looked cramped and awkward on the live C128 help screen.
- **Root Cause:** I stopped once the data was correct and the tests passed, without judging whether the spacing actually read well as a composed 80-column page.
- **Resolution:** For visible UI copy/layout work, review the actual rendered balance: spacing between columns, whitespace around legends, and whether grouped elements read as intentional blocks.
- **Rule:** **For text-mode UI layout changes, do not stop at “correct data.” Check that the rendered spacing and grouping look deliberate on the target screen.**

## 2026-03-27 — When closing a backlog item, update the active plan and the history archive in the same pass

- **Issue:** I closed `BUG-HELP-PAGING` in the implementation record but left `commodore/BUILDPLAN.md` showing it as open, which made the active backlog inaccurate.
- **Root Cause:** I treated the task log as sufficient proof of closure and did not reconcile the project-facing backlog docs that are supposed to reflect current state.
- **Resolution:** Whenever a build-plan item is finished, update both `commodore/BUILDPLAN.md` and `commodore/BUILDPLAN_HISTORY.md` together before declaring the work closed.
- **Rule:** **A completed backlog item is not actually closed until the active plan removes it and the history archive records it in the same pass.**

## 2026-03-28 — When the user chooses the authenticity tier, stop framing it as an optional later enhancement

- **Issue:** I presented variable search odds as a scope fork even after the user made it clear they wanted the more authentic behavior.
- **Root Cause:** I kept the design framed around minimum-risk phasing instead of immediately collapsing the open branch once the user picked the authenticity side of the tradeoff.
- **Resolution:** When a user explicitly chooses the higher-authenticity path, update the active design and recommendation immediately so the chosen tier becomes the baseline rather than a deferred option.
- **Rule:** **Once the user selects the authenticity-focused variant, do not keep the lower-fidelity variant as the implicit default in planning docs or recommendations.**

## 2026-03-28 — When original-game UI behavior is confirmed, elevate it into the feature contract immediately

- **Issue:** After confirming that `umoria` shows a persistent `Searching` status-line indicator, I still framed message-only feedback as acceptable for the feature.
- **Root Cause:** I separated gameplay authenticity from UI authenticity too aggressively, even after the upstream UI contract was verified.
- **Resolution:** Once upstream UI behavior is confirmed and the user wants authentic behavior, move that UI element into the required scope instead of leaving it as a possible follow-up.
- **Rule:** **For authenticity-driven features, verified upstream UI indicators are part of the contract unless the user explicitly agrees to defer them.**

## 2026-03-28 — Preserve the incoming command register across state-clearing helpers in command decode

- **Issue:** After the search-mode work landed, `Shift+direction` running stopped working on C64 even though ordinary movement still worked.
- **Root Cause:** `cmd_run` called `player_search_mode_off` before decoding `CMD_RUN_*`, but the helper clobbered `A`, so the subsequent `sbc #CMD_RUN_N` computed the wrong run direction.
- **Resolution:** Preserve the command byte across helper calls in decode paths, and add a regression that asserts `CMD_RUN_E` still reaches `CMD_MOVE_E` while search mode is cleared.
- **Rule:** **If a command handler needs the original command byte after calling a helper, preserve `A` explicitly; do not assume state-clearing helpers leave decode registers intact.**

## 2026-03-28 — For authenticity-driven interaction rules, verify the specific upstream behavior before freezing the contract

- **Issue:** I wrote the search-mode design and implementation to clear searching on run entry, but `umoria` does not appear to do that and its manual explicitly discusses running while search mode is on.
- **Root Cause:** I verified the broad search-mode behavior but did not verify the narrower run/search interaction before turning it into a design rule and shipped behavior.
- **Resolution:** Recheck the exact upstream interaction before finalizing disturbance rules, then align both the docs and the shared run path with that verified behavior.
- **Rule:** **When a feature is being implemented for authenticity, do not infer sub-behaviors like run/search interactions from the current port or from convenience; verify them directly in upstream sources before locking the contract.**

## 2026-03-28 — When an alternate harness disagrees with the user's exact failing suite, the exact suite is the only truth that matters

- **Issue:** After the user reported `make -C commodore/c128 test128-fast` failing, I talked about a direct `harness128.py` timeout as if it might explain the problem instead of first making the user's exact suite pass.
- **Root Cause:** I treated a secondary harness discrepancy as meaningful diagnostic framing before closing the loop on the authoritative command the user actually ran.
- **Resolution:** Reproduce and fix the exact failing command first, and only discuss alternate harness behavior after the authoritative suite is green and clearly separated from the real issue.
- **Rule:** **Do not describe a failure as “just a harness issue” when the user's exact suite is red. The exact failing command remains authoritative until it passes.**

## 2026-03-30 — For launcher targets, match the user’s known-good invocation before changing the artifact

- **Issue:** I changed the `run128` recipe based on what I thought VICE’s drive flags should do, even though the user had already demonstrated that launching `x128` directly against the disk image worked.
- **Root Cause:** I treated the emulator launch syntax as interchangeable and started changing disk boot artifacts before first aligning the target with the exact known-good command shape.
- **Resolution:** When a disk image works by direct manual launch, make the wrapper target mirror that exact invocation first; only revisit the artifact if the mirrored command still fails.
- **Rule:** **If the user has a known-good emulator command, make the wrapper target match it byte-for-byte in spirit before diagnosing the disk image itself.**

## 2026-03-30 — Default run targets must track the real shipping artifact after a build-system refactor

- **Issue:** After the dual-entry shipping disk was finished, I left `run128` pointing at the standalone C128 debug disk instead of the unified shipping disk.
- **Root Cause:** I fixed the immediate wrapper behavior but failed to re-audit which artifact the target should launch after the product contract changed.
- **Resolution:** Once the shipping artifact changes, immediately review `run`, `run64`, `run128`, and similar wrapper targets to ensure the default ones exercise the real product path.
- **Rule:** **If a feature changes what “shipping” means, default run targets must follow the shipping artifact. Debug images should only stay on explicitly named debug targets.**

## 2026-03-30 — Compatibility aliases must not keep producing deprecated artifacts

- **Issue:** Even after the unified disk shipped, the build still emitted standalone `moria64.d64` and `moria128.d64` files.
- **Root Cause:** I preserved old target behavior instead of converting the old target names into aliases of the new shipping artifact.
- **Resolution:** When an artifact is retired, remove its build rule entirely. If old target names must survive for compatibility, point them at the new canonical artifact rather than producing deprecated files.
- **Rule:** **A compatibility alias may preserve a target name, but it must not preserve a retired artifact.**

## 2026-03-31 — For shared fallback boot art, simplify the composition before inventing platform-specific title hacks

- **Issue:** When the plaque-based fallback logo still looked awkward, I started layering a C128-only runtime title overlay on top of it instead of first fixing the shared composition.
- **Root Cause:** I treated the platform-specific rendering artifact as the primary problem even though the user was pointing at a broader composition issue: too much plaque structure, too much empty space, and the title not owning the center.
- **Resolution:** For cross-platform fallback art, first simplify the shared source design to the strongest readable shapes, then only add platform-specific rendering logic if the simpler composition still fails.
- **Rule:** **If a fallback logo looks awkward on both platforms, fix the shared composition first. Do not reach for platform-specific overlay tricks until the source design is already clean.**

## 2026-03-31 — For shared logos, the C64 width budget must drive the wordmark before the C128 scale

- **Issue:** After simplifying the fallback logo, I still left the `MORIA8` wordmark too wide for the C64 frame because I was judging the shape from the larger C128-friendly version.
- **Root Cause:** I reused a broad block-glyph treatment on the `160x200` source instead of treating the C64 version as the tightest width budget that the shared design has to satisfy.
- **Resolution:** For shared cross-platform logo art, size and condense the title against the smallest target first, then confirm the larger platform still looks balanced.
- **Rule:** **When one shared logo feeds both C64 and C128, the C64 width budget is authoritative for the wordmark. If it nearly touches the frame on C64, it is too wide.**

## 2026-03-31 — Matching style across platforms means reusing the same glyph family before inventing a new small-font look

- **Issue:** My first attempt to fix the C64 width problem used a separate condensed font, which solved the width but made the wordmark look like a different design from the C128 version.
- **Root Cause:** I optimized for fit first and style second, instead of asking whether the smaller target could simply use the same base glyph family at a smaller scale.
- **Resolution:** When a shared logo needs to fit a smaller retro target, try the same glyph family at a reduced scale before designing a second font. Only diverge if the shared glyphs truly do not survive.
- **Rule:** **For shared logo work, preserve the glyph family across platforms whenever possible. Scale first; invent a second font only as a last resort.**

## 2026-03-31 — When a new boot regression appears in a branch-local feature delta, isolate that delta before rewriting older loader code

- **Issue:** After the C128 boot-art handoff started hanging after `128.RUNTIME`, I started patching the older `c128_load_runtime_low_prg` path instead of first isolating the branch-local handoff change that introduced the regression.
- **Root Cause:** I let the monitor trace pull me into the deeper loader stack and ignored the stronger fact that this path had already worked earlier in the same branch before the recent handoff tweak.
- **Resolution:** Treat a fresh regression in an in-progress feature branch as a delta-isolation problem first: compare the current branch-local changes against the last known-good branch state, revert speculative loader surgery, and fix the smallest handoff change that actually regressed behavior.
- **Rule:** **If a path worked earlier in the branch and breaks after a small feature tweak, isolate the feature delta first. Do not rewrite older shared loader code until the branch-local regression has been ruled out.**

## 2026-04-26 — Active lessons compaction archive

The following detail was moved out of `tasks/lessons.md` to keep the active playbook small. Keep future incident-specific lessons here unless they are durable enough for the active file.

# Lessons Learned

Active playbook only. Keep this file short, durable, and reusable.
Move incident-specific postmortems and older detail into `tasks/lessons_archive.md`.

## Verification

- When the user asks for active doc cleanup, move completed material out of `tasks/todo.md` and `commodore/BUILDPLAN.md` into `commodore/BUILDPLAN_HISTORY.md` verbatim before rewriting active docs. Do not leave stale `[x]`, "recently completed," or resolved-state blocks in active planning files.
- When an action creates or removes a remote floor-visible object without moving the player, set the existing scene-redraw latch at the mutation site. A correct floor table and `FLAG_HAS_ITEM` update is not enough if the post-action renderer can choose the local redraw path.
- Do not satisfy a “not wall” visual/inspect bug with a generic nearby message. If the user-visible object is a glyph/rune, the regression must assert glyph/rune copy, not merely any non-wall description.
- For placement spells that store state separately from terrain, prayer-row tests must exercise the user-visible inspect/look path after placement, not only spell dispatch, placement bookkeeping, renderer glyphs, or monster interactions.
- Do not move the C64 live cast/pray modal entry path into the copied `$F000` banked payload. That path nests input, KERNAL keyboard IRQs, and overlay trampolines; keeping it resident is safer than trying to maintain `$01`/IRQ invariants across every nested return.
- If the user says the live spell/prayer cast still only beeps after a helper-level green test, stop treating the helper as the owner. Trace the full product cast -> execute -> restore path and find the live message-clobber seam before claiming the fix.
- If the user says a live command key still does nothing after a pure key-mapper test is green, stop treating `petscii_to_command` as sufficient proof. Trace the full product path through input, dispatch, trampoline/overlay load, and target routine before claiming a live input fix.
- If the user provides a VICE snapshot for an unchanged live repro, make that snapshot the gate immediately. Do not close the issue from static contracts or ordinary suite greens until the snapshot path itself reaches the expected screen/state transition.
- When two plausible owners can be separated by one quick live question, ask that first before diving into emulator instrumentation or snapshot micro-probing.
- Treat the user's exact failing command or repro as the primary gate until it passes.
- Before any commit in a dirty worktree, audit every tracked modified file and classify it explicitly as in-scope, out-of-scope, or user-owned. Do not assume "files I touched this turn" equals the full intended change set.
- On multi-platform feature work, re-run the exact build/test gate for every affected platform before calling the work complete; one green target does not cover the other.
- On C64, do not write shared modal/help cancel policy as if PETSCII `ESC` were a real hardware key. If the UX wants an escape-equivalent on C64, define it explicitly in terms of `RUN/STOP` and use a shared helper instead of scattering raw `$1b` compares.
- On C128, do not assume host `Escape` in VICE proves or disproves the emulated `KEY_ESC` path. Keep the real `ESC` contract, but for modal/read-only dismissal prefer a second platform-native fallback such as `STOP` when emulator mapping is visibly unreliable.
- On C128, do not move code behind KERNAL-space addresses into the banked `$F000` payload if low-RAM/runtime code still jumps to those symbols while KERNAL-visible state is active; verify the linked symbol address, visible execution bank, and callsite banking together.
- When sibling repo checkouts or worktrees exist, verify the exact target repo path before editing, building, or concluding an asset is missing.
- For parity questions against upstream Moria, use the local source trees in `~/Projects/thirdparty/umoria` and `~/Projects/thirdparty/vms-moria` first; do not browse the web when the canonical reference code is already checked out on disk.
- When the user asks to document or write down a plan, stop at the planning artifact. Do not begin implementation without a separate explicit go-ahead to execute code changes.
- Do not call visual asset or boot-presentation work done from a green build alone. For C128 boot art, require a real poster-validating runtime check before treating compression or format changes as successful.
- For live platform/config-specific regressions, build an exact automated repro of that same path before changing product code. If the automation does not go red the same way, do not ask the user to validate speculative fixes.
- For C128 title `L`, distinguish “save disk already mounted before `L`” from “program disk still mounted, prompt to insert save disk.” A smoke that waits for the old first swap prompt is invalid evidence for the mounted-save-disk user path, and a mounted-save-disk harness must allow direct resume before any swap breakpoint.
- For VICE native-monitor boot repros, do not trust the monitor log alone for crash detection. `JAM` can be emitted on emulator stdout/stderr, so exact repro harnesses must capture both monitor output and process output before deciding a boot passed.
- Do not claim a fix from theory, partial tests, or neighboring evidence while the live gate is still red.
- For visual, boot, and interaction bugs, the user-visible path outranks synthetic harness evidence.
- Re-run the exact reported gate after each candidate fix before changing your conclusion about status.
- Do not run the exact C64 and C128 make gates in parallel. They share generated artifacts and VICE/harness state closely enough to turn a clean product tree into a fake timeout or stale-output failure.
- If the user says the live product repro is unchanged, treat any local smoke or control-flow theory as incomplete immediately. Do not ask for trust; go find the next real owner in the live path.
- If the user says a sibling bug is separate and out of scope, stop using it as a control path or discriminator. Keep the diagnosis anchored to the exact reported owner set.
- If the user names the exact live entry keys for a repro (`W`, `T`, `M`, `P`, `D`), do not silently translate that into a different `?` path. Keep the investigation attached to the literal command entry the user reported.
- For C64 prompt text corruption, inspect the live screen RAM bytes before chasing input flow. If the dynamic range letters are wrong bytes in `$0400`, fix the prompt patcher/encoding seam first.
- When changing behavior inside an already-red suite, do not treat the unchanged top-level suite count as evidence. Inspect the per-test deltas in that red suite before claiming the targeted path is covered.
- When a feature or bug fix lands and merges on another branch, immediately reconcile `commodore/BUILDPLAN.md`, `commodore/BUILDPLAN_HISTORY.md`, and `tasks/todo.md` in the current branch. Do not leave already-shipped work marked as open just because the implementation and backlog updates happened out of phase.
- When cleaning `tasks/todo.md`, do not stop after removing whole closed eras. Scan mixed lower sections too, and remove any top-level bug or feature block that is already fully checked and finished.
- Do not leave active backlog items under opaque reused IDs from completed history. If an old `OPT-N` now means a conditional reserve or different scope, rename the active item to a descriptive ID before asking the user to keep tracking it.
- If a live prompt path visibly labels choices with lowercase letters, normalize the real lowercase PETSCII on that path before subtracting `$41`; otherwise a real `a/b/c` selection can fall straight into `Never mind.` while uppercase-only tests still pass.
- For C128 mixed-case message corruption, do not keep chasing encoding after the user says the live repro is unchanged. Re-check the symbol's actual resident owner and address first; a string drifting into overlay or staged-only space can render identical garbage.
- Once the fix is in, the relevant targeted gates are green, and independent tester signoff is green, stop; do not churn on redundant broad reruns after a transient harness hiccup unless the user explicitly asks for more proof.
- For gameplay-facing feature work, do not rely on helper-level spell tests as evidence that the live command path is safe. Add at least one direct cast/study/pray runtime path per platform before handing the feature back for manual testing.
- For spell/prayer row work, keep product-path proof and row-proof separate in your head. A live cast/pray smoke proves dispatch ownership; it does not automatically prove exact silence, no-target, or bookkeeping contracts.
- When a C64 command opens a second-step selectable prompt, do not assume the generic follow-up helper is the right owner. Fix the specific command path first, because widening a shared helper can silently break unrelated prompt flows that relied on the old no-op contract.
- When the user says a live repro is from a fresh build and provides matching evidence, stop arguing old-session/stale-binary theories. Treat the live repro as authoritative and go find the real product seam.
- On C64 PETSCII selection prompts, do not assume letter picks arrive as uppercase only. If a live overlay uses `a-b-c` style letters, normalize lowercase PETSCII before subtracting `$41`, or the prompt will silently reject valid unshifted keypresses.
- When code is already executing inside an overlay, do not bounce back into that same overlay through a resident trampoline just to call a sibling UI routine. On C64, that can unwind through the trampoline epilogue and return control to gameplay while the overlay remains painted on screen.
- For C128 gameplay crash reports, do not trust a special `C128_TEST_*` build as proof for the shipping image. Add or use a product-image repro that boots `commodore/out/moria8-c128.d71` and drives the real input path before claiming the live bug is covered.
- For filtered inventory prompts, the selection letters are contiguous visible entries, not raw carried-slot letters. A book in carried slot `B` is still selected with `A` if it is the first visible filtered item.
- In monitor-driven runtime smokes, once the pass trap is reached, treat that as the primary result. Do not classify the run as a product JAM because VICE later hit a cycle limit after the `BRK` pass trap and no follow-up monitor command exited the session.
- For spell UI regressions, prove which live overlay the screenshot actually exercised before patching product code. `m -> ?` and `m -> book -> ?` are different owners and need different assertions.
- If a visual corruption complaint is about a modal/rendered path, add a product-path text assertion at the live overlay callsite itself so the test stops while the screen is still painted. Post-dismiss checks are too weak for this repo.
- If a C64 prompt-time overlay smoke only asserts the screen before the overlay reads its next key, it cannot catch a live self-dismiss bug caused by re-consuming the initiating `?`. For C64 prompt-time overlays, also enforce the fresh post-overlay key contract in source-level or runtime coverage.

## Regression Ownership

- When reconciling a squash merge, do not infer that a deleted asset means the build should be patched around it. If a referenced commit or feature branch intentionally added a generated-asset pipeline, restore the asset and pipeline together before changing Makefile dependencies.
- Before accepting branch-side file deletions in a squash merge, check whether the deleted file is still wanted on the target branch. For docs/assets like `artwork/CREDITS.md`, preserve the target-branch file unless the user explicitly wants it removed.
- If the user says a command or harness was green before your change and is now red, treat that as your regression until the exact command is green again.
- Do not label a red aggregate suite as “the existing baseline” unless you actually proved that with a pre-change run in the current repo state. If the user says the tree was clean before your work, the red gate is yours until it is green again.
- Do not dismiss new failures as harness noise until you have ruled out your own layout, build, or orchestration changes.
- When a floor item appears to block movement, do not blame item flags or rendering first. `player_try_move` only blocks on `FLAG_OCCUPIED`, so validate the live monster table and stale occupied-bit contract before patching UI or map-item code.
- If performance is part of the contract, do not close the bug with a slower fallback unless the user explicitly approves that tradeoff.
- On this repo, any VICE monitor helper that talks to `127.0.0.1` must be run outside the sandbox. A sandboxed localhost connect failure is a test-environment bug, not product evidence.
- For VICE power-cycle automation, do not assume the remote monitor socket survives `reset 1`. Reconnect the monitor explicitly after the reset before issuing the next `until` or prompt command.

## Scope And Design

- For shared C64/C128 UI renderers, do not emit raw mixed-case screen-code literals through `screen_put_char` unless the bytes are valid for both backends. If a shared path needs explicit letters, prefer PETSCII-safe uppercase bytes or add a test that inspects the rendered bytes.
- On C128 VDC gameplay rendering, keep full-frame `render_viewport` and per-tile `render_single_tile` overlay precedence in lockstep. If one path draws glyphs/items/monsters/player differently, `vis_room_revealed` or modal restores will erase live state until a later local redraw repairs it.
- On 6502 UI code, do not assume `screen_put_char` preserves `A` or `Y`. If you need to emit the same literal twice or keep an index alive across character writes, reload the literal and move the index to preserved state first.
- For compact monster/recall views, do not render placeholder attack slots with zero dice or sides as literal `0D0` data. Treat zero-damage attack entries as absent until real recall knowledge exists.
- On this project, do not shorten user-facing strings to recover C64 bytes without explicit user consent. Treat visible copy as part of the product contract and recover space elsewhere first.
- When a new visible title/boot regression appears on the active branch, freeze the unrelated save/load chase immediately. Restore the title path to the last proven product contract before treating later save/load evidence as meaningful again.
- On this C128 title path, disabling a cache flag is not the same as restoring the older loader contract. If the live regression came with a new loader/helper path, revert the active call path itself instead of leaving the new helper in control and hoping the symptoms disappear.
- When the user broadens a repro, redesign around the shared owner, not the first visible trigger or old bug label.
- When the user narrows a bug to one platform, stop assuming the shared path is primary; isolate the platform-owned seam with a targeted repro before widening the fix.
- When the user corrects a failing asset, overlay, or symbol name, re-anchor on that exact target before continuing; the wrong filename can point at a completely different owner and failure mode.
- For guided setup UX, trigger the flow at the first real operation that needs the resource, not earlier in the surrounding journey; forcing setup too early turns normal progression into a regression.
- On FEAT-DISK, `L`oad and writable setup are different contracts. First-time load should validate an existing save disk only; only explicit Disk Setup or a real save path may offer initialization.
- If title `L` is running in one-drive mode and the program disk is no longer mounted, do not return to title/menu just to explain a wrong save disk. Keep the user inside the save-disk retry loop until they present a valid save disk.
- On tight C64 code, put explanation text in the overlay/banked UI when possible instead of the resident caller. The user still needs the reason, but the resident title path should only carry the control decision.
- In Kick Assembler lookup tables, do not use escaped `.text` forms for single-byte punctuation keys. For characters like backslash or quote, emit the exact byte explicitly and verify table count against pointer-table count, or later entries can shift silently.
- On C64, a live hang with low-RAM PC values and repeated `IRQ -> $FFFF` is a banking-contract bug first: assume `$01=$35` leaked into an interrupt-driven input loop and harden the prompt/return seam before blaming disk I/O.
- On C64, any helper that can be called from overlay or banked spell/combat code must preserve the caller’s interrupt state. `creature_get_name` ending with an unconditional `cli` was enough to reopen IRQs under `$01=$35` and send the next interrupt to `$FFFF`.
- In C64 unit harnesses, never patch a 1-byte stub with a 3-byte `JMP`. `test_effects.s` test 37 was corrupting adjacent code because `test_spell_list_display` and `test_spell_execute_selected` were bare `RTS` stubs in `ui_trampoline_stubs.s`; shared patch targets need explicit 3-byte slots plus spacing asserts.
- On C64, treat title/UI re-entry as its own banking boundary: normalize back to `$01=$36`, restore the runtime IRQ wedge, and repair VIC bank state at the boundary itself instead of trusting each preceding KERNAL caller to leave UI code in a safe state.
- On 6502, never try to carry saved processor state across a `JSR`/`RTS` boundary on the hardware stack; if a helper must preserve flags across separate enter/exit routines, save them in explicit memory and rebuild `P` locally before return.
- On 6502, audit both sides of the flags contract, not just the callee. A caller-side `plp` after `jsr c128_load_title_art_bank1` was still a live stack corruption bug even though the callee already restored LOAD carry before `rts`.
- On C64, if a new crash PC lands in the middle of a valid instruction after adding `PHA`/`PHP`-style bookkeeping around an interactive path, treat it as a stack-return regression first and prefer an existing scratch byte over carrying state on the stack across prompts.
- On C64, do not use `php/plp`-style wrappers around save/load entrypoints that need a carry result or a stable post-I/O bank state; normalize `$01` explicitly on return instead of restoring stale flags.
- On C64, do not reopen IRQs inside a disk/KERNAL helper that returns to overlay-owned UI state; let keyboard/input routines own their own IRQ window, but keep overlay disk-validation paths synchronous or you can turn screen writes into page-1 corruption.
- On C64, for overlay-driven disk validation paths, preserving only `$01` and flags is not enough; treat caller ZP/UI scratch as contaminated by KERNAL serial calls and restore it explicitly before returning to screen clear/print code.
- On C64, do not resume the same overlay frame after KERNAL disk I/O. Make the overlay disposable, keep it display/input-only, and move the disk state machine into resident or banked non-overlay code that re-enters the overlay fresh for each step.
- On C64, a redesign that removes disk I/O from the overlay is still not enough if multiple helpers each “restore enough state” locally. FEAT-DISK needs one authoritative owner of `$01`, interrupt policy, IRQ/editor legality, and stack assumptions across the full transaction, or the bug will keep moving between `$34`, `$36`, and `$37` contexts.
- When a C64 failure keeps moving between low-RAM crashes, IRQ-vector collapses, and KERNAL/editor returns, stop patching seams and instrument the full transaction first. Find the first illegal transition before making another behavioral fix.
- On this C64 layout, even debug-only diagnostics can violate hard ceilings. Before committing to in-code tracing, check whether the resident and banked segments have enough slack for the tracer itself; if they do not, shrink the diagnostic design first instead of forcing a larger “temporary” trace into the image.
- On C64, if a helper body lives in ROM-shadowed RAM (`$A000-$BFFF` or `$F000-$FFFF`), do not return to it directly from a KERNAL vector. Route the KERNAL call through an always-visible low-RAM trampoline or keep the whole helper on a substrate that stays executable across the call.
- On C64, if a FEAT-DISK read path leaves menus echoing typed characters or only accepting input after Return, assume KERNAL channel ownership leaked back into the screen editor. Do not split `CHKIN -> CHRIN -> CLRCHN` across generic wrappers; own the full read transaction in one low-RAM helper and resync the normal UI runtime on return.
- On C64, repeated one-drive swap prompts should use the same modal dismiss helper as the FEAT-DISK screens, not raw `input_get_key`. The explicit buffer flush + release wait prevents the second prompt from inheriting stale key state from the first swap step.
- On this C64 build, adding a helper low in memory still grows the Default segment and can push both `program_end` and the banked-payload staging window over hard limits. Before choosing “low helper” as the fix shape, re-check the full segment ceilings rather than assuming low placement is free.
- On memory-bound C64 code, if a new control flag pushes `program_end` over `MAP_BASE`, shrink repeated caller-site sequences and shared cleanup tails before touching unrelated behavior. Local byte recovery is safer than another subsystem redesign.
- For C64 FEAT-DISK init on an already formatted disk, prefer “create marker and read DOS status after close” over unconditional disk format. Save-disk initialization and whole-disk format are not the same operation.
- On C64 title/menu entry, if the first command key is ignored after redraw or FEAT-DISK return, treat it as stale keyboard-buffer ownership first. Drain/release the buffer at the title boundary instead of blaming the menu parser.
- On C128, if FEAT-DISK returns to gameplay but controls still appear dead and the monitor sits in `input_poll_key_event` / `cia_scan_petscii`, inspect the follow-up-key release contract before assuming the caller failed to unwind. View restoration and input re-arm are separate seams.
- On C128, a stable live PC inside `cia_scan_petscii` after a modal return usually means the raw scan latches were never re-neutralized, not that FEAT-DISK or redraw is still running. Reset `igk_last_sample` / `igk_stable` at the modal release seam before patching higher-level save flow again.
- When a swallowed-key bug only reproduces on C128 direct-scan input, fix the C128 edge-state reset at the automatic-stop seam first instead of paying C64 resident bytes for a shared cleanup helper. The platform-specific input contract matters more than symmetry.
- On this repo, `CMD_RUN` must clear any old visible/pending message before arming the runner, just like ordinary movement. Otherwise stale `zp_msg_flags` survive into `run_post`, causing immediate run cancellation, resurfaced old messages, and “hidden -MORE-” behavior that looks like pathfinding or input bugs.
- On C128, do not drive run held/cancel logic from raw matrix “any key held” state when shifted commands exist. Use a modifier-filtered sample so bare `Shift`/`Ctrl`/`C=` do not keep a run alive or later count as a cancel edge.
- For C128 running, split the seams correctly: the pre-arm held-state check must still see the initiating `Shift+direction` chord as held, while only the later cancel-edge sample should use modifier-filtered input. Filtering the startup held-state is what caused runs to arm early and self-cancel after a few tiles.
- On C128 direct-scan input, a single zero sample is not a safe definition of “keyboard neutral” for running. The run pre-arm path needs a stable-neutral latch before it arms cancel, or key-release jitter on shifted chords will turn into false cancel a few tiles later.
- When a live stopped-state snapshot only shows `zp_run_dir=$ff` and normal command-loop PC, do not conclude the run must have stopped in gameplay logic. `main_loop !run_cancel` leaves the same cleaned-up state; break on the actual `sta zp_run_dir` stores before assigning blame.
- On C128, do not use `cia_scan_petscii` as the run held/cancel sample source. PETSCII decode is a command/prompt contract, not a physical-held-state contract, and it can synthesize false neutral/cancel edges while a shifted run chord is still physically down.
- When a C128 architectural fix introduces new resident code and the build goes red on segment/layout asserts, do not treat byte trimming as a “quick win.” Ask the user and consultants for the intended ownership/placement strategy first, then move the code into the right segment or asset instead of shaving unrelated bytes until it fits.
- When a C128 layout fix is under discussion, never change player-facing text just to buy bytes unless the user explicitly approves that UX tradeoff. First look for ownership fixes, dead code, redundant instructions, or stale reserved slack.
- On C128, do not park unrelated data inside the Common-RAM MMU helper blob just because the addresses are available. That blob is part of the KERNAL/MMU contract; use ordinary `Default` RAM for cold data unless the bytes are genuinely part of the helper page’s execution contract.
- When the same live trace persists across clean rebuilds, stop patching lower-level seams in place and reframe the subsystem ownership. Repeated scanner-seam tweaks on C128 were wasted motion once the real problem became “FEAT-DISK is modeled as a subroutine instead of a mode transition.”
- On C128, no overlay routine at `$E000-$EFFF` may continue executing across `EnterKernal()`. That MMU transition exposes KERNAL ROM over the same address range, so any post-call return into overlay code is a control-flow bug even if the bytes on disk are correct. Use the resident `w_*` KERNAL wrappers or move the helper off the overlay.
- On C128, a design fix still has to fit both resident ceilings at once: moving code out of the Default segment can solve the staged-source ceiling at `$E000`, but if that code lands in `RuntimeLowData` it can silently collide with the floor-item / ego-item low-RAM ownership at `$1A00`. Check both constraints before calling a redesign “memory-safe.”
- On C128, if a subsystem needs a stable non-overlay owner and neither Default nor `RuntimeLowData` can absorb it, use a dedicated runtime-loaded common-RAM PRG instead of forcing the code back into the overlay or bloating the staged source past `$E000`.
- On C128, do not treat the `w_*` KERNAL wrappers as a persistent file-I/O session API. Each wrapper does its own `EnterKernal/ExitKernal`, so stateful transactions like `SETNAM -> SETLFS -> OPEN -> CHKIN -> CHRIN...` must stay inside one continuous KERNAL window.
- On C128 FEAT-DISK, do not call marker initialization “successful” just because the write path returned. Use the same proven contract as C64: scratch, plain create, write, close, then immediately verify with `disk_marker_present`.
- On C64, do not use a side-effecting drive command like `I0` as a device-presence probe. Presence checks should be passive so they do not trigger false negatives or flash the wrong drive while probing.
- On C64, do not assume `c64_disk_call` preserves `X` or `Y` across a KERNAL call. It forwards the caller's registers into KERNAL, but on return only the accumulator/carry contract is reliable unless you explicitly save other registers yourself.
- On C64 UI code, `screen_put_char` expects screen codes, not raw PETSCII or arbitrary device bytes. If you surface DOS/channel diagnostics directly, convert them to display-safe screen codes or print them as hex instead of trusting the raw byte stream.
- When a selected-device setup branch correctly rejects the program disk, keep the user inside that same drive’s retry loop; do not bounce them back out to a broader menu or a different default drive.
- On C64, REU overlay fetch must preserve the caller’s interrupt state. An unconditional `cli` after DMA creates a live `$01=$34` IRQ window and will collapse into low-RAM/zero-vector crashes even if the overlay logic itself is correct.
- On C64 DOS, do not use `@` replace semantics as the primary save-disk marker-init path. The reliable FEAT-DISK flow is `scratch -> plain create -> write -> close -> verify readback`, with status-channel text used only for diagnostics.
- On this C64 FEAT-DISK path, a positive marker readback is the real success gate. Command-channel bytes can help explain a failure, but they are too drive-specific to be the UI truth if readback and runtime behavior disagree.
- When the user reports that a file still exists after a supposedly successful delete-on-load path, drop any stale-status theory and re-anchor on the delete contract itself before patching the later save path.
- When the user provides a `c1541` directory proving `THE.GAME` still exists after load, treat the current delete helper as a live no-op until proven otherwise. Do not describe internal channel-drain tweaks as progress unless the on-disk directory result changes.
- If a save path already uses overwrite-capable `@0:...` semantics, do not stack an unproven pre-save scratch helper in front of it. Treat overwrite and delete-after-load as separate contracts until the delete path is proven live.
- When the product decision changes the persistence contract, remove the old contract completely instead of carrying both. Keeping delete-on-load/delete-on-death while also adding overwrite confirmation made the code larger, less coherent, and harder to debug.
- On tight C64 resident code, use the semantic simplification first. Replacing “probe -> prompt -> scratch -> retry” with “probe -> prompt -> one overwrite-safe open” was both the correct user contract and the right memory recovery move.
- When a consultant says the overwrite prompt is UI-only, verify the actual write transaction. A `Y/N` prompt does nothing unless the confirmed branch changes the file operation itself.
- When a C64 overwrite fix starts drifting into command-channel scratch parsing, stop and ask whether the product contract really needs scratch at all. For persistent savefiles, a confirmed `@0:THE.GAME,S,W` replace-open is both simpler and smaller than `S0:THE.GAME` plus a retry create path.
- On C64, if save retries from a failed plain create into a confirmed overwrite-open, clear `zp_kernal_status` again at the retry boundary. A stale first `OPEN` failure can poison the first `READST`-checked write even after the later `@0:` open succeeds.
- On C64, do not intentionally trigger a failed plain create just to discover that `THE.GAME` already exists. Probe existence first, then choose either plain create or confirmed `@0:` replace-open; that removes the dirty failed-`OPEN` transaction from the overwrite path entirely.
- If a separate existence probe still leaves the live C64 save path red, move the overwrite prompt back onto the real create transaction and classify the failed plain `OPEN` by command-channel status. The correct branch point is the real create failure, not an untrusted side probe.
- On one-drive C64 flows, do not force a swap-back to the program disk just because save/load completed. Prompt at the next real program-disk dependency, not at the end of every persistence routine.
- If a runtime disk prompt should behave like a modal, make it one. In-place row prompts over gameplay hide state and confuse repros; clear/redraw ownership matters as much as the text itself.
- On C64 one-drive title `L`, do not reuse the generic load entry after fresh setup if that entry always prompts for the save disk. The “save disk already mounted” case needs its own branch or the same `L` will ask twice.
- Do not tie successful load completion to an unproven delete-status parser. If a delete helper is still under investigation, keep the load/read contract separate until the delete behavior is proven live.
- On C64, do not leave `save_game` on plain create semantics while delete-after-load is still unproven. If a leftover `THE.GAME` is part of the live failure, make the save open path overwrite-safe first so save does not hard-fail on an existing file.
- On C64 resident paths, treat richer save-error diagnostics as optional until they fit the `MAP_BASE` budget. If a DOS-status decoder pushes `make test64` red on the memory-boundary gate, back it out before claiming progress.
- When both `THE.GAME` saves and `MORIA8.ID` marker writes fail on C64, stop treating them as separate regressions. Re-anchor on the shared sequential file contract first, especially the read/write secondary-address policy, before patching overwrite UI or marker logic again.
- On C64 sequential writes, do not assume `READST` during or immediately after a `CHROUT` stream is a valid success gate if the known-good file writer in the same codebase does not use it. Prefer the proven contract and let close plus reread/status verification decide the result.
- When one C64 disk path works through `c64_disk_call`/wrappers and another path keeps failing while manually managing `$01`, stop patching the manual path piecemeal. Unify it onto the proven wrapper contract instead.
- On C64 KERNAL file I/O, do not immediately reuse the same logical file number after a failed probe/open path unless you have proved the failure path cleans up correctly. Separate probe and create LFNs when chasing unexplained immediate `OPEN` failures.
- On tight C64 banked payloads, diagnostic helpers must fit both ceilings: staged bytes below `$D000` and logical banked code below `$FFFA`. If a debug helper blows either ceiling, back it out and choose the smaller hypothesis-driven change instead of forcing the tracer in.
- On a fresh C64 save disk, do not pre-scratch `MORIA8.ID` before the first create. A redundant `S0:MORIA8.ID` on a missing file is a plausible transaction poison and adds no value when marker presence was already checked before init.
- When copying a C64 helper image into low RAM for runtime execution, do not nest `.pseudopc` inside the banked payload. Store ordinary source bytes and keep internal control flow branch-relative so the copied image relocates cleanly.
- On C64, moving a helper out of resident code can fix the `MAP_BASE` ceiling while still breaking the banked payload ceiling at `$D000` or `$FFFA`. After every relocation, verify all three limits together: resident end, staged payload end, and logical banked code end.
- On C64, do not use the tape buffer at `$033c` as a runtime helper scratch area for disk/KERNAL work. With JiffyDOS in particular, that buffer is live and may be overwritten during the transaction, turning the helper into self-corrupting code.
- When eliminating a bad runtime substrate, check every sibling helper path, not just the one that crashed first. The C64 marker writer had already moved off `$033c`, but the marker reread dispatcher in `main.s` was still copying code into the tape buffer and kept the live bug red.
- On 6502, never save `$01` and processor flags on the same stack frame and then restore them in the opposite order. In the copied C64 marker helpers, `php ... pla / sta $01 / plp` wrote flags back into `$01` and old bank bits into `P`, which is exactly the kind of control-flow corruption that drops back to BASIC.
- In C64 banked-payload callers, do not restore the caller's old interrupt flags at the end of a raw KERNAL helper if `$01` is being restored to a KERNAL-hidden state. That recreates the exact `IRQ -> $FFFF` failure window; return with IRQs still disabled and let the owning caller re-open them only after banking is safe again.
- When a C64 disk-write bug stays red after multiple transaction fixes, add a focused real-disk runtime repro before more edits. A small PRG plus `c1541` inspection can prove whether the file was actually written and keep you from chasing generic code bugs when the real owner is emulator configuration.
- On VICE/JiffyDOS, check the drive attachment mode explicitly. `AttachDevice8d0Readonly=1` will make fresh marker init and later saves fail while loads still work, which looks like a game-side write bug unless you inspect the emulator resources.
- When common gameplay code grows a new shared symbol, update the focused harness stubs in the same pass. Otherwise `make test64` can go red on assembly-only failures before it ever tells you whether the runtime change works.
- On this project, user-facing copy is part of the UX contract. Do not trim strings to recover C64 bytes; solve space pressure with architecture, layout, overlays, or code deduplication instead.
- When a modal disk-swap prompt should fully own the screen, clear it twice: once before showing the prompt and again immediately after dismiss + media reinit, before any status text resumes. Otherwise stale prompt text will visually leak into the next UI phase.
- For C64 modal screen transitions that still show partial old content while repainting, treat it as an atomic repaint problem before assuming the clear routine missed rows. Blanking the display during the modal repaint is a valid low-risk fix when the final cleared screen state is already correct.
- If a live C64 screenshot proves the modal still leaves only the footer/status block behind, stop reasoning about the generic full-screen clear and clear the owned footer rows explicitly in the modal path. Use the exact visible rows from the screenshot as the contract.
- For FEAT-DISK UX, treat overlay-based setup prompts and runtime modals as separate screen-ownership paths. A fix in `disk_prompt_*` does not automatically fix `ui_disk_setup` dismiss behavior.
- On C64, if a runtime modal still leaks small center-screen remnants after a bulk `screen_clear`, switch that path to the repo’s safer row-by-row full-screen clear instead of layering more special-case footer wipes on top of the bulk clear.
- On C64, if a prompt path temporarily relies on KERNAL-visible bank state, explicitly restore `$01` to the normal gameplay/UI bank (`BANK_NO_BASIC`) before returning. Do not assume the follow-on UI code will repair bank state for you.
- On C128, a resident-to-overlay trampoline is not complete when it only restores the MMU/guard state. If the live path can take IRQs after the handoff, restore both `c128_restore_runtime_guards` and `c128_restore_runtime_vectors` before tail-calling overlay-owned code.
- For C128 preload/title handoffs, add a source-level guard for the exact trampoline sequence in `run_tests128.sh`. The existing boot smokes were not enough to catch a missing runtime-vector restore before the user hit it live.
- On C128, do not treat “reached `load_resume_game`” as proof that title-load resume works. The real live gate is after resumed gameplay re-enters the main loop; stop the smoke at `c128_town_move_diag_loop_top` or later.
- On C128, do not keep a bespoke raw `jsr $ffbd/$ffba/...` runtime PRG loader when the rest of the platform already has wrapped `w_*` / `c128_preload_asset_load` KERNAL transactions. A direct runtime loader can accidentally depend on cold-boot ROM visibility and then fail only when re-entered from all-RAM runtime state.
- On C128, avoid raw monitor breakpoints on symbol addresses that may have ROM visible at runtime. For prompt-detection tests, prefer explicit compiled probes/counters over `break $ADDR`, or the test can flag the wrong code path entirely.
- For VICE CLI resources, `-resource` enables and `+resource` disables. Do not “normalize” those signs by intuition; the earlier swap-smoke regression came directly from flipping `-remotemonitor/-binarymonitor` to `+...`.
- If a C128 smoke needs the remote monitor, keep that socket isolated from the parallel unit phase. Moncommands-only workers must not enable remote/binary monitor in parallel or they can poison later monitor-driven smokes in the same exact gate.
- If a live save/load bug only reproduces on a real resumed dungeon save, a town-level synthetic fixture is too weak. Match the live resume depth/path before treating the automated gate as representative.
- When recovering bytes after a FEAT-DISK UX change, remove dead indirection or duplicate harness plumbing before touching any user-facing string or message contract.
- On memory-bound C64 runtime code, remove C64-dead helper bodies and duplicate internal data before adding pressure to UX strings. Gating `save_file_exists` to C128 and aliasing the plain save filename to `save_replace_filename + 1` recovered resident bytes without product degradation.
- If a save-error path already captured DOS status digits during the failing transaction, reuse those digits at the final message site. Do not open the command channel a second time just to build an error string.
- On C64 save retry paths, read the DOS status before closing the failed logical file number when classifying `FILE EXISTS`. Closing first can disturb the status you need to branch on, while still leaving you to guess why the overwrite retry failed.
- When a live save/load bug depends on real CBM DOS behavior, add a real-disk runtime test before asking the user to retest again. Stubbed unit suites were not enough for the C64 overwrite bug; the useful gate was a temp-D64 integration test that seeded `THE.GAME`, exercised overwrite, and read the result back.
- If a new real-disk integration test disproves the current branch point, change the product code to match the proven contract instead of defending the old seam. For C64 save overwrite, the correct contract was `save_file_exists -> prompt -> plain create or @0 replace`, not “plain create must fail with 63 first.”
- Do not assume `c1541 write` gives you a trustworthy sequential save fixture for dotted filenames. For C64 `THE.GAME`, the host-tool seeding path itself was ambiguous enough that it could not be treated as proof of a production load bug.
- If a new integration test is too heavy or too ambiguous to be a stable default gate, keep it out of the exact reported command until it produces a clean signal. A noisy or cycle-bound diagnostic suite is not a substitute for the exact green gate.
- On C64 title `L`, passing validate-only Disk Setup is not enough by itself. If the mounted-load path skips the same post-insert `disk_init_drive` that the prompted path uses, a valid disk can pass marker validation and then immediately fail `load_game` with `Save file not found.`
- If a live overwrite bug reaches `Disk error 63`, inspect the existence probe before the replace-open path. On this codebase, a separate secondary address for `save_file_exists` was enough to miss `THE.GAME` live while plain create still failed with `FILE EXISTS`.
- A real-disk overwrite test needs to call top-level `save_game`, not just manual `@0:` open/close primitives. The surrogate primitive test stayed green while the actual product overwrite flow still failed live.
- On C64, staging banked source bytes inline in the resident Default segment can violate `MAP_BASE` even if the runtime destination is valid. If the banked payload grows, move the staged source out of Default ownership rather than shaving UI text.
- After a large architectural recovery, rerun all exact gates before chasing new live behavior. A stale harness expectation or a different-platform compile break can hide behind the main bug if you skip the full gate sweep.
- When a retry loop fails only after the first bad disk, inspect the failed-`OPEN` cleanup path before changing higher-level retry policy. On C64 marker reads, the missing cleanup was in the first failed `OPEN`, not in the visible retry loop.
- If a C64 banked fix needs bytes, collapse control flow before touching text. Reusing an existing close/fail path in the marker reader recovered the overlay byte budget without violating the UX-copy contract.
- On C64, the same “no execution from ROM-shadowed code after `$01=$36`” rule applies to banked `$F000-$FFFF` payloads just as much as to overlays. A helper at `$FE67` that flips `$01` to `$36` is self-banking garbage by construction.
- When a C64 helper must perform a continuous raw KERNAL transaction and resident space is tight, use a small resident stub plus owned always-visible low RAM for execution. Do not keep the transaction in banked `$F000` code just because the bytes fit there.
- When adding a bindable shared hook to satisfy focused C64 harnesses, do not automatically carry that abstraction into the C128 production build. If C128 already has the real UI symbol available, call it directly and keep the hook C64-only so the C128 resident/banked ceilings stay intact.
- When public disk loaders change from “return carry on failure” to “prompt and retry until success,” update the focused runtime suites in the same pass. Old tests that deliberately force one failed LOAD will otherwise hang or report empty result buffers because the loader no longer returns on the first error.
- Before patching a newly narrowed interaction bug, verify whether the shared command intentionally stops on visibility or ownership boundaries; an apparent platform-only failure may be the expected shared stop condition in a different live scene.
- If a symptom returns after a seam-specific fix, check sibling paths into the same subsystem before assuming the original fix was lost.
- For scan/classification bugs, verify every sibling data source at the seam before closing it; fixing item lookup alone is insufficient if stale monster lookup can still win on the same blocked tile.
- When the user changes the product target, stop optimizing the old architecture by inertia and restate the new target in the plan.
- When the user asks for a bounded action like “revert” or “build the test,” stop after that action and report the exact state; do not roll straight into debugging the next failure without explicit approval.
- Verify source-game geometry before extending or porting it; do not infer fixed subregion sizes like town from live dungeon dimensions or from older AI-written port code.
- When a fixed logical subregion lives inside a larger backing map, fix both halves of the contract: generation must make the out-of-region space non-presentational, and viewport math must clamp to the logical region rather than the backing buffer.

## C128 Contracts

- For C128 runtime-loaded or banked code, verify together: linked address, PRG load address, destination bank, visible execution bank, and copy-source safety.
- For C128 callable code, verify the full body and its required data stay out of `$D000-$DFFF`; an entrypoint below the I/O hole is not enough.
- When a C128 boot or chain path fails repeatedly, stop patching around symptoms and re-anchor on the proven loader and MMU/KERNAL contract.
- On C128 one-drive title `L`, use the same mounted-load split as C64. After fresh validate-only setup succeeds, branch to a mounted path that performs `disk_init_drive` and then enters the shared load tail without a second `disk_prompt_save`; drive `9` can hide this bug because the redundant prompt path is a no-op there.
- If a C128 load-resume smoke is meant to cover FEAT-DISK validation, seed the disk with both `THE.GAME` and `MORIA8.ID`. A save blob alone only proves load-resume on an already-trusted disk, not the real title `L` validation contract.
- For C128 prompt-policy smokes, do not hand-build a “close enough” boot disk. Start from the real built `moria128.d71` and layer only the test-specific save artifacts or variant main PRG on top; otherwise fixture filename drift will masquerade as product prompt bugs.
- For C128 variant disk builders, replacing only `moria128` is not enough if the variant changes any resident/overlay contract that later loads `128.*` assets. Rewrite the whole variant-owned file set (`128.start`, `128.town`, `128.death`, `128.gen`, `128.help`, `128.ui`, `128.runtime`, `128.fdisk`) or the test disk can silently mix incompatible builds and send the investigation sideways.
- If a smoke needs to prove “no program-disk prompt during title load,” do not break on the raw shared prompt symbol from power-on. Add a targeted test-only probe that resets at title `L` and checks the specific flow boundary you actually care about.
- On C128 preloaded runtime paths, do not leave one overlay as a “temporary” disk exception. A single `OVL_HELP -> disk` bypass in `overlay_load` was enough to make one-drive save-disk flows look like the program disk was still required “just to show a message.”
- On C128, never call a helper imported inside an overlay segment from resident boot/title code as if it were resident. `c128_preload_title_art` lived in `UiOverlay`; a direct `JSR $EC61` from `entry_main` produced a live JAM because the title-entry path violated overlay ownership/execution boundaries.
- On C128 one-drive media tests, a “drive 8 load” smoke is invalid if the test disk still contains both the program assets and the save files. That hybrid `D71` hides exactly the real bug class where the save disk replaces the program disk after boot.
- On C128, program-media loaders must never inherit `save_device`. `c128_load_runtime_prg` loading `128.RUNTIME` / `128.FDISK` from `save_device` was a category error that only shows up once a save disk has been selected or swapped in.
- On VICE remote-monitor automation, `until` should be treated as a stop-text operation, not a prompt-return operation. Waiting for the monitor prompt after `until` caused false timeouts in the new C128 swap harness; the stable approach is to wait for the actual `UNTIL: ... C:$ADDR` stop text.
- On VICE remote monitor helpers, `break` needs explicit `$` address syntax. Sending `break 316A` from the Python helper silently broke the C128 swap smoke even though the equivalent moncommand test worked.
- For C128 monitor-driven gameplay automation, plain ASCII is not enough for all commands. The real save command is `SHIFT+S` (`$D3` PETSCII), so a monitor connector that only encodes ASCII cannot prove save paths.
- For C128 monitor-driven save verification, do not treat host-disk contents after runtime `attach`/`detach` as a trustworthy oracle by itself. First stop on explicit in-game save success/fail probes so the harness proves the product path before it tries to prove host-image persistence.
- When a C128 save/load live bug is about current-build save content, prefer a same-session in-emulator roundtrip over a save-then-quit host-image check. The authoritative proof was `save -> Start Over -> L` inside one emulator session, because that exercised the real product path without depending on VICE host writeback after monitor control.
- On a fresh C128 title `L` automation path, do not skip the drive-9 confirmation branch just because the target scenario is one-drive on device 8. If drive 9 responds, the real input sequence starts with `N` before the one-drive `1` selection and later modal dismiss keys.
- On C128, do not treat a same-session `save -> Start Over -> L` roundtrip as closure for a fresh-build live boot/load hang. If the user reports a cold or fresh-build failure after that gate is green, add the colder reboot/re-entry smoke instead of defending the warmer path.
- On C128, once a colder reboot/re-entry smoke exists, keep it in the exact fast-smoke gate. A green same-session roundtrip plus a missing cold-reset path was not enough to protect against the live fresh-build drive-8 failure.
- On C128 title `L`, do not jump straight from shared `load_game` into resumed gameplay and assume the file-I/O wrappers left runtime state safe. If a success-path prompt or menu seam is removed, reassert the full all-RAM runtime guard/vector bridge explicitly before `load_resume_game`.
- When a C128 fix needs a few bytes and the exact build gate trips a staged-source assert, recover the bytes locally in the same control-flow region before touching product behavior elsewhere. Tightening branches in the title `L` path was safer than backing out the runtime repair.
- On C128, “runtime guards” are not a safe abstraction if they omit the IRQ/CHRIN bridge. Any post-KERNAL runtime resync helper must restore MMU/VDC state and the full all-RAM vector/stub contract together, or live title/load paths can fall into the KERNAL IRQ tail at `$0D06`.
- On C128, do not restore `$0314/$0315` to the startup-captured native IRQ tail address just because KERNAL-visible mode is active. In this build the captured tail can still be `$0D06`, but the program does not preserve executable Screen Editor tail code there; leaving that vector live turns any IRQ into a repeated `BRK` storm at `$0D06`.
- On C128, if a live IRQ bug tempts you to reason about JiffyDOS or ROM-specific tail semantics, stop and inspect whether the game is clobbering KERNAL/editor-owned low-common RAM first. The clean fix is to restore KERNAL-owned workspace at the mode boundary or move runtime code out of that region, not to reverse-engineer a ROM-specific IRQ shim.
- On C128, do not use `SCNKEY` as a raw KERNAL-entry IRQ-owner handoff. The clean contract is explicit mode ownership: runtime/all-RAM uses `mmu_common_irq`, KERNAL-visible windows use `mmu_kernal_irq`, and `EnterKernal_sub`/`ExitKernal_sub` are the only places that flip between them.
- On C128, if a copied runtime helper blob grows past 255 bytes, any `LDX`/`CPX #size` copy loop is now a truncation bug. The common-helper blob reached `$110` bytes, and the old 8-bit loop silently copied only the first `$10`, leaving `mmu_kernal_irq` and `mmu_common_nmi` uninitialized in common RAM.
- On C128, `EnterKernal_sub`/`ExitKernal_sub` must transfer CHRIN ownership with the IRQ owner. If runtime leaves `$0302/$0303` pointing at `chrin_keyboard_stub` during a KERNAL-visible file-load window, ROM/editor input code can re-enter `cia_scan_petscii` against the wrong substrate and crash even when `$0314/$0315` is correct.
- If a live C128 preload crash moves into resident Bank 0 code/data while `$0314/$0315` and `$0302/$0303` are already sane, stop extending the IRQ-owner theory and add a resident-code corruption guard around the first preload transaction. That catches the real scribble seam earlier than the eventual JAM in message/UI code.
- In VICE monitor logs, `BREAK: n C:$ADDR (Stop on exec)` can be breakpoint-registration noise, not proof the breakpoint was hit. For fail/pass traps, prefer matching real `Stop on  exec addr` stop lines or an equivalent explicit hit signal before concluding a guard fired.
- In VICE native-monitor logs, `UNTIL: ... C:$ADDR` is also not trustworthy enough by itself as crash evidence for shipping-image repros. For C128 product gates, prefer the remote monitor’s actual breakpoint-stop semantics over monlog text matching.
- For focused C128 spell/prayer row checks, direct VICE monitor moncommands are a valid verification path when the socket-based Python harness is environment-fragile. Treat that as focused row proof only; keep the product-path make/smoke gate separate.
- On C128 banked gameplay trampolines, restoring `$FF00` alone is not enough after `BankOutKernal()`. Save and restore `$01` too, or the post-call runtime can be poisoned even when the immediate banked call appears to succeed.
- If the user’s active build gate is `make disk128`, do not make the automation stricter than that command by layering a separate `grep "FAILED!"` rejection onto the same build path. Keep the exact reported command as the authority, and move stricter invariant checks into dedicated guards instead of silently changing what “build passed” means.
- A C128 runtime-load repro is not valid unless it proves an IRQ actually fires inside the `128.RUNTIME` KERNAL load window. A direct-boot guard that only watches for pass/fail symbols can still false-green while live hardware falls into a stale software IRQ vector like `$0E06`.
- Do not let the C128 wrapper unit contract diverge from product code. If `test_wrapper_irq128.s` asserts that KERNAL-visible mode owns `mmu_kernal_irq` but `EnterKernal_sub` restores a boot-captured native `$0314/$0315`, the local green test story is invalid before any user rerun.
- In gameplay automation, do not append drive-selection digits to `SHIFT+S` once the session is already configured. Those digits are only meaningful if Disk Setup opens; otherwise they become stray queued input and can make the harness diagnose the wrong seam.
- On C128 save-disk fixtures built with `c1541`, plain `write` seeds host files as `prg`. Do not assume those test disks model the live `seq` save-file contract unless the file type has been proven explicitly.
- On CBM disk fixtures, `c1541 write` plus a directory-type patch is a valid low-risk way to get `seq` test files when the data bytes are already correct. The important part is to patch the directory entry name in PETSCII, not ASCII, and then assert the result with `c1541 -list`.
- Do not run `make disk128` and `make test128-fast-smoke` in parallel. They share C128 build outputs under `commodore/out/c128` and `commodore/c128/out`, so the results are invalid as verification evidence.
- Do not add a transient state consumer without proving the producer exists in the current tree. The `disk_setup_done == 2` C128 title-load helper was dead code because the active title setup path never emitted that state.
- If the user says the live repro is unchanged, treat any automation that claims the bug is fixed as invalid immediately. Do not keep defending or iterating on under-modeled C128 save/load smokes once the manual drive-8-before-`L` gate disagrees.
- On C128 VDC bugs, if snapshot evidence proves the map/monster state is correct but the live retest is still wrong, stop patching turn-level redraw flags and inspect renderer-owned staging buffers next. A stale per-row cache can look exactly like a visibility bug.
- Do not wire a low-level C128 IRQ/CHRIN wrapper probe into the generic autostart unit worker until that worker is proven stable for the test. The focused `test_wrapper_irq128.s` probe is useful, but enabling it in the default unit phase before the harness survives real IRQ windows only turns the suite red with a VICE segfault and no actionable log.
- For 8563 VDC block operations, verify the register trigger contract byte-for-byte: mode/select registers must be programmed before the register write that starts the operation, and stale device state should be treated as part of the bug until disproven.
- If a user-visible C128 title regression survives a rollback of only the active title path, stop preserving inactive experiments “just in case.” In this tree the exact screenshot gate only moved once the whole save/load-era product slice was restored to `HEAD`; leaving inactive title/runtime helpers in place still preserved the bad layout.
- When clean `HEAD` is stable and the dirty tree is not, treat that as permission to restore the affected product files back to `HEAD` instead of continuing partial forward fixes. A mixed dirty baseline is not trustworthy evidence, and protecting dead-end work is worse than losing it.
- When the user says the work is drifting away from the core task, stop and restate the exact active gate plus the current evidence before doing more debugging. For harness failures, keep the next step scoped to the reported command instead of expanding into adjacent product or suite cleanup.
- When a shared save/load change is validated first on C128, do not assume the C64 UX matches just because the product logic is shared. Re-check the C64 one-drive prompt, overwrite, and redraw seams explicitly before treating the feature as done.
- In `run_tests128.sh`, boot-asset freshness must include the disk image the smoke actually autostarts, not just the rebuilt PRGs and symbol files. A fresh `out/main.vs` against a stale `out/moria128.d71` produces false C128 smoke failures.
- For VICE monitor-driven C128 boot smokes, do not chain multiple `until` probes in one boot playback. Use one symbol probe per boot run, or the playback can report misleading state and turn a healthy boot into a red harness.
- In shared assembly, do not assume there is a `C64` build flag. This tree keys the 64-bit path as `!C128`, so `#if C64` silently misses C64-only shrink/fallback code until the memory map proves otherwise.
- On C64, fullscreen modal prompts should use `ui_clear_full_screen_safe`, not the bulk `screen_clear`, when live residue matters. The row-by-row clear is the proven-safe path for C64 modal transitions, including save/load disk prompts.
- On this repo, do not spend resident Huffman-table budget on spell-only feedback that can live in an overlay-local string. Spell execution text for blocked/no-target/single-overlay paths should stay with the overlay owner first; resident messaging is for shared always-live status/reporting paths.
- When one newly added spell/prayer family is clearly under-tested, do not keep fixing single entries ad hoc. Broaden immediately to a behavior-family audit and build representative runtime coverage before trusting the larger feature set.
- In shared 6502 contracts, do not let a caller infer boolean state from whatever `A` happened to hold when the callee only promised carry. If the caller persists accumulator state, the callee must return an explicit `A=0/1` value or the scene-dirty/redraw path will drift into nondeterministic visual bugs.
- On 6502 scan/selection loops, if you save a result in `A` and then restore the slot index in `X`, do not branch on `BNE/BEQ` after the restore unless you deliberately want flags from `X`. The pack/equipment pseudo-ID pass was silently skipping every nonzero slot because the branch was testing the restored slot index instead of the RNG result.
- In shared `screencode_mixed` UI strings, do not use `{` and `}` as decorative delimiters unless you have verified both C64 and C128 render them as intended. The sensed-item `{magik}` suffix leaked glyph noise on the live VDC path; PETSCII-safe delimiters like parentheses are the safer default.
- Do not use `input_get_modal_dismiss_key` for overlays that already present a real selectable footer. Spell/prayer list overlays are selectable screens, not read-only modals; on C128 the dismiss-helper contract can preserve the wrong behavior even when the shared cancel path looks correct.
- On C128 direct-scan UI paths, raw Esc is `KEY_ESC` (`$AE`), not PETSCII `$1B`. Any shared prompt or list cancel path that compares literal `$1B` will false-green on C64 tests and stay broken live on C128.
- For selectable overlays on C128, do the release gate before drawing the overlay, not after. A post-draw `input_wait_release` can swallow the user's first quick selection/cancel key even when synthetic scripted tests stay green.

## Layout And Build Safety

- After assembly or import-order changes, re-check memory-map boundaries and treat new hangs or timeouts as likely layout regressions first.
- On this repo, if a C64 test starts hanging right after shared code growth, treat it as a memory/layout bug first and inspect patch slots, hard-coded test buffers, and breakpoint/bootstrap contracts before blaming feature logic.
- For C64 unit harnesses, do not satisfy new production trampoline symbols by importing whole overlay/runtime owners into shared test stubs. Add tiny test-local no-op owners first; otherwise unrelated suites can silently grow past their scratch-buffer or `$C000` limits.
- On C64 test layouts, if a suite only needs command-dispatch entrypoints, stub those entrypoints locally instead of importing the entire subsystem. `test_main_loop.s` only needed spell-call labels; importing the full spell runtime was the wrong fix shape.
- In shared 6502 helper APIs, do not let a bitmask/index helper silently clobber the loop register used by its callers. `spell_mask_test_ptr` was mutating `X`, which turned the spell-book scan loops into hangs; preserve the loop register in the helper or restore it at every callsite.
- For packed spell/book bit tables, verify the bucket/shift table counts against the real 8-bit mask width. A 31-spell catalog still uses `8,8,8,7` byte groups; the earlier `6,8,8,8,1` split silently dropped book membership for spell IDs 6 and 7.
- For spell-capable classes with a minimum spell level above 1, gate the live `m`/`p` commands on the class minimum before prompting for books. `PL_SPELL_TYPE` alone is not a valid UX gate once rogue/ranger/paladin exist.
- On C128, do not stop at auditing the top-level trampoline or entrypoint for a feature. If a banked routine has internal helpers, audit those callees too; `player_cast_spell` was below `$D000` while `pm_select_book` had drifted to `$D075`, which still JAMed live gameplay.
- When splitting shared assembly into resident state plus banked logic, patch the C64 unit harness imports in the same change. Many test files imported `player_magic.s` directly and broke until they also imported the new resident spell-state owners.
- When expanding a large C64 unit suite, re-check the scratch-buffer start and keep a hard `.assert` between the test body and buffer segment. Spell hardening pushed `test_effects.s` far enough that the old buffer start was no longer safe.
- For C128 spell smokes, “spell executed” is not a sufficient pass condition. Require the spell flow to return to gameplay or `main_loop` after execution, or a banking/MMU regression can still pass.
- On memory-bound C64 code, remove dead production helpers before planning overlay moves or string compression. If a helper only exists to support a unit test path, gate it to the test build instead of carrying its state and buffers in the shipping resident image.
- On C64, if the banked `$F000` payload is tight while `OVL.UI` is empty, move modal UI ownership into the overlay before attempting deeper compression or shared-runtime surgery.
- On C64, do not move a modal screen into `OVL.UI` unless its live data is independent of the `$E000` overlay window. Monster recall still has to stay banked because it reads creature/tier state that shares that same window.
- When a user reports that a previous change broke the exact reported command, stop treating the red gate as pre-existing debt. Re-run the exact command with the forced-rebuild path it actually uses and fix that gate before claiming the feature is done.
- When reusing or changing Huffman strings, update `data/huffman_strings.txt` and regenerate `commodore/common/huffman_data.s` before trusting any build or live behavior. Changing only the source text file is not enough.
- On C64, do not keep a feature in `OVL.UI` if that feature can trigger gameplay or tier restore while still executing from the overlay. Any path that can reload the active tier will repopulate `$E000` and self-clobber the running overlay code; keep those flows banked or return to banked code before restoring gameplay.
- On C64, if an overlay-backed modal returns to gameplay through a custom redraw path instead of `ui_view_restore_modal_overlay` or `ui_view_redraw_gameplay_view`, it still needs the same tier-state recheck before gameplay resumes. Character view was a separate return seam and broke recall after the `OVL.UI` move until that was fixed explicitly.
- For dead-code audits on this repo, verify shipping callsites separately from test callsites. A helper that still appears in subsystem tests can still be completely dead in the shipping C64 image and worth removing from the real import graph.
- For disk images with patched boot sectors or reserved media, reserve the owned sector before file allocation.
- When a build or test depends on tool handoff, make fresh-build paths deterministic; do not rely on warm outputs or fragile temp-path behavior.
- On message-line gameplay commands, do not route all no-turn exits through a “restore gameplay view” helper. For prompt-driven commands like `m`/`p`, that clears the screen and turns a real error message into a flash; cancel paths should clear their own prompt state, while wrong-command errors should fall back to the normal no-turn main-loop path.
- On C128, every secondary prompt in a multi-step command must explicitly gate `input_get_key` with `input_wait_release` or `input_prepare_followup_key`, even if the previous step already did so. The spell book prompt was release-gated, but the immediate follow-up spell-choice prompt was not, so the held book-selection key was consumed as the spell choice.
- On C128, a follow-up release gate placed after rendering the next prompt can swallow a fast second keypress. For prompt-to-prompt flows like book -> spell selection, do the release gate before drawing the second prompt, then read the key normally.
- On C128, selectable `?` overlays are not the same as read-only “Press any key” modals. If an overlay is supposed to accept a real item/spell letter, release-gate before drawing the overlay and then read the selection while the overlay is visible; waiting for release after the overlay is already drawn can swallow a quick first selection tap.
- On C128, never store mutable UI mode state inside an overlay file if the state is written before `overlay_load`. The overlay load will wipe it before the renderer runs. Keep that state resident/common or make the behavior explicit through the entrypoint contract.
- Do not rely on `msg_clear` to preserve carry on C128. Clearing a non-status row calls `screen_clear_row`, and the VDC implementation leaves carry reflecting its row compares. Any chooser that uses carry for success/cancel must `jsr msg_clear` and then set carry explicitly before returning.
- On C128, start-address residency audits are not enough for callable helpers near `$D000`. Audit the full function extent with explicit end labels; `pm_mark_worked` still JAMmed even after its entrypoint moved below the I/O hole because the tail of the routine crossed into `$D000`.

## C64 Banking And IRQ

- If a live C64 hang lands in low RAM with repeated `IRQ -> $FFFF` frames, inspect the `$01`/interrupt contract before chasing memory corruption; `$01=$35` with IRQs active means KERNAL vectors are banked out and prompt/input code likely returned in the wrong bank state.
- Do not attribute a broken VICE localhost monitor flow to sandboxing by default. In this repo, a failed C64/C128 product-smoke monitor step is more likely a bug in the harness sequencing, breakpoint choreography, or connection startup than an environment issue, and the tooling has to be proven first.
- If the user says a spell crash only happens when a real monster is targetable, do not accept a town smoke or a dungeon no-target smoke as evidence. The automated gate must force an actual targetable monster in the aimed tile before any conclusion about reproduction or fixes.
- When a snapshot-backed repro proves the crash happens immediately after dismissing `-more-`, stop widening spell-path hypotheses and debug the shared message resume/history seam first. That path can fail independently of the spell effect and will invalidate otherwise healthy targeting smokes.
- When the user reports a new live gameplay corruption and explicitly says to add it to the list, record it as its own bug with the exact on-screen symptom instead of folding it into the current spell/debug thread.
- Do not use an old VICE `.vsf` as the closure gate after rebuilding the product. A snapshot restores the old machine RAM image too, so current symbols and current code layout no longer describe the restored program; use the snapshot to root-cause the seam, then capture the bug in a current-build regression.
- On C64, REU/tier helpers called from monster-name reloads must preserve the caller interrupt state just like spell/combat helpers do. Raw `sei ... cli` in `reu_fetch_tier` or the C64 activation path of `tier_load` can reopen IRQs inside a live spell-hit message path and send execution off into garbage.
- In message-line driven UI flows, accepted prompts must actively clear their row state before handing off to the next gameplay prompt. If the old chooser prompt remains “live,” the next prompt is treated as a third message and forces a bogus `-more-` even though the user just pressed a key.
- On C64, restoring the active tier after an overlay/UI action is not the same thing as a real dungeon-depth transition. If that restore path reuses `tier_check_transition` directly, `tier_load` will leak the transient `Loading...` message into normal gameplay; use a silent restore path for overlay recovery.
- On C64, overlay-driven tier invalidation can surface again through stale `$E0xx` monster-name pointers even after the main overlay restore is fixed. `creature_get_name` has its own tier reload path, and it also must suppress transient `Loading...` messaging during internal recovery.
- If a full-screen chooser footer says a letter selects an item/spell, do not route that path through a read-only modal dismiss helper. The caller must either treat the returned key as a real selection or change the footer text; anything else is a broken UI contract.
- When changing identify/item naming, inspect the actual source name tables before assuming a shared helper adds category nouns; bare canonical names like potions and scrolls need explicit category-aware wording in the caller or a proven shared formatter.
- If a branch regresses the reported build gate, do not argue that the same assert was already red on `HEAD`. The branch still owns the regression if the current branch work pushed the build/test over the edge, and the correct response is to fix the current tree and then verify the exact reported gate.
- When recovering bytes for one platform, do not hide shared text/data inside a broadly imported module unless every consumer actually needs it. Moving Home-only strings into `ui_store.s` fixed C128 size pressure but pushed unrelated C64 tests over their memory limits; isolate feature-local text in a dedicated owner file instead.
- For narrow prompt bugs in this repo, do not extend resident shared filter/state machinery until the forced C128 rebuild gate stays green. The attempted recharge-only inventory filter fixed the local picker but immediately tripped the staged-source assert; for one-off prompt flows, prefer adapting the existing overlay contract before teaching `player_items.s` a new global mode.

- When a shared gameplay owner gains a new global like `eff_detect_timer` or `tier_silent_restore`, update the C128 unit harness stubs in the same change. `main_loop128` and `monster128` both went red only because the test owners lagged the shared symbol contract.
- When a new high-value regression smoke is added to close an escaped bug, wire it into the standard `make test128-fast-smoke` target immediately. A targeted-only smoke is not enough coverage for the next regression pass.
- A scripted C128 smoke that only checks an internal timer or success counter is not sufficient proof for live spell/prayer UX. For `m`/`p` flows, the smoke must prove a user-visible effect or message through the real gameplay path, or it can pass while the manual C128 experience is still broken.
- If the user reports that both C128 spells and prayers regressed in the current tree, stop doing prayer-only debugging. Reclassify it immediately as a shared casting-path regression and audit the recent shared cast/pray edits before touching effect-specific code.
- When the repo already has local upstream source trees called out in project notes, use them before answering historical/parity questions from memory.
- For `umoria`-parity fixes, do not infer intent from the current port's shared code paths. Verify the exact upstream routine first; here the prayer and wizard reveal had drifted together locally even though upstream treats them as different features.
- On C128, any direct access to map rows at `$4000+` must use the MMU-safe map macros, not raw `(zp_ptr),y` loads/stores. Raw accesses there hit Bank 0 resident code unless `$FF00` is explicitly on Bank 1, and the failure mode looks like later random JAMs in unrelated routines.
- If a C64 suite suddenly goes all-zero with empty raw output after shared-code growth, check that suite's Memory Map first. In this repo that almost always means the test body drifted past a safe boundary, and the right fix is to trim imports or stub unneeded modules until the test fits again.
- When trimming a large C64 suite back under `MAP_BASE`, satisfy any leftover trampoline symbol contracts with tiny local stubs instead of re-importing the whole owner module. `test_save.s` only needed `ui_help_display` to exist for `ui_trampoline_stubs.s`; a local `rts` stub fixed the build without re-bloating the test body.
- On C128, a self-patched overlay trampoline must patch the full 16-bit call target unless there is an explicit assert that every callee stays on the same page. Patching only the low byte made the shared UI trampoline jump into the wrong `OVL.UI` routine and corrupted Wizard Mode.
- Do not trust `make build128` in this repo as proof that a C128 layout change really rebuilt the shipping image. The real residency gate is the forced `make -s -C commodore -W c128/main.s -W c128/boot128.s ... build128 disk128` path used by `test128-fast-smoke`; that is the one that caught the staged-source overflow after the wizard fix.
- In this repo, any command that can fall through `command_result_main_or_update_visibility` must have a valid pre-command render baseline. `render_local_area` uses `old_player_*` and `old_view_*`; if stationary commands inherit stale movement coordinates, visible monsters can disappear or linger until the next full redraw. Snapshot that baseline once at the top of `main_loop`, not ad hoc per command.
- Do not call a spell-feedback fix done when the regression only proves a reused message ID or helper. The first `Slow Monster` fix passed because the unit only exercised `huff_print_msg`, not the live spell path, and the actual built game still showed `.`.
- When changing `data/huffman_strings.txt`, regenerate `commodore/common/huffman_data.s` in the same pass before claiming any prompt/message fix works. This repo does not auto-refresh the generated Huffman table for every test path, so source-text edits alone can false-green while live builds still show the old empty string.
- For movement redraw bugs on this repo, separate “any monster acted” from “the expensive full-scene redraw is required.” Nearby monster movement can be correct with only the local redraw path; `turn_scene_dirty` should be reserved for non-local visible changes.
- When a high-count legacy suite starts failing while you are adding new coverage for an unrelated bug, restore the committed baseline cases first and only keep the new targeted assertions. Do not let incidental edits to existing test scenarios become part of the main debugging surface.
- A cached status bar still flashes badly if the renderer redraws all rows whenever any field changes. Preserve the forced full-repaint contract for screen/status clears, but ordinary HP/MP/hunger changes should only clear and redraw the dirty status rows.
- When a late gameplay message looks like a stale prayer/spell line, prove whether it is visually stale or freshly emitted before touching UI restore paths. Here the real source was `turn_tick_pseudo_id` still using broken contiguous Huffman-ID arithmetic, and the later real `The prayer has expired.` message was the clue that the bless timer path was fine.
- When explicit new resident Huffman strings push C64 over `MAP_BASE`, recover bytes from overlay-only message owners first and keep shared resident code/data minimal. For this fix, making the PID block truly contiguous again and moving overlay-only prayer feedback strings out of the resident Huffman pool was the clean recovery; opportunistic localizing of shared heal strings made the layout worse.
- When a large C64 suite suddenly JAMs late in execution after shared-code growth, check the suite's assembled main/test-body end against `MAP_BASE` before debugging gameplay logic. `test_item.s` had simply drifted to `$C0D4`, and moving non-executed imports out of the resident body plus a hard `.assert` fixed the crash.
- In `commodore/c64/run_tests.sh`, treat `script` tty logs as text explicitly and retry once when a monitor dump is missing. The VICE monitor output can disappear intermittently for long suites even when the product/test PRG itself is healthy, and `grep -a "^>C:0"` plus a single rerun keeps the exact `make test64` gate aligned with the real runtime result.
- When a load/resume path rebuilds gameplay view, do not call a deadband-style `viewport_update` on uninitialized transient viewport coords. Seed `zp_view_x/zp_view_y` first or stale UI/title values like `$FF` can survive into the first render and produce convincing VDC “garbage” that is really row-255 map data.
- When a live message looks bogus, check whether the player stats or world state already prove the effect happened before treating it as a message regression. `You feel weakened.` looked suspicious, but `CO:15` immediately matched the poison-dart CON-drain path and ruled out another string-routing bug.
- Do not tell the user a fresh-build visual bug is probably an old binary/session unless you have proof from the actual shipping path. The `Long SwordITEM 0-63:` report was real on a fresh build; the right move was to trace the live C128 item-name append path, not push back on the report.
- When a stale string begins exactly where a dynamic item name ends, suspect a bad append path before a row-clear bug. `Long SwordITEM 0-63:` looked like residue at first, but the exact alignment pointed to invalid ego suffix handling, and the wizard prompt text was only showing up because the suffix lookup walked off-table.
- Load/title error prompts must not reuse raw `input_get_key` after a command-triggered failure on C128. Use the modal-dismiss/follow-up-key path or the initiating command key can leak through and make the message look unpaused.
- When adding new runtime tests to an existing C64 suite, update both the in-test result copy count and `run_tests.sh`'s byte range/test count. Otherwise the new tests can exist but never become part of the gate.
- For inventory `?` overlays, distinguish all-items views from filtered selectors before changing letter ownership. All-items overlays must preserve the player's real sparse inventory letters; only filtered views should relabel contiguously.
- When a prompt-range bug is caller-specific, do not “fix” it by deleting the range text or by teaching the shared prompt framework new semantics first. Match the nearest correct product behavior (`wear` here), then localize the ownership and recover bytes separately if layout gets tight.
- For dynamic prompt letters rendered through the C64 message path, patch VIC screen codes, not PETSCII-style uppercase values. The shared prompt strings here are screen-code buffers, so `d` is `$04`, not `$44`.
- When trimming branches in a gameplay command path, re-check the success/control-flow labels, not just the byte count. Here `item_drop` lost the jump around `!idr_empty`, so every valid direct selection fell through to `You have nothing there.`
- When a C128 save/load checksum mismatch appears only on a real media path and the snapshot shows `save_io_error = 0`, inspect KERNAL register-clobber contracts before changing the save format. Here the real break was that `CHRIN/CHROUT` clobbered `X`, and the floor-item save/load loops were keeping their slot index in `X` across `load_read_byte` / `save_write_byte`.
- Before adding new text in a broadly imported overlay/shared owner, check whether an existing resident string can express the same feedback. Here a new dispel-specific string pushed `DeathOverlay` over `$EFFF`; reusing `cmb_kill_str` preserved the fix and kept both C64/C128 layout gates green.
- When a small UX fix overflows `DeathOverlay`, look for semantically equivalent resident Huffman strings before inventing new overlay text or new owners. Here the no-target `Dispel Evil` fix fit cleanly once the recharge-empty prompt reused resident `HSTR_PIW_NOTHING`.
- When the branch goal is explicit `umoria` parity, do not preserve an older local VMS-style compromise just because it is already documented in the port. Re-check the upstream source/manual and update the local spec to match the real parity target.
- On C128, a tiny shared resident change can still fail the banked staged-source ceiling even when every overlay fits. After any resident/common-code spell change, re-check both the C64 `MAP_BASE` ceiling and the C128 `banked_payload_end <= $E000` staged-source assert before calling the layout safe.
- A C128 modal/input smoke that stops at an internal pass trap can miss the next live command after the modal returns. For escaped modal bugs, keep at least one product-path gate running past the dismiss into the follow-up command that used to crash, or add a static/runtime contract for the exact post-dismiss owner.
- In C128 overlays, direct `input_get_key` is unsafe unless the caller explicitly restores the overlay execution banking before the next instruction. Static audits should reject direct key reads in overlay-resident prompt routines, not require them as a prompt-shape proof.
- If `make test128-fast-smoke` fails after a layout-affecting branch, do not call the staged-source assertion pre-existing just because a different build target previously printed a related warning. The smoke target's forced `build128 disk128` gate is authoritative, and the current branch owns any over-ceiling bytes until proven otherwise.
- Do not invent a new `OVL_DEATH` dependency for live gameplay spell feedback without explicit approval. If a spell-effect message needs a home, keep the text gameplay-owned and verify the C128 staged source/banked ceilings before choosing resident, banked, or overlay ownership.
- `msg_print` does not consume message pointers from `A/Y`; it reads `zp_ptr0/zp_ptr0_hi`. Any new direct spell/prayer feedback path must populate that ZP pointer first, or the fix can look correct in source review while printing garbage or nothing at runtime.
- Any new direct `.text` message that flows into `msg_print` or `screen_put_string` must be assembled under `.encoding "screencode_mixed"`. The glyph placement line looked fine in source and tests that only checked pointers, but the live C128 path rendered garbage because the file inherited the wrong text encoding.
- When shrinking a shared helper that carries both a filter in `A` and a prompt/string id in `X`, re-check the register contract before counting the bytes as saved. The first dense-pack trim in `piw_prompt_filtered_inv` accidentally fed the prompt id into `piw_build_visible_inv_cache`, which broke every filtered inventory path until the helper was rewritten to save `X` in scratch and leave `A` intact.
- 2026-04-22: When a shared core fix on C64 changes resident layout by even a few bytes, do not trust green unit/smoke gates alone for overlay-backed UI paths. Compare the rebuilt resident `main.vs` addresses and overlay binary against the last known-good build when a live-only modal/UI regression appears.
- 2026-04-22: For C64 shared spell fixes, prefer layout-neutral rewrites when possible. The first `Phase Door` fix used an extra callsite and shifted resident `pm_*` addresses enough to break live spell-list rendering; the correct repair preserved the original callsite footprint and moved the shared side effect into the common target-apply path instead.
- Do not let automatic no-input turns enter the message `-MORE-` prompt path. If preserving a status-cause message across paralysis/rest/forced turns, explicitly prevent the forced-turn expiry message from stacking into a third queued message.
- Important overcast/faint feedback should be acknowledged during the initiating cast/pray action, not deferred to automatic paralysis turns. Put the `-MORE-`/input wait before forced turns start, then keep forced turns free of message prompts.
- Do not fake a `-MORE-` acknowledgement by reprinting an important message through the full-message queue. It avoids a new call dependency but duplicates live feedback after the keypress; call the acknowledgement path directly and add focused stubs/tests instead.
- Do not call a C128 spell/common-code change complete until the shipping image gate has rebuilt. Focused unit tests and C64 suites can pass while `make disk128` still fails DeathOverlay or banked staged-source ceilings.
- Treat untracked files in the worktree as your responsibility unless proven otherwise. If an untracked source file appears during your changes, explain or remove it before claiming the tree is clean.
- A spell row test that patches `test_spell_execute_selected` to call an effect directly does not cover C64 product overlay trampolines. For spells dispatched through cross-overlay trampolines, add a contract or product-path regression for the trampoline itself; otherwise effect tests can green while live overlay reloads hang.
- Do not stop at the first plausible C64 overlay banking bug when the user reports the live path still fails. After any overlay-owned call that invalidates monster tier data, check the follow-up restore path too; `tier_restore_after_overlay` may do disk-backed KERNAL I/O and must not run with KERNAL banked out.
- Passing static banking contracts plus broad tests is not closure for a user-reported live C64 hang. If the user provides a fresh VSF after a supposed fix, reopen the task, inspect that snapshot/product path, and do not call success until a gate that exercises the same live path fails-before/passes-after or the user confirms the fresh disk.
- On C64, code that hides KERNAL must also make the RAM IRQ/NMI vectors valid. Even if all intended paths use `SEI`, a leaked interrupt under `$35` reads `$FFFE/$FFFF` from RAM; if those bytes are uninitialized, the symptom is a wild IRQ stack spiral rather than a clean crash at the original caller.
- If a C64 safety fix trips `Program fits below MAP_BASE`, fix the resident-size regression immediately and keep the boundary assert authoritative. Consolidating repeated resident trampoline preambles is preferable to moving IRQ/vector safety code out of always-visible RAM.
- A fresh live C64 `CPU JAM` after green static contracts means the current coverage still missed a product control-flow path. Reopen the task and trace the live return/jump chain; do not add another static contract until the reason execution reached the JAM address is understood.
- A C64 overlay trampoline called from inside another overlay must restore the caller overlay before `RTS`. If that restore needs disk/KERNAL I/O, briefly return to `$36`/CLI for `overlay_load`, then hide KERNAL again before returning to the overlay caller.
- When a live C64 spell bug changes symptom from JAM to hang after a candidate fix, treat that as a new active gate on the latest VSF. Do not keep defending the previous root cause; inspect CPU/RAM state again and update the task record before editing.
- For C64 spells invoked from an overlay caller, prefer a banked-payload effect over `caller overlay -> resident trampoline -> different overlay -> restore caller overlay` if the effect fits. The reload chain can pass unit tests and static contracts while still being too fragile for live interrupt/stack/product timing.
- Do not describe a manual Wizard Mode workflow from intent alone. Check `WIZARD.md` or the wizard command implementation first; here there was no direct "set poison" command, and the correct setup was generating/quaffing item `19`.
- Do not shorten user-visible C128 preload/disk asset names as a byte-saving tactic in unrelated work. If bytes are tight, recover them away from boot/status identity strings so the displayed name still matches the actual program-media filename.

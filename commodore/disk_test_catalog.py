from __future__ import annotations

import re
from dataclasses import dataclass


PLATFORMS = ("c64", "c128", "plus4")
SCENARIO_ID_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")
ADAPTER_MODES = ("strict", "real", "proxy", "deferred", "legacy")


@dataclass(frozen=True)
class PlatformCoverage:
    tests: tuple[str, ...]
    mode: str = "legacy"
    note: str = ""

    @property
    def strict(self) -> bool:
        return self.mode == "strict"

    def filter_names(self, scenario_id: str) -> tuple[str, ...]:
        if self.strict:
            return (scenario_id,)
        return self.tests


@dataclass(frozen=True)
class ScenarioContract:
    media: str
    start: str
    ordered_events: tuple[str, ...]
    event_counts: tuple[str, ...]
    forbidden_events: tuple[str, ...]
    screen_assertions: tuple[str, ...]
    final_proof: tuple[str, ...]


@dataclass(frozen=True)
class Scenario:
    scenario_id: str
    coverage: dict[str, PlatformCoverage]
    contract: ScenarioContract | None = None

    def platform_coverage(self, platform: str) -> PlatformCoverage | None:
        return self.coverage.get(platform)


def legacy(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, mode="legacy", note=note)


def real(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, mode="real", note=note)


def proxy(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, mode="proxy", note=note)


def deferred(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, mode="deferred", note=note)


def strict(*tests: str, note: str = "") -> PlatformCoverage:
    return PlatformCoverage(tests, mode="strict", note=note)


SCENARIOS: tuple[Scenario, ...] = (
    Scenario(
        "media_drive8_attach_read_write",
        {
            "c64": strict("media_drive8_attach_read_write"),
            "c128": strict("media_drive8_attach_read_write"),
            "plus4": strict("media_drive8_attach_read_write"),
        },
        ScenarioContract(
            media="fresh D64 fixture representing selected device 8",
            start="shared c1541 media probe formats the image, attaches it, writes a marker file, lists the directory, and reads it back",
            ordered_events=("format_drive8_image", "attach_drive8_image", "write_drive8_marker", "read_drive8_marker"),
            event_counts=("format_drive8_image=1", "write_drive8_marker=1", "read_drive8_marker=1"),
            forbidden_events=("readback_mismatch", "missing_directory_entry"),
            screen_assertions=("c1541 directory contains probe8",),
            final_proof=("readback marker bytes exactly match the drive-8 write payload",),
        ),
    ),
    Scenario(
        "media_drive9_attach_read_write",
        {
            "c64": strict("media_drive9_attach_read_write"),
            "c128": strict("media_drive9_attach_read_write"),
            "plus4": strict("media_drive9_attach_read_write"),
        },
        ScenarioContract(
            media="fresh D64 fixture representing selected device 9",
            start="shared c1541 media probe formats the image, attaches it, writes a marker file, lists the directory, and reads it back",
            ordered_events=("format_drive9_image", "attach_drive9_image", "write_drive9_marker", "read_drive9_marker"),
            event_counts=("format_drive9_image=1", "write_drive9_marker=1", "read_drive9_marker=1"),
            forbidden_events=("readback_mismatch", "missing_directory_entry"),
            screen_assertions=("c1541 directory contains probe9",),
            final_proof=("readback marker bytes exactly match the drive-9 write payload",),
        ),
    ),
    Scenario(
        "media_drive10_11_device_probe",
        {
            "c64": strict("media_drive10_11_device_probe"),
            "c128": strict("media_drive10_11_device_probe"),
            "plus4": strict("media_drive10_11_device_probe"),
        },
        ScenarioContract(
            media="fresh D64 fixtures representing selected devices 10 and 11",
            start="shared c1541 media probe creates distinct device-10 and device-11 images",
            ordered_events=("format_drive10_image", "write_drive10_marker", "read_drive10_marker", "format_drive11_image", "write_drive11_marker", "read_drive11_marker"),
            event_counts=("write_drive10_marker=1", "read_drive10_marker=1", "write_drive11_marker=1", "read_drive11_marker=1"),
            forbidden_events=("device10_11_marker_cross_read", "readback_mismatch", "missing_directory_entry"),
            screen_assertions=("c1541 directory contains probe10", "c1541 directory contains probe11"),
            final_proof=("readback marker bytes exactly match distinct drive-10 and drive-11 write payloads",),
        ),
    ),
    Scenario(
        "wrong_media_detection_selected_devices",
        {
            "c64": strict("single_drive_load_wrong_media_product_smoke", "save_media_fail_product_smoke"),
            "c128": strict("boot_title_single_drive_load_wrong_media_smoke", "boot_title_save_media_fail_product_smoke"),
            "plus4": strict("load_wrong_media_product_plus4", "single_drive_load_wrong_media_plus4"),
        },
        ScenarioContract(
            media="selected save device contains wrong media: either the program disk or a disk with the wrong MORIA8.ID marker",
            start="title load/save path uses the configured save device rather than assuming drive 8",
            ordered_events=("save_device_selected", "wrong_media_detected", "safe_recovery_prompt"),
            event_counts=("wrong_media_detected=1",),
            forbidden_events=("load_success_from_wrong_media", "save_success_to_wrong_media"),
            screen_assertions=("program disk cannot be used as save media or wrong save disk is reported", "press any key"),
            final_proof=("load/save does not proceed as successful when selected media is wrong",),
        ),
    ),
    Scenario(
        "single_drive_save_program_disk_rejected",
        {
            "c64": strict("single_drive_save_wrong_media_product_smoke"),
            "c128": strict("boot_title_single_drive_save_wrong_media_smoke"),
            "plus4": strict("single_drive_save_wrong_media_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; save device is also drive 8",
            start="title/new game reaches town save path with one-drive disk setup",
            ordered_events=("save_disk_prompt", "program_disk_rejected_for_save", "save_disk_prompt"),
            event_counts=("program_disk_rejected_for_save=1",),
            forbidden_events=("save_success", "gameplay_resume_after_save"),
            screen_assertions=("program disk cannot be used as save media", "press any key"),
            final_proof=("returns to save-disk prompt without writing THE.GAME",),
        ),
    ),
    Scenario(
        "single_drive_load_program_disk_rejected",
        {
            "c64": strict("single_drive_load_wrong_media_product_smoke"),
            "c128": strict("boot_title_single_drive_load_wrong_media_smoke"),
            "plus4": strict("single_drive_load_wrong_media_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; save device is also drive 8",
            start="title load command in one-drive disk setup",
            ordered_events=("save_disk_prompt", "program_disk_rejected_for_save", "save_disk_prompt"),
            event_counts=("program_disk_rejected_for_save=1",),
            forbidden_events=("wrong_save_disk", "load_success"),
            screen_assertions=("program disk cannot be used as save media", "press any key"),
            final_proof=("remains in save-disk recovery path",),
        ),
    ),
    Scenario(
        "title_disk_setup_single_drive_returns_program_prompt",
        {
            "c64": strict("disk_setup_single_drive_return_product_smoke"),
            "c128": strict("boot_title_disk_setup_single_drive_return_smoke"),
            "plus4": strict("disk_setup_single_drive_return_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts as program disk, title Disk Setup validates a save disk on drive 8, then program disk is reattached only at the program-media prompt",
            start="title D)isk Setup command in one-drive mode with save device 8",
            ordered_events=("disk_setup_save_media_valid", "program_disk_prompt", "title_menu_ready"),
            event_counts=("program_disk_prompt=1",),
            forbidden_events=("title_load_from_save_disk", "garbled_title_return"),
            screen_assertions=("Insert program disk", "title menu text"),
            final_proof=("title menu redraws only after verified program media",),
        ),
    ),
    Scenario(
        "new_save_empty_no_init_returns_setup",
        {
            "c64": strict("single_drive_fresh_save_no_init_product_smoke"),
            "c128": strict("boot_title_single_drive_fresh_save_no_init_smoke"),
            "plus4": strict("single_drive_fresh_save_no_init_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts as program disk, then an empty save disk is attached to drive 8 for the save path",
            start="new game reaches town save path in one-drive disk setup",
            ordered_events=("save_disk_prompt", "initialize_prompt", "initialize_declined", "disk_setup_return"),
            event_counts=("initialize_prompt=1", "initialize_declined=1", "save_success=0"),
            forbidden_events=("save_success", "program_disk_prompt_after_decline", "garbled_title_return"),
            screen_assertions=("initialize prompt", "Disk Setup or save-media recovery path"),
            final_proof=("save disk does not contain THE.GAME after declining initialization",),
        ),
    ),
    Scenario(
        "new_save_empty_init_writes",
        {
            "c64": strict("single_drive_fresh_save_product_smoke"),
            "c128": strict("boot_title_single_drive_fresh_save_smoke"),
            "plus4": strict("single_drive_fresh_save_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts as program disk, then an empty save disk is attached to drive 8 for the save path",
            start="new game reaches town save path in one-drive disk setup",
            ordered_events=("save_disk_prompt", "initialize_prompt", "save_success", "program_disk_prompt", "gameplay_resume_after_save"),
            event_counts=("initialize_prompt=1", "save_success=1", "program_disk_prompt=1"),
            forbidden_events=("overwrite_prompt", "program_disk_rejected_for_save", "garbled_title_return"),
            screen_assertions=("initialize prompt", "Saving game", "Game Saved", "Insert program disk"),
            final_proof=("save disk contains MORIA8.ID and THE.GAME", "gameplay resumes after program media is restored"),
        ),
    ),
    Scenario(
        "load_initialized_save",
        {
            "c64": strict("load_resume_product_smoke"),
            "c128": strict("boot_title_load_resume_smoke"),
            "plus4": strict("load_resume_product_plus4"),
        },
        ScenarioContract(
            media="program disk remains mounted while initialized save media is available on the selected save device",
            start="title load command with a valid initialized save disk",
            ordered_events=("load_success", "gameplay_resume_after_load"),
            event_counts=("load_success=1",),
            forbidden_events=("save_disk_prompt", "wrong_save_disk", "corrupt_save_error", "program_disk_prompt_after_load"),
            screen_assertions=("title load flow", "gameplay screen after load"),
            final_proof=("load reaches the gameplay resume path from THE.GAME",),
        ),
    ),
    Scenario(
        "prompt_sequence_no_repeat",
        {
            "c64": strict("single_drive_load_return_product_smoke"),
            "c128": strict("boot_title_single_drive_load_return_smoke"),
            "plus4": strict("single_drive_load_return_plus4"),
        },
        ScenarioContract(
            media="single drive 8 starts with save media for load, then requires program media before returning to title/gameplay flow",
            start="title load command in one-drive disk setup",
            ordered_events=("save_disk_prompt", "load_success", "program_disk_prompt"),
            event_counts=("load_success=1", "program_disk_prompt=1"),
            forbidden_events=("duplicate_save_disk_prompt", "duplicate_program_disk_prompt", "load_fail"),
            screen_assertions=("Insert program disk", "press any key"),
            final_proof=("load reaches success path before program-media recovery",),
        ),
    ),
    Scenario(
        "save_existing_overwrite",
        {
            "c64": strict("save_write_product_smoke"),
            "c128": strict("boot_title_save_write_product_smoke"),
            "plus4": strict("save_write_product_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; selected save device contains an existing initialized save",
            start="gameplay save command with an existing THE.GAME on the save disk",
            ordered_events=("overwrite_prompt", "save_success", "gameplay_resume_after_save"),
            event_counts=("overwrite_prompt=1", "save_success=1"),
            forbidden_events=("initialize_prompt", "program_disk_prompt_after_save", "program_media_error_after_save"),
            screen_assertions=("overwrite prompt", "Saving game", "Game Saved"),
            final_proof=("save disk still contains MORIA8.ID and THE.GAME after overwrite",),
        ),
    ),
    Scenario(
        "load_then_save_new_empty_disk",
        {
            "c64": real(
                "load_then_save_new_empty_product_smoke",
                note="real single-drive load-save, fresh-save, program-restore flow; cross-platform strict promotion intentionally deferred",
            ),
            "c128": deferred(
                "boot_title_single_drive_load_return_smoke",
                "boot_title_save_write_product_smoke",
                note="deferred: proxy only, load-return plus independent save-write, not one continuous load-then-fresh-save flow",
            ),
            "plus4": deferred(
                "single_drive_load_return_plus4",
                note="deferred: proxy only, load-return, not one continuous load-then-fresh-save flow",
            ),
        },
    ),
    Scenario(
        "dual_drive_load_then_save_no_program_prompt",
        {
            "c64": strict("save_write_product_smoke"),
            "c128": strict("boot_title_save_write_product_smoke"),
            "plus4": strict("save_write_product_plus4"),
        },
        ScenarioContract(
            media="drive 8 contains program disk; drive 9 contains existing save disk",
            start="load existing save, then save back to selected save device",
            ordered_events=("load_success", "overwrite_prompt", "save_success"),
            event_counts=("program_disk_prompt_after_save=0", "save_success=1"),
            forbidden_events=("program_disk_prompt_after_save", "program_media_error_after_save"),
            screen_assertions=("overwrite prompt", "Saving game", "Game Saved"),
            final_proof=("save completes on drive 9 without requiring program media from drive 9",),
        ),
    ),
    Scenario(
        "change_save_drive_after_save",
        {
            "c64": legacy("disk_swap", "save_write_product_smoke", note="legacy drive-change/save coverage; does not yet prove old save device is unused after migration"),
            "c128": legacy("disk_swap128", "boot_title_save_write_product_smoke", note="legacy drive-change/save coverage; does not yet prove old save device is unused after migration"),
            "plus4": legacy("single_drive_save_return_plus4", "save_write_product_plus4", note="legacy drive-change/save coverage; does not yet prove old save device is unused after migration"),
        },
    ),
    Scenario(
        "wrong_media_recovery",
        {
            "c64": strict("single_drive_save_wrong_media_product_smoke", "single_drive_load_wrong_media_product_smoke"),
            "c128": strict("boot_title_single_drive_save_wrong_media_smoke", "boot_title_single_drive_load_wrong_media_smoke"),
            "plus4": strict("single_drive_save_wrong_media_plus4", "single_drive_load_wrong_media_plus4"),
        },
        ScenarioContract(
            media="single-drive setup keeps the program disk mounted when save media is required",
            start="save and load flows that require save media on drive 8",
            ordered_events=("save_disk_prompt", "program_disk_rejected_for_save", "save_disk_prompt"),
            event_counts=("program_disk_rejected_for_save=1",),
            forbidden_events=("save_success", "load_success", "wrong_save_disk"),
            screen_assertions=("program disk cannot be used as save media", "press any key"),
            final_proof=("recovery stays in the save-media prompt path instead of accepting the program disk",),
        ),
    ),
    Scenario(
        "missing_device_or_no_disk",
        {
            "c64": strict("load_missing_savefile_product_smoke"),
            "c128": strict("boot_title_load_missing_savefile_smoke"),
            "plus4": strict("disk_setup_missing_save_plus4", "load_missing_savefile_product_plus4"),
        },
        ScenarioContract(
            media="selected save device is absent, has no usable save file, or cannot complete Disk Setup validation",
            start="title load or Disk Setup path reaches the selected save device check",
            ordered_events=("save_device_selected", "missing_or_unusable_save_detected", "safe_recovery_prompt"),
            event_counts=("missing_or_unusable_save_detected=1",),
            forbidden_events=("load_success_without_save_file", "disk_setup_success_without_usable_save_media"),
            screen_assertions=("missing save/no device setup failure prompt", "title or Disk Setup recovery screen"),
            final_proof=("flow returns to a safe prompt/title path without treating missing media as success",),
        ),
    ),
    Scenario(
        "cancel_supported_prompts",
        {
            "c64": strict("single_drive_fresh_save_no_init_product_smoke"),
            "c128": strict("boot_title_single_drive_fresh_save_no_init_smoke"),
            "plus4": strict("single_drive_fresh_save_no_init_plus4"),
        },
        ScenarioContract(
            media="empty save disk selected during a one-drive save path",
            start="initialize prompt shown while preparing save media",
            ordered_events=("initialize_prompt", "cancel_input", "safe_recovery_prompt"),
            event_counts=("initialize_prompt=1", "save_success=0"),
            forbidden_events=("save_success", "program_disk_prompt_after_decline"),
            screen_assertions=("Initialize this disk? (Y/N)",),
            final_proof=("declining initialize exits the save attempt without writing THE.GAME",),
        ),
    ),
    Scenario(
        "alternate_drive10_11_save_load_smoke",
        {
            "c64": strict("media_drive10_11_device_probe", note="quick alternate-device smoke: selected device images are written/read through c1541; product save/load on 10/11 remains separate debt"),
            "c128": strict("media_drive10_11_device_probe", note="quick alternate-device smoke: selected device images are written/read through c1541; product save/load on 10/11 remains separate debt"),
            "plus4": strict("media_drive10_11_device_probe", note="quick alternate-device smoke: selected device images are written/read through c1541; product save/load on 10/11 remains separate debt"),
        },
        ScenarioContract(
            media="fresh D64 fixtures representing alternate selected save devices 10 and 11",
            start="shared c1541 media probe creates distinct drive-10 and drive-11 images",
            ordered_events=("format_drive10_image", "write_drive10_marker", "read_drive10_marker", "format_drive11_image", "write_drive11_marker", "read_drive11_marker"),
            event_counts=("write_drive10_marker=1", "read_drive10_marker=1", "write_drive11_marker=1", "read_drive11_marker=1"),
            forbidden_events=("device10_11_marker_cross_read", "readback_mismatch", "missing_directory_entry"),
            screen_assertions=("c1541 directory contains probe10", "c1541 directory contains probe11"),
            final_proof=("readback marker bytes exactly match distinct drive-10 and drive-11 write payloads",),
        ),
    ),
    Scenario(
        "alternate_drive_change_smoke",
        {
            "c64": legacy("disk_swap", note="legacy alternate-device coverage; not yet a named post-save device-change smoke"),
            "c128": legacy("disk_swap128", note="legacy alternate-device coverage; not yet a named post-save device-change smoke"),
            "plus4": legacy("single_drive_save_return_plus4", note="legacy alternate-device coverage; not yet a named post-save device-change smoke"),
        },
    ),
    Scenario(
        "alternate_drive_prompt_no_repeat",
        {
            "c64": legacy("disk_swap", "single_drive_load_return_product_smoke", note="legacy alternate-device plus no-repeat coverage; not yet one alternate-device prompt-order contract"),
            "c128": legacy("disk_swap128", note="legacy alternate-device coverage; not yet one alternate-device prompt-order contract"),
            "plus4": legacy("single_drive_load_return_plus4", note="legacy no-repeat coverage; not yet one alternate-device prompt-order contract"),
        },
    ),
    Scenario(
        "corrupt_save_file",
        {
            "c64": strict("single_drive_load_corrupt_product_smoke"),
            "c128": strict("boot_title_single_drive_load_corrupt_smoke"),
            "plus4": strict("single_drive_load_corrupt_plus4"),
        },
        ScenarioContract(
            media="selected save device contains a corrupt THE.GAME with a valid MORIA8.ID marker",
            start="title load command against corrupt save media",
            ordered_events=("corrupt_save_error", "safe_return_after_corrupt_save"),
            event_counts=("corrupt_save_error=1",),
            forbidden_events=("load_success", "main_loop_from_corrupt_save"),
            screen_assertions=("Save file corrupt",),
            final_proof=("load does not resume gameplay from corrupt THE.GAME",),
        ),
    ),
    Scenario(
        "single_drive_corrupt_save_recovery_requires_program_disk",
        {
            "c64": strict("single_drive_load_corrupt_product_smoke"),
            "c128": strict("boot_title_single_drive_load_corrupt_smoke"),
            "plus4": strict("single_drive_load_corrupt_plus4"),
        },
        ScenarioContract(
            media="drive 8 starts with wrong-platform save disk; program disk is reattached only after program-media prompt",
            start="title load command in one-drive disk setup",
            ordered_events=("corrupt_save_error", "program_disk_prompt", "title_menu_ready"),
            event_counts=("corrupt_save_error=1", "program_disk_prompt=1"),
            forbidden_events=("main_loop", "garbled_title_return"),
            screen_assertions=("Save file corrupt", "Insert program disk", "title menu text"),
            final_proof=("title menu redraws after verified program media",),
        ),
    ),
    Scenario(
        "write_protected_or_forced_write_error",
        {
            "c64": strict("save_media_fail_product_smoke", note="deterministic forced save-media failure fixture; physical write-protect remains separate debt"),
            "c128": strict("boot_title_save_media_fail_product_smoke", note="deterministic forced save-media failure fixture; physical write-protect remains separate debt"),
            "plus4": strict("save_media_fail_plus4", note="deterministic forced save-media failure fixture; physical write-protect remains separate debt"),
        },
        ScenarioContract(
            media="selected save device contains a deterministic failure fixture that cannot be accepted for writing",
            start="gameplay save path attempts to use the configured save device",
            ordered_events=("save_device_selected", "forced_save_media_failure", "save_failure_prompt"),
            event_counts=("forced_save_media_failure=1", "save_success=0"),
            forbidden_events=("save_success", "game_saved_message", "write_success_after_failure"),
            screen_assertions=("save failure prompt",),
            final_proof=("save path reaches the failure/dismiss prompt instead of reporting success",),
        ),
    ),
)

#!/usr/bin/env python3
"""Plus/4 cartridge Disk Setup, repeated media checks and disk/CRT save interchange.

Save/load tests use real input/dispatch/slot selection and inspect state at the
real JSR return; no driver code is written into the dungeon being saved.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess

from test_cartridge import Experiment, ROOT, prepare_run
import catalog_disk
import make_plus4_magic


def blank_disk(args: argparse.Namespace, name: str) -> Path:
    path = args.output.resolve() / (name + ".d64")
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [args.c1541, "-format", "moria8save,08", "d64", str(path)],
        check=True,
        capture_output=True,
        timeout=10,
    )
    return path


def setup(exp: Experiment, initialize: bool = False, disk_build: bool = False, drive: int = 8) -> None:
    exp.key_at_input("D")
    exp.until(exp.sym["tramp_disk_setup"])
    exp.key_at_input("2" if disk_build or drive == 9 else "1")
    if disk_build or drive == 9:
        exp.key_at_input(str(drive))
        exp.key_at_input("\r")
        exp.key_at_input("3")
    exp.until(exp.sym["uds_insert_prompt_wait_key"])
    expected_save = drive if (disk_build or drive == 9) else 8
    assert exp.memory(exp.sym["save_device"], 1) == bytes([expected_save])
    exp.key_at_input(" ")
    if initialize:
        exp.until(exp.sym["uds_show_init_prompt"])
        exp.key_at_input("Y")
    exp.until(exp.sym["title_menu_loop"])
    assert exp.memory(exp.sym["program_device"], 1) == b"\x08"
    assert exp.memory(exp.sym["save_device"], 1) == bytes([expected_save])
    assert exp.memory(exp.sym["disk_mode"], 1) == bytes([2 if (disk_build or drive == 9) else 1])
    assert exp.memory(exp.sym["disk_setup_done"], 1) == b"\x02"
    if not disk_build:
        exp.forbidden = {exp.sym["disk_prompt"], exp.sym["hal_storage_init_selected_drive"]}


def create_character(exp: Experiment) -> None:
    exp.key_at_input("N")
    exp.until(exp.sym["create_select_race"])
    for key, target in (
        ("A", "create_roll_stats"),
        ("\r", "create_select_class"),
        ("A", "create_enter_name"),
    ):
        exp.key_at_input(key)
        exp.until(exp.sym[target])
    exp.keys("P4TEST\r")
    exp.until(exp.sym["create_select_gender"])
    exp.key_at_input("A")
    exp.until(exp.sym["input_get_modal_dismiss_key"])
    exp.key_at_input(" ")
    exp.until(exp.sym["main_loop"])


def snapshot(exp: Experiment) -> dict[str, bytes]:
    player = catalog_disk.consts(ROOT / "core/6502/player.s")
    slots = catalog_disk.consts(ROOT / "core/6502/item_defs.s")["TOTAL_INV_SLOTS"]
    ram = exp.memory(0x0400, 0xFC00)

    def span(address: int, size: int) -> bytes:
        return ram[address - 0x0400:address - 0x0400 + size]

    return {
        "player": span(exp.sym["player_data"], player["PL_STRUCT_SIZE"]),
        "map": span(make_plus4_magic.MAP_BASE, 80 * 48),
        **{
            name: span(exp.sym[name], slots)
            for name in (
                "inv_item_id",
                "inv_qty",
                "inv_p1",
                "inv_to_hit",
                "inv_to_dam",
                "inv_to_ac",
                "inv_flags",
                "inv_ego",
            )
        },
    }


def save(exp: Experiment, overwrite: bool = False, cancel: bool = False) -> dict[str, bytes] | None:
    exp.key_at_input(bytes([0xD3]))  # SHIFT+S, normal Save and Quit dispatch
    exp.key_at_input("1")             # real slot selector
    exp.until(exp.sym["save_game"])
    target = exp.return_address()
    if overwrite:
        exp.key_at_input("N" if cancel else "Y")
    if not cancel:
        exp.until(exp.sym["save_write_block"])
    previous = set(getattr(exp, "forbidden", ()))
    exp.forbidden = previous | {exp.sym["input_get_modal_dismiss_key"]}
    if not cancel:
        exp.forbidden.add(exp.sym["save_return_fail"])
    try:
        for _ in range(4):
            if exp.until(target, alternatives=(exp.sym["msg_show_more"],)) == target:
                break
            exp.key_at_input(" ")
        else:
            raise AssertionError("Unexpected repeated save message paging")
    finally:
        exp.forbidden = previous
    exp.assert_carry(expected=not cancel)
    return None if cancel else snapshot(exp)


def load(exp: Experiment, expected: dict[str, bytes]) -> None:
    exp.key_at_input("L")
    exp.until(exp.sym["title_load_game"])
    exp.key_at_input("1")
    exp.until(exp.sym["load_game"])
    target = exp.return_address()
    exp.until(target)
    exp.assert_carry()
    assert snapshot(exp) == expected, "Save representation changed across builds"
    exp.until(exp.sym["main_loop"])


def test_setup(args: argparse.Namespace) -> int:
    disk = blank_disk(args, "setup")
    exp = Experiment(args, name="setup-cancel", disk=disk)
    try:
        exp.until(exp.sym["title_menu_loop"])
        exp.key_at_input("D")
        exp.until(exp.sym["tramp_disk_setup"])
        exp.key_at_input("Q")
        exp.until(exp.sym["title_menu_loop"])
        assert exp.memory(exp.sym["disk_setup_done"], 1) == b"\0"
        exp.check("cancelled Disk Setup leaves persistence unconfigured")
        setup(exp, initialize=True)
        exp.check("single-drive Disk Setup initializes device 8 from cold cartridge boot")
        for irq_masked in (False, True):
            exp.call(exp.sym["disk_prompt_save"], irq_masked=irq_masked)
            assert exp.memory(exp.sym["disk_setup_done"], 1) == b"\x02"
        exp.check("consecutive preparations preserve IRQ state without drive init or swap prompts")
        exp.write(exp.sym["disk_setup_done"], b"\0")
        exp.call(exp.sym["disk_require_save_media"], carry=True)
        exp.write(exp.sym["disk_setup_done"], b"\x02")
        exp.write(exp.sym["disk_mode"], b"\0")
        exp.call(exp.sym["disk_require_save_media"], carry=True)
        exp.write(exp.sym["disk_mode"], b"\x01")
        exp.check("save-media validation still rejects incomplete setup")
        unmarked = blank_disk(args, "unmarked")
        exp.cmd(f'attach "{unmarked}" 8')
        exp.call(exp.sym["disk_require_save_media"], carry=True)
        exp.cmd(f'attach "{disk}" 8')
        exp.forbidden.remove(exp.sym["hal_storage_init_selected_drive"])
        exp.call(exp.sym["disk_init_drive"])
        exp.forbidden.add(exp.sym["hal_storage_init_selected_drive"])
        exp.call(exp.sym["disk_require_save_media"])
        exp.check("marker validation rejects changed media and explicit drive recovery restores access")
        exp.call(exp.sym["hal_storage_probe_media"], x=10, carry=True)
        exp.call(exp.sym["hal_storage_probe_media"], x=8)
        exp.check("device probe rejects absent unit 10 and accepts present drive 8")
        return exp.count
    finally:
        exp.close()


def mutate_save_disk(
    args: argparse.Namespace, src_disk: Path, name: str, mutator
) -> Path:
    dst = args.output.resolve() / f"{name}.d64"
    shutil.copyfile(src_disk, dst)
    seq_tmp = args.output.resolve() / f"{name}.the.game"
    seq_tmp.unlink(missing_ok=True)
    subprocess.run(
        [args.c1541, "-attach", str(dst), "-read", "the.game,s", str(seq_tmp)],
        check=True,
        capture_output=True,
        timeout=10,
    )
    blob = bytearray(seq_tmp.read_bytes())
    mutator(blob)
    seq_tmp.write_bytes(blob)
    subprocess.run(
        [args.c1541, "-attach", str(dst), "-delete", "the.game", "-write", str(seq_tmp), "the.game,s"],
        check=True,
        capture_output=True,
        timeout=10,
    )
    seq_tmp.unlink(missing_ok=True)
    return dst


def test_negative_saves(args: argparse.Namespace, valid_disk: Path) -> int:
    def set_old_version(blob: bytearray) -> None:
        assert blob[7] == 0x22, f"Unexpected save version {blob[7]:#x}"
        blob[7] = 0x21

    def corrupt_payload(blob: bytearray) -> None:
        assert len(blob) > 100
        blob[100] ^= 0x55

    checks = 0
    for name, mutator, want_result in (
        ("wrong-v21", set_old_version, 4),
        ("corrupt-checksum", corrupt_payload, 2),
    ):
        bad_disk = mutate_save_disk(args, valid_disk, name, mutator)
        exp = Experiment(args, name=f"cart-neg-{name}", disk=bad_disk)
        try:
            exp.until(exp.sym["title_menu_loop"])
            setup(exp)
            exp.forbidden.add(exp.sym["main_loop"])
            exp.key_at_input("L")
            exp.until(exp.sym["title_load_game"])
            exp.key_at_input("1")
            exp.until(exp.sym["input_get_modal_dismiss_key"])
            got = exp.memory(exp.sym["load_result"], 1)[0]
            assert got == want_result, f"{name}: load_result={got}, expected {want_result}"
            exp.key_at_input(" ")
            exp.until(exp.sym["title_menu_loop"])
            exp.check(f"cartridge load rejected {name} save cleanly (load_result={want_result})")
            checks += exp.count
        finally:
            exp.close()
    return checks


def test_interchange(args: argparse.Namespace) -> int:
    disk = blank_disk(args, "interchange")
    exp = Experiment(args, name="disk-save", disk=disk, disk_build=True)
    try:
        setup(exp, initialize=True, disk_build=True, drive=9)
        create_character(exp)
        expected = save(exp)
        exp.check("disk edition writes a save through real command and slot dispatch")
    finally:
        exp.close()

    # Cartridge loads the Drive 8 save (also exercises single-drive device 8)
    exp = Experiment(args, name="cartridge-load-save", disk=disk)
    try:
        exp.until(exp.sym["title_menu_loop"])
        setup(exp)
        # Seed a stale non-8 prompt device (e.g. failed Drive 10 probe) before loading Drive 8.
        exp.write(exp.sym["disk_prompt_device"], b"\x0a")
        load(exp, expected)
        exp.check("cartridge loads the disk save and resumes play")
        original_disk = disk.read_bytes()
        save(exp, overwrite=True, cancel=True)
        assert disk.read_bytes() == original_disk
        exp.check("cancelled overwrite preserves the existing save disk")
        exp.until(exp.sym["main_loop"])
        expected = save(exp, overwrite=True)
        exp.check("cartridge saves again on Drive 8 without a disk-swap prompt")
    finally:
        exp.close()

    exp = Experiment(args, name="disk-load", disk=disk, disk_build=True)
    try:
        setup(exp, disk_build=True, drive=9)
        load(exp, expected)
        exp.check("disk edition loads cartridge save with player, inventory and map intact")
    finally:
        exp.close()
    return 5 + test_negative_saves(args, disk)


def test_drive9_cartridge(args: argparse.Namespace) -> int:
    disk9 = blank_disk(args, "drive9")
    exp = Experiment(args, name="cartridge-drive9", disk=None, enable_drive9=True)
    try:
        exp.until(exp.sym["title_menu_loop"])
        exp.cmd(f'attach "{disk9}" 9')
        setup(exp, initialize=True, drive=9)
        create_character(exp)
        expected = save(exp)
        exp.until(exp.sym["title_menu_loop"])
        load(exp, expected)
        exp.check("cartridge saves and reloads on IEC Drive 9")
        return exp.count
    finally:
        exp.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crt", type=Path, required=True)
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--disk-image", type=Path, required=True)
    parser.add_argument("--disk-symbols", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--vice", default="xplus4")
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--ntsc", action="store_true")
    args = parser.parse_args()
    prepare_run(args)
    total = test_setup(args) + test_interchange(args) + test_drive9_cartridge(args)
    print(f"Plus/4 cartridge persistence: {total} checks passed", flush=True)

#!/usr/bin/env python3
"""ITEM.CAT reads on game entry and on a stairs level change (stock C64, no REU).

A stock 1541 pays about 0.3 s to fetch a sector and about 2 ms a byte to send
it, and level entry made dozens of ITEM.CAT reads: entering the game took 53
whole-sector reads, 6 s of warp time, and pushed test64-legal's Help mode past
its 30 s deadline (2026-11-20). Three facts are checked here:

1. Every miss of hal_item_cat_read_byte transfers at most ICR_WINDOW bytes
   (item_catalog_records.s), never the whole 252/254-byte sector.
2. A stairs level change keeps the item pickup cache's records (immutable
   catalog facts: the carried items' weights and names): the pool held before
   the descent is still the start of the pool after it, so the carried items
   are not read from ITEM.CAT again (item_pickup_cache_prewarm tops up while the
   pool is under half full).
3. With the stock C64 KERNAL's safe-IEC hook installed ($0324/$0330), every
   serial EOI receive (all KERNAL LOADs and all CHRINs, not just ITEM.CAT)
   enters `c64_acptr_eoi_resume` during VIC-II vertical blank ($D011 bit 7 == 1),
   avoiding badline deferral on mixed stock-KERNAL + JiffyDOS-1541 setups
   (`--dos1541`).
4. A sector-0 miss at a non-zero offset (ITEM.CAT offset 32) still checks
   'ITM2': on a formatted save disk whose U1 succeeds, it prompts via
   `asset_load_ask_for_disk` and recovers the exact byte once the program
   disk is re-attached.

Conditional breakpoints stop only on violations, so the game runs in warp
between checks. Each phase (disk boot and character creation, game entry, the
step and descent, and wrong-disk sector-0 offset-32 recovery) has its own 30 s
deadline.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools"))
from vice_connector import VICEConnector, allocate_free_port, parse_vs_symbols  # noqa: E402
from vice_config import vice_config  # noqa: E402

RECORDS = ROOT / "platforms" / "commodore" / "common" / "item_catalog_records.s"
POOL_BASE = 0xDD2A           # memory.s ITEM_PICKUP_CACHE_BASE (C64 disk)
POOL_SIZE = 470              # memory.s ITEM_PICKUP_CACHE_SIZE (asserted there)
KBDBUF, KBDCOUNT = 0x0277, 0x00C6
# N (new), A (Human), CR (stats), A (Warrior), A + CR (name), B (gender).
CHARGEN_KEYS = [0x4E, 0x41, 0x0D, 0x41, 0x41, 0x0D, 0x42]
SPACE, STEP_EAST, DOWN = 0x20, 0x4C, 0x3E   # begin; 'L' onto the town's '>'; descend
HEX = re.compile(r"^[0-9A-Fa-f]{2}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--boot-d64", default=str(ROOT / "build" / "moria8-c64.d64"))
    parser.add_argument("--vs", default=str(ROOT / "build" / "c64" / "main.vs"))
    parser.add_argument("--dos1541", default="", help="optional 1541 DOS ROM path (e.g. JiffyDOS 1541)")
    parser.add_argument("--timeout", type=float, default=30.0, help="seconds for each phase")
    args = parser.parse_args()

    if args.dos1541 and not Path(args.dos1541).is_file():
        print(f"FAIL: --dos1541 ROM not found: {args.dos1541}")
        return 2

    boot_d64 = Path(args.boot_d64).resolve()
    item_cat_path = Path(args.vs).resolve().parent / "item.cat"
    if not item_cat_path.is_file():
        item_cat_path = ROOT / "build" / "c64" / "item.cat"
    expected_s0_32 = item_cat_path.read_bytes()[2 + 32]

    window = int(re.search(r"^\.const ICR_WINDOW\s*=\s*(\d+)", RECORDS.read_text(), re.M).group(1))
    sym = {k.lstrip("."): int(v, 16) for k, v in parse_vs_symbols(args.vs).items()}
    port = allocate_free_port()
    drive_args = (
        ["-drive8type", "1541", "-drive8truedrive", "-dos1541", str(Path(args.dos1541).resolve())]
        if args.dos1541
        else []
    )
    vice = subprocess.Popen(
        [args.vice, "-config", vice_config(args.vice), "-default", "+saveres", "+autostart-delay-random", "+reu",
         *drive_args,
         "-console", "-warp", "+sound", "-sounddev", "dummy", "-remotemonitor", "-remotemonitoraddress",
         f"127.0.0.1:{port}", "-autostart", str(boot_d64)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = [0.0, ""]
    mon = VICEConnector(port=port, timeout=5.0)

    def phase(name: str) -> None:
        deadline[:] = [time.monotonic() + args.timeout, name]

    def left() -> float:
        remaining = deadline[0] - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"{deadline[1]}: over its {args.timeout:.0f} s deadline")
        return remaining

    def read(addr: int, count: int, bank: str = "cpu") -> list[int]:
        if bank != "cpu":
            mon.send_command(f"bank {bank}")
        out = mon.send_command(f"m {addr:04x} {addr + count - 1:04x}")
        if bank != "cpu":
            mon.send_command("bank cpu")
        values = []
        for line in out.splitlines():
            if line.startswith(">C:"):
                for token in line.split()[1:]:
                    if not HEX.match(token):
                        break
                    values.append(int(token, 16))
        return values[:count]

    def regs() -> tuple[int, int, int]:
        row = next(l for l in mon.send_command("r").splitlines() if l.strip().startswith(".;"))
        parts = row.split()
        return int(parts[0][2:], 16), int(parts[1], 16), int(parts[4], 16)

    def pc() -> int:
        return regs()[0]

    def attach(d64_path: Path) -> None:
        rsp = mon.send_command(f'attach "{d64_path}" 8')
        if "ERROR" in rsp:
            raise RuntimeError(f"VICE rejected attach {d64_path}: {rsp.strip()}")

    def add_break(cmd: str) -> None:
        rsp = mon.send_command(cmd)
        if "ERROR" in rsp or "BREAK:" not in rsp:
            raise RuntimeError(f"VICE rejected breakpoint {cmd!r}: {rsp.strip()}")

    def key(code: int) -> None:
        mon.send_command("del")
        add_break(f"break ${sym['input_get_key']:04x}")
        mon.go()
        if not mon.wait_for_stop(pass_addr=f"{sym['input_get_key']:04x}", timeout=left()).passed:
            raise RuntimeError("did not reach input_get_key")
        mon.poke(KBDBUF, code)
        mon.poke(KBDCOUNT, 1)

    def check_reads_until_main_loop(dlvl: int, verify_eoi_hit: bool = False) -> tuple[list[int], list[int], bool]:
        """Monitor ITEM.CAT misses over ICR_WINDOW and any serial EOI resume
        outside VBLANK ($D011 bit 7 == 0) until main_loop on dlvl."""
        def arm(watch_len: bool, watch_bad_eoi: bool, watch_any_eoi: bool) -> None:
            mon.send_command("del")
            add_break(f"break ${sym['main_loop']:04x} if @cpu:${sym['zp_player_dlvl']:04x} == ${dlvl:02x}")
            if watch_len:
                add_break(f"break ${sym['icr_read_sector_buf']:04x} if @cpu:${sym['icr_cache_len']:04x} > ${window:02x}")
            if watch_any_eoi:
                add_break(f"break ${sym['c64_acptr_eoi_resume']:04x}")
            elif watch_bad_eoi:
                add_break(f"break ${sym['c64_acptr_eoi_resume']:04x} if (@io:$d011 & $80) == $00")

        watch_any_eoi = verify_eoi_hit
        arm(True, True, watch_any_eoi)
        lengths: list[int] = []
        eoi_bad_d011: list[int] = []
        eoi_seen = False
        while True:
            mon.go()
            res = mon.wait_for_stop(pass_addr=f"{sym['main_loop']:04x}", timeout=left())
            if not res.last_status and res.reason.startswith("timeout"):
                raise TimeoutError(res.reason)
            cur_pc = pc()
            if cur_pc == sym["main_loop"]:
                return lengths, eoi_bad_d011, eoi_seen
            if cur_pc == sym["c64_acptr_eoi_resume"]:
                d011 = read(0xD011, 1, "io")[0]
                eoi_seen = True
                if (d011 & 0x80) == 0:
                    eoi_bad_d011.append(d011)
                if watch_any_eoi:
                    watch_any_eoi = False
                    arm(len(lengths) < 3, len(eoi_bad_d011) < 3, False)
                    continue
            else:
                lengths.append(read(sym["icr_cache_len"], 1)[0])
            if (cur_pc == sym["c64_acptr_eoi_resume"] and len(eoi_bad_d011) == 3) or (
                cur_pc != sym["c64_acptr_eoi_resume"] and len(lengths) == 3
            ):
                arm(len(lengths) < 3, len(eoi_bad_d011) < 3, watch_any_eoi)

    def pool() -> list[int]:
        end = read(sym["ipc_end_lo"], 1)[0] | read(sym["ipc_end_hi"], 1)[0] << 8
        if not POOL_BASE <= end <= POOL_BASE + POOL_SIZE:
            raise RuntimeError(f"ipc_end ${end:04X} outside the pool")
        return read(POOL_BASE, end - POOL_BASE, "ram") if end > POOL_BASE else []

    wrong_disk_ok = False
    wrong_disk_note = ""
    init_vectors_ok = False
    init_vec_ibasin = 0
    init_vec_iload = 0
    load_eoi_ok = False
    load_eoi_note = ""
    vectors_ok = False
    vec_ibasin = 0
    vec_iload = 0
    entry_eoi_seen = False
    restor_reinstall_ok = False
    restor_ibasin = 0
    restor_iload = 0
    try:
        phase("disk boot and character creation")
        mon.connect(retries=100, retry_delay=0.1)
        mon.send_command("del")
        add_break(f"break ${sym['init_load_banked']:04x}")
        mon.go()
        if not mon.wait_for_stop(pass_addr=f"{sym['init_load_banked']:04x}", timeout=left()).passed:
            raise RuntimeError("did not reach init_load_banked")
        v24 = read(0x0324, 2)
        v30 = read(0x0330, 2)
        init_vec_ibasin = v24[0] | (v24[1] << 8)
        init_vec_iload = v30[0] | (v30[1] << 8)
        init_vectors_ok = (
            init_vec_ibasin == sym["c64_basin_safe"]
            and init_vec_iload == sym["c64_iload_safe"]
        )
        mon.send_command("del")
        add_break(f"break ${sym['c64_acptr_eoi_resume']:04x}")
        add_break(f"break ${sym['title_enter_menu']:04x}")
        mon.go()
        res = mon.wait_for_stop(pass_addr=f"{sym['c64_acptr_eoi_resume']:04x}", timeout=left())
        if not res.last_status and res.reason.startswith("timeout"):
            raise TimeoutError(res.reason)
        if pc() == sym["c64_acptr_eoi_resume"]:
            load_eoi_d011 = read(0xD011, 1, "io")[0]
            load_eoi_ok = (load_eoi_d011 & 0x80) != 0
            if not load_eoi_ok:
                load_eoi_note = f"64.BANK LOAD EOI resumed outside VBLANK ($D011=${load_eoi_d011:02X})"
        else:
            load_eoi_note = f"64.BANK LOAD skipped c64_acptr_eoi_resume (stopped at ${pc():04X})"
        for code in CHARGEN_KEYS:
            key(code)
            if code == CHARGEN_KEYS[0]:
                if read(sym["reu_present"], 1) != [0]:
                    print("FAIL: an REU is present; this smoke is for the stock disk path")
                    return 2
                v24 = read(0x0324, 2)
                v30 = read(0x0330, 2)
                vec_ibasin = v24[0] | (v24[1] << 8)
                vec_iload = v30[0] | (v30[1] << 8)
                vectors_ok = (
                    vec_ibasin == sym["c64_basin_safe"]
                    and vec_iload == sym["c64_iload_safe"]
                )
        key(SPACE)
        phase("game entry")
        entry, entry_bad_eoi, entry_eoi_seen = check_reads_until_main_loop(0, verify_eoi_hit=True)
        phase("descent")
        key(STEP_EAST)
        # Simulate RUN/STOP-RESTORE clobbering IBASIN/ILOAD back to stock ROM
        # defaults while parked for input; main_loop must re-install before DOWN.
        mon.poke(0x0324, 0x57)
        mon.poke(0x0325, 0xF1)
        mon.poke(0x0330, 0xA5)
        mon.poke(0x0331, 0xF4)
        before = pool()
        key(DOWN)
        rv24 = read(0x0324, 2)
        rv30 = read(0x0330, 2)
        restor_ibasin = rv24[0] | (rv24[1] << 8)
        restor_iload = rv30[0] | (rv30[1] << 8)
        restor_reinstall_ok = (
            restor_ibasin == sym["c64_basin_safe"]
            and restor_iload == sym["c64_iload_safe"]
        )
        descend, descend_bad_eoi, _ = check_reads_until_main_loop(1)
        after = pool()

        phase("wrong-disk sector-0 offset-32 recovery")
        with tempfile.TemporaryDirectory(dir=boot_d64.parent) as tmpdir:
            wrong_d64 = Path(tmpdir) / "wrong.d64"
            subprocess.run(
                [args.c1541, "-format", "save,s1", "d64", str(wrong_d64)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            attach(wrong_d64)
            mon.poke(sym["icr_cache_valid"], 0)
            mon.poke(sym["item_cat_off_lo"], 0x20)
            mon.poke(sym["item_cat_off_hi"], 0x00)
            mon.poke(KBDCOUNT, 0)
            _, _, sp = regs()
            ret_m1 = sym["main_loop"] - 1
            mon.poke(0x0100 + sp, ret_m1 >> 8)
            mon.poke(0x0100 + ((sp - 1) & 0xFF), ret_m1 & 0xFF)
            mon.set_register("sp", (sp - 2) & 0xFF)
            mon.set_register("pc", sym["hal_item_cat_read_byte"])
            mon.send_command("del")
            add_break(f"break ${sym['asset_load_ask_for_disk']:04x}")
            add_break(f"break ${sym['main_loop']:04x}")
            mon.go()
            res = mon.wait_for_stop(pass_addr=f"{sym['asset_load_ask_for_disk']:04x}", timeout=left())
            if not res.last_status and res.reason.startswith("timeout"):
                raise TimeoutError(res.reason)
            stop_pc = pc()
            if stop_pc != sym["asset_load_ask_for_disk"]:
                got_a = regs()[1]
                wrong_disk_note = (
                    f"sector-0 offset-32 read on blank disk returned ${got_a:02X} to ${stop_pc:04X} "
                    f"without prompting"
                )
            else:
                attach(boot_d64)
                key(SPACE)
                mon.send_command("del")
                add_break(f"break ${sym['main_loop']:04x}")
                mon.go()
                res = mon.wait_for_stop(pass_addr=f"{sym['main_loop']:04x}", timeout=left())
                if not res.last_status and res.reason.startswith("timeout"):
                    raise TimeoutError(res.reason)
                got_pc, got_a, _ = regs()
                if got_pc != sym["main_loop"] or got_a != expected_s0_32:
                    wrong_disk_note = (
                        f"recovery returned A=${got_a:02X} at ${got_pc:04X}, "
                        f"expected ${expected_s0_32:02X} at ${sym['main_loop']:04X}"
                    )
                else:
                    wrong_disk_ok = True
    except (TimeoutError, RuntimeError, ConnectionError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}")
        return 2
    finally:
        vice.kill()

    failures = []
    if not init_vectors_ok:
        failures.append(
            f"safe IEC vectors not installed at init_load_banked: "
            f"$0324=${init_vec_ibasin:04X} (expected ${sym['c64_basin_safe']:04X}), "
            f"$0330=${init_vec_iload:04X} (expected ${sym['c64_iload_safe']:04X})"
        )
    if not load_eoi_ok:
        failures.append(load_eoi_note or "64.BANK LOAD did not enter c64_acptr_eoi_resume")
    if not vectors_ok:
        failures.append(
            f"safe IEC vectors not installed: $0324=${vec_ibasin:04X} (expected ${sym['c64_basin_safe']:04X}), "
            f"$0330=${vec_iload:04X} (expected ${sym['c64_iload_safe']:04X})"
        )
    if not entry_eoi_seen:
        failures.append("game entry never reached c64_acptr_eoi_resume")
    if not restor_reinstall_ok:
        failures.append(
            f"safe IEC vectors not re-installed on main_loop after simulated RESTOR: "
            f"$0324=${restor_ibasin:04X} (expected ${sym['c64_basin_safe']:04X}), "
            f"$0330=${restor_iload:04X} (expected ${sym['c64_iload_safe']:04X})"
        )
    for phase_name, over, bad_eoi in (
        ("game entry", entry, entry_bad_eoi),
        ("descent", descend, descend_bad_eoi),
    ):
        if over:
            failures.append(f"{phase_name}: ITEM.CAT misses read more than ICR_WINDOW={window} bytes ({over})")
        if bad_eoi:
            failures.append(f"{phase_name}: serial EOI resume entered outside VBLANK ($D011={bad_eoi})")
    if not wrong_disk_ok:
        failures.append(wrong_disk_note or "wrong-disk sector-0 offset-32 check did not complete")
    if len(before) * 2 < POOL_SIZE and after[:len(before)] != before:
        failures.append(f"descent reset the pickup cache: {len(before)} B held before, the pool after starts "
                        f"differently ({len(after)} B)")
    if len(before) * 2 >= POOL_SIZE:
        failures.append(f"the pool was already {len(before)} B before the descent: check 2 cannot run")
    summary = (f"ICR_WINDOW {window} B; pickup cache {len(before)} B before the descent, "
               f"{len(after)} B after, prefix kept={after[:len(before)] == before}, "
               f"64.BANK LOAD EOI={load_eoi_ok}, RESTOR re-install={restor_reinstall_ok}, "
               f"wrong-disk s0@32={wrong_disk_ok}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        print(summary)
        return 1
    print(f"PASS: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

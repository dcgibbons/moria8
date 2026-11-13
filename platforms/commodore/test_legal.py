#!/usr/bin/env python3
"""Exercise the shipped disk product's title/Help legal viewer in VICE.

Input is injected at the existing HAL get-key call boundary; every loader,
trampoline, stream, renderer and return runs the linked production code.
Each emulator has one 30-second deadline, including startup and cleanup.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from vice_connector import VICEConnector, allocate_free_port
from vice_config import vice_config


def run(args: argparse.Namespace, output: Path, mode: str = "title") -> None:
    port = args.port
    output.mkdir(parents=True, exist_ok=False)
    sym = {name: int(value, 16) for name, value in re.findall(
        r"\.label (\w+)=\$([0-9a-fA-F]+)",
        args.symbols.read_text())}
    vice = args.vice
    image = args.disk_image
    if mode == "missing":
        fixture = output / ("missing-license" + image.suffix)
        shutil.copyfile(image, fixture)
        subprocess.run([args.c1541, "-attach", str(fixture), "-delete", "license"],
                       check=True, capture_output=True, timeout=10)
        wrap_image = output / ("layout-boundaries" + image.suffix)
        shutil.copyfile(image, wrap_image)
        width = 80 if port == "c128" else 40
        # On 40 columns this puts CR at byte 127 and LF at byte 128, proving
        # normalization across refills as well as exact-width line endings.
        payload = (b"A" * (width - 2) + b"\r\n" + b"B" * (width - 1) + b"\r\n"
                   + b"C" * width + b"\r\nTAIL\r\n" + b"\r\n" * 15 + b"EDGE\r\n")
        text = output / "layout.seq"
        text.write_bytes(payload)
        subprocess.run([args.c1541, "-attach", str(wrap_image), "-delete", "license",
                        "-write", str(text), "license,s", "-name", "legal layout,lw", "8"],
                       check=True, capture_output=True, timeout=10)
        image = fixture
    if mode == "swap":
        save_disk = output / ("separate-save" + args.disk_image.suffix)
        disk_format = "d71" if port == "c128" else "d64"
        subprocess.run([args.c1541, "-format", "legal test,lt", disk_format, str(save_disk)],
                       check=True, capture_output=True, timeout=10)
    endpoint = allocate_free_port()
    mon = VICEConnector(port=endpoint, timeout=0.2)
    deadline = time.monotonic() + 30
    command = [vice, "-config", vice_config(vice), "-default", "+saveres",
               "+autostart-delay-random", "-console", "-nativemonitor", "-warp",
               "+sound", "-sounddev", "dummy", "+confirmonexit",
               "-8", str(image), "-remotemonitor", "-remotemonitoraddress",
               f"127.0.0.1:{endpoint}"]
    if port == "c128":
        command.append("-80col")
    elif port == "c64":
        command += ["-autostartprgmode", "1"]
    with (output / "vice.log").open("wb", buffering=0) as log:
        proc = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                env=dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy"))
        timer = threading.Timer(max(0, deadline - time.monotonic()), proc.kill)
        timer.start()
        def cmd(text: str) -> str:
            with (output / "monitor.log").open("a") as trace:
                trace.write(text + "\n")
                response = mon.send_command(text, deadline=deadline)
                trace.write(response + "\n")
            assert not re.search(r"(?im)^\s*(ERROR|Unknown command|Unknown bank name|Syntax error)\b", response), response
            return response
        def until(label: str, offset: int = 0) -> None:
            addr = sym[label] + offset
            if re.search(rf"(?im)^\s*\.;{addr:04x}\s", cmd("r")):
                return
            cmd("del")
            # Match RAM instructions, including below BASIC, without trapping
            # an unrelated KERNAL address while its loader is still active.
            guard = ""
            if port == "c64" and addr >= 0xE000:
                guard = " if (@cpu:$0001 & $02) == $00"
            elif port == "c64" and 0xA000 <= addr < 0xC000:
                guard = " if (@cpu:$0001 & $03) != $03"
            elif port == "c128" and addr >= 0xE000:
                guard = " if @cpu:$ff00 == $3e"
            cmd(f"break ${addr:04x}{guard}")
            if label == "legal_page_wait":
                cmd(f"break ${sym['legal_read_error']:04x}{guard}")
            response = cmd("g")
            assert re.search(rf"(?:C:|PC:|PC=)\$?{addr:04x}", response, re.I), response
        def memory(addr: int, count: int, bank: str = "ram") -> bytes:
            target = output / "memory.bin"
            target.unlink(missing_ok=True)
            cmd(f"bank {bank}")
            cmd(f'bsave "{target}" 0 ${addr:04x} ${addr+count-1:04x}')
            cmd("bank cpu")
            result = target.read_bytes()
            assert len(result) == count
            return result
        def key(ch: str) -> None:
            if port == "c128":
                labels = ("hal_input_get_key", "input_get_key_fast")
                registers = cmd("r")
                if not any(re.search(rf"(?im)^\s*\.;{sym[label]:04x}\s", registers) for label in labels):
                    cmd("del")
                    for label in labels:
                        cmd(f"break ${sym[label]:04x}")
                    cmd("g")
            else:
                until("hal_input_get_key")
            row = next(line for line in cmd("r").splitlines() if line.strip().startswith(".;"))
            sp = int(row.split()[4], 16)
            ret = int.from_bytes(memory(0x101 + sp, 2), "little") + 1
            cmd(f"r a={ord(ch):02x}")
            cmd(f"r sp={(sp+2)&255:02x}")
            cmd(f"r pc={ret:04x}")
        def page() -> None:
            if mode == "title" and port != "c128":
                # HAL full-clear contract: every visible cell and attribute,
                # including the 232-byte tail, belongs to the new page.
                until("legal_page_begin")
                screen_base = 0x0C00 if port == "plus4" else 0x0400
                color_base = 0x0800 if port == "plus4" else 0xD800
                for base in (screen_base, color_base):
                    for offset in range(768, 1000, 32):
                        data = bytes([0x0A]) * min(32, 1000 - offset)
                        cmd(f"> {base + offset:04x} " + data.hex(" "))
                color = memory(sym["zp_text_color"], 1)[0]
                until("legal_page_begin", 3)  # Production full clear returned.
                assert memory(screen_base, 1000) == b" " * 1000, "Full clear left stale text"
                expected = 0x71 if port == "plus4" else color
                attrs = memory(color_base, 1000, "cpu")
                assert bytes(a & (0x7F if port == "plus4" else 0x0F) for a in attrs) == bytes([expected]) * 1000, "Full clear left stale attributes"
            until("legal_page_wait")
        def has(text: str) -> None:
            if port == "c128":
                screen = memory(0, 80*25, "vdc")
            else:
                screen = memory(0x0C00 if port == "plus4" else 0x0400, 1000)
            # Uppercase in the shared font is screen code ASCII $41..$5A.
            expected = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in text)
            assert expected in screen, f"{port}: missing {text!r}"
        try:
            mon.connect()
            cmd("del")
            initial = sym["title_menu_loop"] if port == "c128" else sym["entry"]
            cmd(f"break ${initial:04x}")
            # The existing boot suites own the disk chain. Injecting the
            # same product PRG leaves this modal test enough of its 30-second
            # budget for real 1541 overlay/document loads under parallel load.
            program = args.program if port == "c64" and mode != "boot" else image
            cmd(f'autostart "{program}"')
            if port == "c64" and mode != "boot":
                until("entry")
                cmd("> ba 08")  # Device fixture normally supplied by boot LOAD.
            until("title_menu_loop")
            if mode == "boot":
                key("A")
                until("legal_menu_wait")
                key("Q")
                until("title_menu_loop")
                print(f"PASS {port}: shipped disk boot -> legal viewer -> title", flush=True)
                return
            basic_snapshot = memory(sym["zp_save_buf"], 142) if port == "c64" else None
            if mode == "help":
                key("N")
                until("create_select_race")
                key("A")
                until("create_roll_stats")
                key("\r")
                until("create_select_class")
                key("A")
                until("create_enter_name")
                key("V")
                key("\r")
                until("create_select_gender")
                key("A")
                until("input_get_modal_dismiss_key")
                key(" ")
                until("main_loop")
                def state():
                    return (memory(sym["player_data"], 111), memory(0x40, 2),
                            memory(0x1A, 4),
                            memory(sym["inv_item_id"], 33),
                            memory(0x4000, 13068, "ram01") if port == "c128"
                            else memory(0xC800 if port == "plus4" else 0xC000, 3840))
                before = state()
                key("?")
                until("hal_input_get_key")
                has("L:License")
                key(" ")
                until("hal_input_get_key")
                has("L License / Source")
                key("L")
            elif mode == "swap":
                cmd(f"> {sym['disk_mode']:04x} 01")
                cmd(f"> {sym['save_device']:04x} 08")
                if port == "c128":
                    cmd(f"> {sym['c128_media_state']:04x} 02")
                cmd(f'attach "{save_disk}" 8')
                if port != "c128":
                    cmd(f"> {sym['zp_msg_flags']:04x} 03")
                key("A")
                until("disk_prompt" if port == "c128" else "disk_prompt_game_required_error_shown")
                cmd(f'attach "{args.disk_image}" 8')
                key(" ")
            else:
                # A cancelled Disk Setup can leave this internal prompt byte
                # on the save drive; legal entry must select program_device.
                cmd(f"> {sym['disk_prompt_device']:04x} 09")
                if mode == "title":
                    cmd(f"> {sym['zp_snd_effect']:04x} 00 01 01")
                    cmd(f"> {sym['zp_ui_dirty']:04x} 01")
                key("A")
            if mode == "title":
                until("legal_viewer")
                saved = sym["legal_zp_save"]
                assert memory(saved + sym["zp_snd_effect"] - 2, 3) == bytes((0, 1, 1))
                # Model a sound that expired in a slow loader/retry prompt,
                # and an additional redraw producer, after the snapshot.
                cmd(f"> {sym['zp_snd_effect']:04x} ff 00 00")
                cmd(f"> {sym['zp_ui_dirty']:04x} 80")
            until("legal_menu_wait")
            if mode == "swap" and port != "c128":
                assert memory(sym["legal_zp_save"] + sym["zp_msg_flags"] - 2, 1) == b"\0", "Snapshot predates message reset"
            if mode == "title":
                assert memory(sym["zp_snd_effect"], 3) == bytes((255, 0, 0)), "Entry resurrected expired sound"
                assert memory(sym["zp_ui_dirty"], 1) == b"\x81", "Entry lost a redraw producer"
            if mode == "fault":
                # Title-only idle map/creature RAM. Replace only transport
                # JSR operands, retaining the actual linked fill/read/render
                # code, banking wrappers, document OPEN/CLOSE and error UI.
                scratch = {"c64": 0xC600, "c128": 0x1B00, "plus4": 0xCE00}[port]
                read_stub, status_stub = scratch, scratch + 8
                original = memory(scratch, 40)
                read_operand = sym["legal_fill_read"] + 1
                status_operand = sym["legal_fill_status"] + 1
                original_read = memory(read_operand, 2)
                original_status = memory(status_operand, 2)
                def put(addr, data):
                    data = bytes(data)
                    # VICE's text monitor truncates long command lines.
                    for offset in range(0, len(data), 32):
                        cmd(f"> {addr + offset:04x} " + data[offset:offset + 32].hex(" "))
                put(read_stub, (0xA9, ord("Z"), 0x60))
                put(read_operand, read_stub.to_bytes(2, "little"))
                put(status_operand, status_stub.to_bytes(2, "little"))
                for index, status in ((0, 0x02), (0, 0x80), (0, 0x42), (63, 0x02), (127, 0x02), (0, 0x40)):
                    # LDX #counter; INC counter; CPX #index; BCC good;
                    # LDA #status; RTS; good: LDA #0; RTS.
                    counter = status_stub + 1
                    put(status_stub, (0xA2, 0, 0xEE, counter & 255, counter >> 8,
                                      0xE0, index, 0x90, 3, 0xA9, status, 0x60, 0xA9, 0, 0x60))
                    put(sym["legal_input_cache"], b"\xa5" * 128)
                    key("1")
                    if status != 0x40:
                        until("legal_read_error")
                        assert memory(sym["legal_eof"], 1) == bytes((status,))
                        assert memory(sym["legal_cache_index"], 1) == b"\0", "Failed refill exposed bytes"
                        assert memory(sym["legal_cache_count"], 1) == bytes((index,)), "Failed CHRIN was committed"
                        assert memory(sym["legal_input_cache"] + index, 1) == b"\xa5"
                        key(" ")
                        until("legal_menu_wait")
                    else:
                        until("legal_page_wait")
                        has("End. R: restart")
                        assert memory(sym["legal_cache_count"], 1) == b"\x01", "EOI final byte was discarded"
                        key("Q")
                        until("legal_menu_wait")
                put(read_operand, original_read)
                put(status_operand, original_status)
                put(scratch, original)
                key("Q")
                until("title_menu_loop")
                print(f"PASS {port}: production refill faults at 0/63/127, $02/$80/$42 reject data, $40 retains final byte", flush=True)
                return
            if mode == "open-retry":
                # Status loss is injected at the transport adapter; execute
                # real OPEN/CLOSE retries and the production renderer.
                scratch = {"c64": 0xC600, "c128": 0x1B00, "plus4": 0xCE00}[port]
                original = memory(scratch, 32)
                operand = sym["legal_open_status"] + 1
                original_operand = memory(operand, 2)
                cmd(f"> {operand:04x} " + scratch.to_bytes(2, "little").hex(" "))
                for losses, result, expected_calls in ((2, 0, 3), (0, 62, 1), (3, 0, 3)):
                    # LDX #counter; INC counter; CPX #losses; BCC lost;
                    # LDA #result; CLC; RTS; lost: SEC; RTS.
                    counter = scratch + 1
                    code = bytes((0xA2, 0, 0xEE, counter & 255, counter >> 8,
                                  0xE0, losses, 0x90, 4, 0xA9, result, 0x18, 0x60, 0x38, 0x60))
                    cmd(f"> {scratch:04x} " + code.hex(" "))
                    key("1")
                    if losses < 3 and result == 0:
                        until("legal_page_wait")
                        has("MORIA8 LICENSE NOTICE")
                        key("Q")
                    else:
                        until("legal_read_error")
                        key(" ")
                    until("legal_menu_wait")
                    assert memory(counter, 1) == bytes((expected_calls,)), "Wrong OPEN retry bound"
                    assert memory(sym["legal_opened"], 1) == b"\0"
                cmd(f"> {operand:04x} " + original_operand.hex(" "))
                cmd(f"> {scratch:04x} " + original.hex(" "))
                key("Q")
                until("title_menu_loop")
                print(f"PASS {port}: lost DOS status retries fresh OPEN, DOS error is final, retry exhaustion closes stream", flush=True)
                return
            key("1")
            if mode == "missing":
                until("legal_read_error")
                key(" ")
                until("legal_menu_wait")
                assert memory(sym["legal_opened"], 1) == b"\0"
                key("2")
                until("legal_page_wait")
                has("MORIA8 SOURCE OFFER")
                key("Q")
                until("legal_menu_wait")
                cmd(f'attach "{wrap_image}" 8')
                if port in ("c64", "c128"):
                    # This title-only fixture has no live dungeon/creatures.
                    # Initialize the attached disk through the production HAL;
                    # keep the short driver in documented idle map/scratch RAM.
                    driver = 0xC600 if port == "c64" else 0x1B00
                    original = memory(driver, 6)
                    routine = sym["hal_storage_init_selected_drive"]
                    code = bytes((0x20, routine & 255, routine >> 8,
                                  0x4C, (driver + 3) & 255, (driver + 3) >> 8))
                    cmd(f"> {sym['disk_prompt_device']:04x} 08")
                    cmd(f"> {driver:04x} " + code.hex(" "))
                    cmd("del")
                    cmd(f"break ${driver + 3:04x}")
                    response = cmd(f"g ${driver:04x}")
                    assert re.search(rf"(?:C:|PC:|PC=)\$?{driver + 3:04x}", response, re.I), response
                    cmd(f"> {driver:04x} " + original.hex(" "))
                    if port == "c64":
                        cmd("> 0001 35")  # Restore the legal viewer's RAM + I/O mapping.
                    cmd(f"r pc={sym['legal_menu_wait']:04x}")
                key("1")
                until("legal_page_wait")
                width = 80 if port == "c128" else 40
                screen = (memory(0, width * 25, "vdc") if port == "c128"
                          else memory(0x0C00 if port == "plus4" else 0x0400, width * 25))
                for row, expected in ((2, b"A" * (width - 2)), (3, b"B" * (width - 1)),
                                      (4, b"C" * (width - 1)), (5, b"C"),
                                      (6, b"TAIL"), (22, b"EDGE")):
                    assert screen[row * width + 1:row * width + 1 + len(expected)] == expected, (row, screen[row*width:(row+1)*width])
                has("End. R: restart")
                key("Q")
                until("legal_menu_wait")
                key("Q")
                until("title_menu_loop")
                if port == "c64":
                    assert memory(sym["zp_save_buf"], 142) == basic_snapshot
                print(f"PASS {port}: missing-file recovery, exact-width lines, split CRLF and page-boundary EOF", flush=True)
                return
            page()
            has("MORIA8 LICENSE NOTICE")
            if mode == "help":
                # Title coverage below owns restart/offer/EOF. Here exercise
                # Help's distinct reload/return path and game-state invariant.
                key("Q")
                until("legal_menu_wait")
                assert memory(sym["legal_opened"], 1) == b"\0"
                key("Q")
                key("Q")
                until("main_loop")
                after = state()
                assert after == before, [(i, a[:16].hex(), b[:16].hex())
                                         for i, (a, b) in enumerate(zip(before, after)) if a != b]
                if port == "c64":
                    assert memory(sym["zp_save_buf"], 142) == basic_snapshot
                print(f"PASS {port}: Help -> disk LICENSE -> Help -> play; player, turn, RNG, inventory and map preserved", flush=True)
                return
            key("R")
            page()
            has("MORIA8 LICENSE NOTICE")
            key("Q")
            until("legal_menu_wait")
            key("2")
            page()
            has("MORIA8 SOURCE OFFER")
            for _ in range(5):
                if memory(sym["legal_eof"], 1) == b"\x40":
                    break
                key(" ")
                page()
            else:
                raise AssertionError("Source offer did not reach EOF")
            key("Q")
            until("legal_menu_wait")
            assert memory(sym["legal_opened"], 1) == b"\0"
            key("Q")
            until("title_menu_loop")
            if port == "c64":
                assert memory(sym["zp_save_buf"], 142) == basic_snapshot, "BASIC snapshot staging was not restored"
            print(f"PASS {port} {mode}: dispatch -> disk LICENSE/source offer, restart, paging, close and return", flush=True)
        finally:
            timer.cancel()
            mon.close()
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)
            (output / "exit.txt").write_text(f"{proc.returncode}\n")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", choices=("c64", "c128", "plus4"))
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--disk-image", type=Path, required=True)
    parser.add_argument("--program", type=Path, help="C64 product PRG to inject")
    parser.add_argument("--vice", required=True)
    parser.add_argument("--c1541", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scenario", choices=("title", "help", "missing", "swap", "boot", "fault", "open-retry"))
    args = parser.parse_args(argv)
    if args.port == "c64" and args.program is None:
        parser.error("--program is required for c64")
    for name in ("symbols", "disk_image", "program"):
        path = getattr(args, name)
        if path is not None:
            path = path.resolve()
            if not path.is_file():
                parser.error(f"{name}: file not found: {path}")
            setattr(args, name, path)
    # VICE runs with cwd=ROOT; resolve relative tool paths in the caller's cwd.
    for name in ("vice", "c1541"):
        tool = shutil.which(getattr(args, name))
        if tool is None:
            parser.error(f"{name}: executable not found: {getattr(args, name)}")
        setattr(args, name, str(Path(tool).resolve()))
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=args.output))
    print(f"Evidence: {output}", flush=True)
    modes = [args.scenario] if args.scenario else ["title", "help", "missing", "swap", "fault", "open-retry"]
    if args.scenario is None and args.port == "c64":
        modes.append("boot")
    for mode in modes:
        run(args, output / mode, mode)


if __name__ == "__main__":
    main()

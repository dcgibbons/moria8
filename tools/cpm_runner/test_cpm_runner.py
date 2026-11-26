#!/usr/bin/env python3
"""Comprehensive self-test for tools/cpm_runner (and sjasmplus + RunCPM cross-check)."""

from __future__ import annotations

import json
import os
import pty
import select
import shutil
import subprocess
import sys
import termios
import time
from pathlib import Path

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def _resolve_tool(env_name: str, default_path: Path) -> Path:
    val = os.environ.get(env_name, "").strip()
    if not val:
        return default_path
    p = Path(val)
    if "/" in val or os.sep in val:
        return p.resolve()
    found = shutil.which(val)
    return Path(found) if found else p


SJASMPLUS = _resolve_tool("SJASMPLUS", ROOT / "tools" / "sjasmplus" / "sjasmplus")
RUNCPM = _resolve_tool("RUNCPM", ROOT / "tools" / "runcpm" / "RunCPM")
CPM_RUNNER = _resolve_tool("CPM_RUNNER", ROOT / "build" / "cpm" / "cpm_runner")
WORK_ROOT = ROOT / "build" / "cpm" / "selftest_work"


ASM_SUITE = r"""
    DEVICE NOSLOT64K
    ORG $0100

    ; Initialize stack from TPA top ($0006-$0007)
    LD HL, ($0006)
    LD A, H
    CP $D1              ; 52K TPA guard: require BDOS >= $D100 (BDOS_MIN_TOP)
    JR NC, tpa_ok
    LD C, 9
    LD DE, msg_low_tpa
    CALL 5
    LD C, 0
    CALL 5

tpa_ok:
    LD SP, HL
    ; Write stack canary below stack
    LD HL, stack_canary
    LD (HL), $CA
    INC HL
    LD (HL), $FE

    ; Print CLI tail length + bytes from $0080
    LD C, 9
    LD DE, msg_tail
    CALL 5
    LD A, ($0080)
    OR A
    JR Z, tail_done
    LD B, A
    LD HL, $0081
tail_loop:
    PUSH BC
    PUSH HL
    LD E, (HL)
    LD C, 2
    CALL 5
    POP HL
    POP BC
    INC HL
    DJNZ tail_loop
tail_done:
    LD C, 9
    LD DE, msg_crlf
    CALL 5

    ; Check BDOS 12 version == $22
    LD C, 12
    CALL 5
    CP $22
    JP NZ, fail_test

    ; Check BDOS 25 current drive == 0 (A:)
    LD C, 25
    CALL 5
    OR A
    JP NZ, fail_test

    ; Test BDOS 14 select drive B: (1) and back to A: (0)
    LD C, 14
    LD E, 1
    CALL 5
    OR A
    JP NZ, fail_test
    LD C, 25
    CALL 5
    CP 1
    JP NZ, fail_test
    ; Create B:TESTB.DAT on B:
    LD C, 22
    LD DE, fcb_b
    CALL 5
    INC A
    JP Z, fail_test
    XOR A
    LD (fcb_b + 32), A
    LD C, 26
    LD DE, dma_write_b
    CALL 5
    LD C, 21
    LD DE, fcb_b
    CALL 5
    OR A
    JP NZ, fail_test
    LD C, 16
    LD DE, fcb_b
    CALL 5
    INC A
    JP Z, fail_test
    ; Back to drive A:
    LD C, 14
    LD E, 0
    CALL 5
    OR A
    JP NZ, fail_test

    ; Test file ops on A: F_MAKE, F_WRITE (2 seq recs), F_RANDREC, F_CLOSE, F_OPEN, F_SIZE, F_READ, F_WRITERAND, F_READRAND
    LD C, 22
    LD DE, fcb_a
    CALL 5
    INC A
    JP Z, fail_test
    XOR A
    LD (fcb_a + 32), A

    LD C, 26
    LD DE, dma_rec0
    CALL 5
    LD C, 21
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test

    LD C, 26
    LD DE, dma_rec1
    CALL 5
    LD C, 21
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test

    ; Test F_RANDREC (36) -> should compute r0 = 2, r1 = 0, r2 = 0
    LD C, 36
    LD DE, fcb_a
    CALL 5
    LD A, (fcb_a + 33)
    CP 2
    JP NZ, fail_test

    LD C, 16
    LD DE, fcb_a
    CALL 5
    INC A
    JP Z, fail_test

    ; F_OPEN and F_SIZE (35)
    XOR A
    LD (fcb_a + 12), A
    LD (fcb_a + 32), A
    LD C, 15
    LD DE, fcb_a
    CALL 5
    INC A
    JP Z, fail_test

    LD C, 35
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test
    LD A, (fcb_a + 33)
    CP 2
    JP NZ, fail_test

    ; Sequential read rec 0 into dma_buf
    LD C, 26
    LD DE, dma_buf
    CALL 5
    LD C, 20
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test
    LD A, (dma_buf)
    CP 'R'
    JP NZ, fail_test
    LD A, (dma_buf + 3)
    CP '0'
    JP NZ, fail_test

    ; Random write record #5 (r0=5, r1=0, r2=0)
    LD A, 5
    LD (fcb_a + 33), A
    XOR A
    LD (fcb_a + 34), A
    LD (fcb_a + 35), A
    LD C, 26
    LD DE, dma_rec5
    CALL 5
    LD C, 34
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test

    ; Random read record #5 into dma_buf
    LD C, 26
    LD DE, dma_buf
    CALL 5
    LD C, 33
    LD DE, fcb_a
    CALL 5
    OR A
    JP NZ, fail_test
    LD A, (dma_buf + 3)
    CP '5'
    JP NZ, fail_test

    ; Random read unwritten record #7 (past EOF 6 records, inside extent 0) -> A == 1
    LD A, 7
    LD (fcb_a + 33), A
    LD C, 33
    LD DE, fcb_a
    CALL 5
    CP 1
    JP NZ, fail_test

    ; Random read unwritten extent record #200 -> nonzero (A == 4 on CP/M 2.2 / cpm_runner; A == 1 on RunCPM)
    LD A, 200
    LD (fcb_a + 33), A
    LD C, 33
    LD DE, fcb_a
    CALL 5
    OR A
    JP Z, fail_test

    ; Close TESTA.DAT cleanly before rename/delete
    LD C, 16
    LD DE, fcb_a
    CALL 5
    INC A
    JP Z, fail_test

    ; Search first / search next (BDOS 17 / 18) on A:*.DAT
    LD C, 26
    LD DE, dma_buf
    CALL 5
    LD C, 17
    LD DE, fcb_wild
    CALL 5
    INC A
    JP Z, fail_test
    ; Next search should return FF since only TESTA.DAT matches *.DAT on A:
    LD C, 18
    LD DE, fcb_wild
    CALL 5
    CP $FF
    JP NZ, fail_test

    ; Rename TESTA.DAT -> RENAMED.DAT (BDOS 23)
    LD C, 23
    LD DE, fcb_rename
    CALL 5
    OR A
    JP NZ, fail_test

    ; Delete RENAMED.DAT (BDOS 19)
    LD C, 19
    LD DE, fcb_renamed
    CALL 5
    OR A
    JP NZ, fail_test

    ; Copy injected RNG seed at $2000 into shadow_seed at $2010
    LD HL, ($2000)
    LD ($2010), HL
    LD HL, ($2002)
    LD ($2012), HL

    ; Write ANSI screen text + color (row 3, col 10, green)
    LD C, 9
    LD DE, msg_ansi
    CALL 5

    ; Also update shadow RAM at $2100 for RAM inspection test
    LD HL, shadow_src
    LD DE, $2100
    LD BC, 6
    LDIR

    ; Flush any typeahead once (tests idle_polls=512 resilience!), then draw marker
    LD C, 6
    LD E, $FF
    CALL 5
    LD C, 6
    LD E, '!'
    CALL 5

    ; Wait for keys via BDOS 6 E=$FF loop until 'Q' is received; store keys at $2200
    LD HL, $2200
    LD B, 0
key_loop:
    PUSH HL
    PUSH BC
wait_poll:
    LD C, 6
    LD E, $FF
    CALL 5
    OR A
    JR Z, wait_poll
    POP BC
    POP HL
    LD (HL), A
    INC HL
    INC B
    CP 'Q'
    JR NZ, key_loop
    LD A, B
    LD ($21FF), A

    ; Test BDOS 10 buffered line input (with backspace editing: "AB\x08BC\r" -> len 3 "ABC")
    LD C, 10
    LD DE, line_buf
    CALL 5
    LD A, (line_buf + 1)
    CP 3
    JP NZ, fail_test
    LD A, (line_buf + 2)
    CP 'A'
    JP NZ, fail_test
    LD A, (line_buf + 3)
    CP 'B'
    JP NZ, fail_test
    LD A, (line_buf + 4)
    CP 'C'
    JP NZ, fail_test

    ; Test BDOS 1 (echoes 'Z')
    LD C, 1
    CALL 5
    CP 'Z'
    JP NZ, fail_test

    ; Test BDOS 20 sequential read EOF (A == 1) on empty file EMPTY.DAT
    LD C, 22
    LD DE, fcb_empty
    CALL 5
    INC A
    JP Z, fail_test
    XOR A
    LD (fcb_empty + 32), A
    LD C, 20
    LD DE, fcb_empty
    CALL 5
    CP 1
    JP NZ, fail_test
    LD C, 16
    LD DE, fcb_empty
    CALL 5

    ; Test opening LOWER.TXT (case-insensitive on cpm_runner, uppercase on RunCPM)
    LD C, 15
    LD DE, fcb_lower
    CALL 5
    INC A
    JP Z, fail_test
    XOR A
    LD (fcb_lower + 32), A
    LD C, 26
    LD DE, dma_buf
    CALL 5
    LD C, 20
    LD DE, fcb_lower
    CALL 5
    OR A
    JP NZ, fail_test
    LD A, (dma_buf)
    CP 'l'
    JP NZ, fail_test
    LD C, 16
    LD DE, fcb_lower
    CALL 5

    LD C, 9
    LD DE, msg_pass
    CALL 5
    LD C, 0
    CALL 5

fail_test:
    LD C, 9
    LD DE, msg_fail
    CALL 5
    HALT

msg_low_tpa: DB "TPA LOW", 13, 10, "$"
msg_tail:    DB "TAIL:", "$"
msg_crlf:    DB 13, 10, "$"
msg_ansi:    DB 27, "[2J", 27, "[3;10H", 27, "[32mGREEN!", 27, "[0m$"
msg_pass:    DB 13, 10, "ALL PASS", 13, 10, "$"
msg_fail:    DB 13, 10, "FAIL", 13, 10, "$"
shadow_src:  DB "MORIA8"

fcb_a:
    DB 0, "TESTA   ", "DAT"
    DS 24, 0
fcb_b:
    DB 0, "TESTB   ", "DAT"
    DS 24, 0
fcb_wild:
    DB 0, "????????", "DAT"
    DS 24, 0
fcb_rename:
    DB 0, "TESTA   ", "DAT", 0, 0, 0, 0
    DB 0, "RENAMED ", "DAT"
    DS 8, 0
fcb_renamed:
    DB 0, "RENAMED ", "DAT"
    DS 24, 0
fcb_empty:
    DB 0, "EMPTY   ", "DAT"
    DS 24, 0
fcb_lower:
    DB 0, "LOWER   ", "TXT"
    DS 24, 0

dma_rec0:    DB "REC0"
             DS 124, 'A'
dma_rec1:    DB "REC1"
             DS 124, 'B'
dma_rec5:    DB "REC5"
             DS 124, 'C'
dma_write_b: DB "DRV_B_OK"
             DS 120, ' '
dma_buf:     DS 128, 0

line_buf:    DB 16, 0
             DS 16, 0

    ORG $2300
stack_canary:
    DW 0

    SAVEBIN "__COM_OUT__", $0100, $2302 - $0100
"""

ASM_RET_EXIT = r"""
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 9
    LD DE, msg
    CALL 5
    RET
msg:
    DB "RET EXIT OK", 13, 10, "$"
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""

ASM_HALT = r"""
    DEVICE NOSLOT64K
    ORG $0100
    HALT
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""


class ControlClient:
    def __init__(self, args: list[str]) -> None:
        self.proc = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert self.proc.stdin is not None
        assert self.proc.stdout is not None

    def call(self, obj: dict) -> dict:
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            stderr = self.proc.stderr.read() if self.proc.stderr else ""
            raise RuntimeError(f"cpm_runner closed stdout unexpectedly; stderr={stderr!r}")
        resp = json.loads(line)
        if not resp.get("ok"):
            raise AssertionError(f"command {obj} failed: {resp}")
        return resp

    def close(self) -> int:
        try:
            self.call({"cmd": "quit"})
        except Exception:
            pass
        rc = self.proc.wait(timeout=5)
        stderr = self.proc.stderr.read() if self.proc.stderr else ""
        if stderr:
            raise AssertionError(f"unexpected stderr in control mode: {stderr!r}")
        return rc


def assemble(asm_src: str, asm_path: Path, com_path: Path) -> None:
    asm_path.write_text(asm_src.replace("__COM_OUT__", str(com_path)), encoding="utf-8")
    subprocess.run([str(SJASMPLUS), str(asm_path)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_bdos6_raw_output_and_bdos9_fault(work: Path) -> None:
    # 1. Verify BDOS 6 E=0xFE and E=0xFD emit raw bytes 0xFE/0xFD (strict CP/M 2.2)
    src_raw6 = """
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 6
    LD E, $FE
    CALL 5
    LD C, 6
    LD E, $FD
    CALL 5
    LD C, 6
    LD E, 'Z'
    CALL 5
    LD C, 0
    CALL 5
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    raw6_com = work / "RAW6.COM"
    assemble(src_raw6, work / "raw6.asm", raw6_com)
    cli = ControlClient([str(CPM_RUNNER), "--control", str(raw6_com)])
    try:
        res = cli.call({"cmd": "run", "max_steps": 10000})
        assert res["reason"] == "exited" and res["exit_code"] == 0
        out = cli.call({"cmd": "console_out"})
        assert out["hex"] == "fefd5a", f"expected raw FE FD 5A, got {out['hex']}"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()

    # 2. Verify BDOS 9 bounded to 65536 bytes -> CPM_FAULT when '$' missing
    src_b9 = """
    DEVICE NOSLOT64K
    ORG $0100
    LD HL, $0200
    LD DE, $0201
    LD BC, $8000
    LD (HL), 'X'
    LDIR
    LD C, 9
    LD DE, $0200
    CALL 5
    LD C, 0
    CALL 5
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    b9_com = work / "B9FAULT.COM"
    assemble(src_b9, work / "b9fault.asm", b9_com)
    cli = ControlClient([str(CPM_RUNNER), "--control", str(b9_com)])
    try:
        res = cli.call({"cmd": "run", "max_steps": 1000000})
        assert res["reason"] == "fault" and res["exit_code"] == 1
        assert res["exit_reason"] == "bdos_9_unterminated"
        # Resuming after fault must not run further
        res2 = cli.call({"cmd": "run", "max_steps": 100})
        assert res2["steps_run"] == 0 and res2["reason"] == "fault"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()


def test_bdos_hazards_clobber_and_stack_probe(work: Path) -> None:
    # Verify IX/IY/DE/C/F clobbering, stack poison [SP-32..SP-1]=0xCC, and --no-strict-bdos
    src_clobber = """
    DEVICE NOSLOT64K
    ORG $0100
    LD SP, $8C10
    LD HL, $CAFE
    LD ($8C00), HL
    LD IX, $1122
    LD IY, $3344
    LD DE, $5566
    LD C, 12
    CALL 5
    LD ($2000), IX
    LD ($2002), IY
    LD ($2004), DE
    LD ($2006), BC
    LD C, 0
    CALL 5
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    clob_com = work / "CLOBBER.COM"
    assemble(src_clobber, work / "clobber.asm", clob_com)

    # Strict mode (default): IX/IY/DE/C poisoned, [SP-32..SP-1] poisoned with 0xCC (smashing $8C00)
    cli = ControlClient([str(CPM_RUNNER), "--control", str(clob_com)])
    try:
        res = cli.call({"cmd": "run", "max_steps": 10000})
        assert res["reason"] == "exited" and res["exit_code"] == 0
        mem = bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x2000, "len": 8})["hex"])
        assert mem[0:2] == b"\xEF\xBE", f"expected poisoned IX=0xBEEF, got {mem[0:2].hex()}"
        assert mem[2:4] == b"\xFE\xCA", f"expected poisoned IY=0xCAFE, got {mem[2:4].hex()}"
        assert mem[4:6] == b"\xAD\xDE", f"expected poisoned DE=0xDEAD, got {mem[4:6].hex()}"
        assert mem[6] == 0xFF, f"expected poisoned C=0xFF, got {mem[6]:02x}"
        # Stack canary at $8C00..$8C0D (below $8C10-2=$8C0E after CALL 5) was poisoned with 0xCC
        canary = bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x8C00, "len": 4})["hex"])
        assert canary == b"\xCC\xCC\xCC\xCC", f"expected 0xCC stack poison at $8C00, got {canary.hex()}"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()

    # --no-strict-bdos: IX/IY preserved and stack canary untouched
    cli = ControlClient([str(CPM_RUNNER), "--control", "--no-strict-bdos", str(clob_com)])
    try:
        res = cli.call({"cmd": "run", "max_steps": 10000})
        assert res["reason"] == "exited"
        mem = bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x2000, "len": 4})["hex"])
        assert mem[0:2] == b"\x22\x11" and mem[2:4] == b"\x44\x33"
        canary = bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x8C00, "len": 2})["hex"])
        assert canary == b"\xFE\xCA"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()

    # Stack underflow fault when SP < 0x0128
    src_under = """
    DEVICE NOSLOT64K
    ORG $0100
    LD SP, $0120
    LD C, 12
    CALL 5
    HALT
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    under_com = work / "UNDER.COM"
    assemble(src_under, work / "under.asm", under_com)
    cli = ControlClient([str(CPM_RUNNER), "--control", str(under_com)])
    try:
        res = cli.call({"cmd": "run", "max_steps": 1000})
        assert res["reason"] == "fault" and res["exit_code"] == 1
        assert res["exit_reason"] == "bdos_stack_underflow"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()


def test_strict_fcb_and_readstr_and_idle512(work: Path) -> None:
    fcb_dir = work / "fcb_dir"
    fcb_dir.mkdir(parents=True)
    (fcb_dir / "EXISTS.DAT").write_bytes(b"HELLO" + b"\x00" * 123)
    (fcb_dir / "TARGET.DAT").write_bytes(b"TARGET" + b"\x00" * 122)

    src_fcb = """
    DEVICE NOSLOT64K
    ORG $0100

    ; 1. Empty basename FCB ("        TXT") must be rejected
    LD C, 15
    LD DE, fcb_empty_base
    CALL 5
    CP $FF
    JP NZ, bad

    ; 2. F_MAKE on existing file EXISTS.DAT must fail (A == $FF)
    LD C, 22
    LD DE, fcb_exists
    CALL 5
    CP $FF
    JP NZ, bad

    ; 3. F_RENAME to already-existing TARGET.DAT must fail (A == $FF)
    LD C, 23
    LD DE, fcb_ren_exist
    CALL 5
    CP $FF
    JP NZ, bad

    ; 4. READSEQ / READRAND before OPEN must fail (A == $FF)
    LD C, 20
    LD DE, fcb_exists
    CALL 5
    CP $FF
    JP NZ, bad
    LD C, 33
    LD DE, fcb_exists
    CALL 5
    CP $FF
    JP NZ, bad

    ; 5. OPEN EXISTS.DAT -> copy 36 bytes to fcb_copy -> READSEQ on copy without OPEN must fail!
    LD C, 15
    LD DE, fcb_exists
    CALL 5
    INC A
    JP Z, bad
    LD HL, fcb_exists
    LD DE, fcb_copy
    LD BC, 36
    LDIR
    LD C, 20
    LD DE, fcb_copy
    CALL 5
    CP $FF
    JP NZ, bad

    ; 6. CLOSE fcb_exists clears open mark -> READSEQ on fcb_exists must now fail!
    LD C, 16
    LD DE, fcb_exists
    CALL 5
    INC A
    JP Z, bad
    LD C, 20
    LD DE, fcb_exists
    CALL 5
    CP $FF
    JP NZ, bad

    ; 7. F_MAKE new file leaves FCB+32 (CR) dirty/untouched
    LD A, $55
    LD (fcb_new + 32), A
    LD C, 22
    LD DE, fcb_new
    CALL 5
    INC A
    JP Z, bad
    LD A, (fcb_new + 32)
    CP $55
    JP NZ, bad
    LD C, 16
    LD DE, fcb_new
    CALL 5

    ; 7b. Exact CP/M 2.2 F_READRAND unwritten extent error code (A == 4) on EXISTS.DAT rec 200
    LD C, 15
    LD DE, fcb_exists
    CALL 5
    INC A
    JP Z, bad
    LD A, 200
    LD (fcb_exists + 33), A
    XOR A
    LD (fcb_exists + 34), A
    LD (fcb_exists + 35), A
    LD C, 33
    LD DE, fcb_exists
    CALL 5
    CP 4
    JP NZ, bad
    LD C, 16
    LD DE, fcb_exists
    CALL 5

    ; 8. BDOS 10 C_READSTR max=3 discards extra chars until Enter
    LD C, 10
    LD DE, readstr_buf
    CALL 5
    LD A, (readstr_buf + 1)
    CP 3
    JP NZ, bad

    ; 8b. BDOS 11 C_STAT returns 0 when queue empty
    LD C, 11
    CALL 5
    OR A
    JP NZ, bad

    ; 9. 255-poll loop (ESC_CSI_POLL_ITERS=255) must NOT trigger run_idle default threshold (512)!
    LD B, 255
poll255:
    PUSH BC
    LD C, 6
    LD E, $FF
    CALL 5
    POP BC
    DJNZ poll255
    LD C, 6
    LD E, 'K'
    CALL 5

    ; Search first before reset test
    LD C, 26
    LD DE, dma_tmp
    CALL 5
    LD C, 17
    LD DE, fcb_wild_all
    CALL 5
    INC A
    JP Z, bad

    ; Final idle poll loop
final_idle:
    LD C, 6
    LD E, $FF
    CALL 5
    OR A
    JR Z, final_idle

    ; If resumed with 'N', check BDOS 18 (search next) after reset test (expects $FF if reset cleared search!)
    LD C, 18
    LD DE, fcb_wild_all
    CALL 5
    LD ($2000), A

    LD C, 9
    LD DE, ok_msg
    CALL 5
    LD C, 0
    CALL 5

bad:
    HALT

ok_msg: DB "STRICT-OK$"
fcb_empty_base:
    DB 0, "        ", "TXT"
    DS 24, 0
fcb_exists:
    DB 0, "EXISTS  ", "DAT"
    DS 24, 0
fcb_ren_exist:
    DB 0, "EXISTS  ", "DAT", 0, 0, 0, 0
    DB 0, "TARGET  ", "DAT"
    DS 8, 0
fcb_copy:
    DS 36, 0
fcb_new:
    DB 0, "NEWFILE ", "DAT"
    DS 24, 0
fcb_wild_all:
    DB 0, "????????", "DAT"
    DS 24, 0
readstr_buf:
    DB 3, 0
    DS 8, 0
dma_tmp:
    DS 128, 0

    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    fcb_com = work / "STRICT.COM"
    assemble(src_fcb, work / "strict.asm", fcb_com)

    cli = ControlClient([
        str(CPM_RUNNER), "--control",
        "--workdir", str(fcb_dir),
        str(fcb_com),
    ])
    try:
        # Send "ABCXYZ\r" for BDOS 10 (max=3): should wait for \r and discard XYZ
        cli.call({"cmd": "send_keys", "text": "ABCXYZ\r"})
        # Default run_idle (idle_polls=512) must run past the 255-poll loop and see 'K'
        res = cli.call({"cmd": "run_idle", "max_steps": 1000000})
        assert res["reason"] == "idle", f"expected idle after 255-poll loop, got {res}"
        out = cli.call({"cmd": "console_out"})["text"]
        assert "K" in out, f"run_idle stopped prematurely during 255-poll loop! out={out!r}"
        # Check BDOS 10 stored "ABC" (len 3) and didn't leave "XYZ\r" in input FIFO
        assert cli.call({"cmd": "info"})["input_queue_len"] == 0

        # Finish program cleanly
        cli.call({"cmd": "send_keys", "text": "N"})
        fin = cli.call({"cmd": "run", "max_steps": 100000})
        assert fin["reason"] == "exited" and "STRICT-OK" in cli.call({"cmd": "console_out"})["text"]

        # Verify reset frees/zeros search_matches: start a fresh run and call reset mid-way
        cli.call({"cmd": "reset"})
        # Write tiny F_SNEXT-only snippet in RAM via write_mem to verify F_SNEXT returns 0xFF after reset
        snext_only = bytes([
            0x0E, 0x12,       # LD C, 18 (F_SNEXT)
            0xCD, 0x05, 0x00, # CALL 5
            0x32, 0x00, 0x20, # LD ($2000), A
            0x0E, 0x00,       # LD C, 0
            0xCD, 0x05, 0x00, # CALL 5
        ])
        cli.call({"cmd": "write_mem", "addr": 0x0100, "bytes": list(snext_only)})
        r_sn = cli.call({"cmd": "run", "max_steps": 1000})
        assert r_sn["reason"] == "exited"
        assert cli.call({"cmd": "read_mem", "addr": 0x2000, "len": 1, "format": "bytes"})["bytes"] == [0xFF]

        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()


def test_ldir_lddr_r_and_steps(work: Path) -> None:
    src_blk = """
    DEVICE NOSLOT64K
    ORG $0100
    LD HL, $2000
    LD DE, $2100
    LD BC, 4
    LDIR
    LD HL, $2003
    LD DE, $2203
    LD BC, 5
    LDDR
    LD C, 0
    CALL 5
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    blk_com = work / "BLK.COM"
    assemble(src_blk, work / "blk.asm", blk_com)
    cli = ControlClient([str(CPM_RUNNER), "--control", str(blk_com)])
    try:
        # Step over 3 LD instructions to reach LDIR
        s0 = cli.call({"cmd": "step", "count": 3})
        r0 = s0["r"]
        s1 = cli.call({"cmd": "step", "count": 1})  # LDIR BC=4
        assert s1["steps_run"] == 4, f"expected LDIR steps_run=4, got {s1}"
        assert ((s1["r"] - r0) & 0x7F) == 8, f"expected LDIR dR=8, got {(s1['r'] - r0) & 0x7F}"

        # Step over 3 LD instructions to reach LDDR
        s2 = cli.call({"cmd": "step", "count": 3})
        r2 = s2["r"]
        s3 = cli.call({"cmd": "step", "count": 1})  # LDDR BC=5
        assert s3["steps_run"] == 5, f"expected LDDR steps_run=5, got {s3}"
        assert ((s3["r"] - r2) & 0x7F) == 10, f"expected LDDR dR=10, got {(s3['r'] - r2) & 0x7F}"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()


def test_bios_seldsk_and_bdos14_select_err(work: Path) -> None:
    rcpm_root = work / "runcpm_seldsk"
    (rcpm_root / "A" / "0").mkdir(parents=True)

    probe_src = """
    DEVICE NOSLOT64K
    ORG 0x0100
    LD C, 0
    LD DE, 0
    CALL call_seldsk
    LD (0x2000), HL
    LD C, 1
    LD DE, 0
    CALL call_seldsk
    LD (0x2002), HL
    LD C, 16
    LD DE, 0
    CALL call_seldsk
    LD (0x2004), HL
    LD C, 0
    LD DE, 1
    CALL call_seldsk
    LD (0x2006), HL
    LD C, 0
    CALL 5
call_seldsk:
    LD HL, (0x0001)
    LD A, L
    ADD A, 24
    LD L, A
    JR NC, nc
    INC H
nc:
    JP (HL)
    SAVEBIN "__COM_OUT__", 0x0100, $ - 0x0100
"""
    probe_com = work / "PROBE.COM"
    assemble(probe_src, work / "probe.asm", probe_com)
    cli = ControlClient([
        str(CPM_RUNNER), "--control", "--workdir", str(rcpm_root), str(probe_com),
    ])
    try:
        fin = cli.call({"cmd": "run", "max_steps": 10000})
        assert fin["reason"] == "exited" and fin["exit_code"] == 0, fin
        mem = cli.call({"cmd": "read_mem", "addr": 0x2000, "len": 8, "format": "bytes"})["bytes"]
        dph_a0 = mem[0] | (mem[1] << 8)
        dph_b0 = mem[2] | (mem[3] << 8)
        dph_bad = mem[4] | (mem[5] << 8)
        dph_a1 = mem[6] | (mem[7] << 8)
        assert dph_a0 != 0 and dph_a1 != 0, f"mounted A: SELDSK failed: {mem}"
        assert dph_b0 == 0 and dph_bad == 0, f"unmounted SELDSK should return 0: {mem}"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()

    selerr_src = """
    DEVICE NOSLOT64K
    ORG 0x0100
    LD C, 14
    LD E, 1
    CALL 5
    LD (0x2000), HL
    LD C, 0
    CALL 5
    SAVEBIN "__COM_OUT__", 0x0100, $ - 0x0100
"""
    selerr_com = work / "SELERR.COM"
    assemble(selerr_src, work / "selerr.asm", selerr_com)

    strict_res = subprocess.run(
        [str(CPM_RUNNER), "--workdir", str(rcpm_root), "--summary-json", str(selerr_com)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
    )
    assert strict_res.returncode != 0
    assert b"Bdos Err on B: Select" in strict_res.stdout
    summary = json.loads(strict_res.stderr.decode("utf-8").strip())
    assert summary["status"] == "exited" and summary["exit_reason"] == "bdos_select_err"

    cli_ns = ControlClient([
        str(CPM_RUNNER), "--control", "--no-strict-bdos", "--workdir", str(rcpm_root), str(selerr_com),
    ])
    try:
        fin_ns = cli_ns.call({"cmd": "run", "max_steps": 10000})
        assert fin_ns["reason"] == "exited" and fin_ns["exit_code"] == 0
        ret_ns = cli_ns.call({"cmd": "read_mem", "addr": 0x2000, "len": 2, "format": "bytes"})["bytes"]
        assert ret_ns == [0xFF, 0x01], f"expected 0x01FF in --no-strict-bdos, got {ret_ns}"
        assert cli_ns.close() == 0
    finally:
        if cli_ns.proc.poll() is None:
            cli_ns.proc.kill()


def test_pty_interactive_tty_and_csi(work: Path) -> None:
    """Interactive PTY mode sets raw non-canonical/no-echo termios, runs unlimited steps past >1.2s,
    delivers raw single keys & multi-byte CSI sequences without Enter, and restores termios on exit."""
    asm_src = r"""
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 9
    LD DE, msg_rdy
    CALL 5
wait_x:
    LD C, 6
    LD E, $FF
    CALL 5
    OR A
    JR Z, wait_x
    CP 'x'
    JR NZ, wait_x
    LD C, 9
    LD DE, msg_x
    CALL 5
    LD HL, buf
    LD B, 3
wait_csi:
    PUSH BC
    PUSH HL
    LD C, 6
    LD E, $FF
    CALL 5
    POP HL
    POP BC
    OR A
    JR Z, wait_csi
    LD (HL), A
    INC HL
    DJNZ wait_csi
    LD HL, buf
    LD A, (HL)
    CP $1B
    JR NZ, fail
    INC HL
    LD A, (HL)
    CP '['
    JR NZ, fail
    INC HL
    LD A, (HL)
    CP 'A'
    JR NZ, fail
    LD C, 9
    LD DE, msg_ok
    CALL 5
    LD C, 0
    CALL 5
fail:
    HALT
msg_rdy: DB "RDY$"
msg_x:   DB "X!$"
msg_ok:  DB "CSI-OK$"
buf:     DS 4, 0
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    pty_work = work / "pty_tty"
    pty_work.mkdir(parents=True, exist_ok=True)
    com_path = pty_work / "PTY.COM"
    assemble(asm_src, pty_work / "pty.asm", com_path)

    master_fd, slave_fd = pty.openpty()
    try:
        orig_attrs = termios.tcgetattr(slave_fd)
        proc = subprocess.Popen(
            [str(CPM_RUNNER), "--workdir", str(pty_work), str(com_path)],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            start_new_session=True,
            close_fds=True,
        )
        os.close(slave_fd)
        slave_fd = -1
        out = b""

        def read_until(marker: bytes, timeout: float) -> bytes:
            nonlocal out
            deadline = time.monotonic() + timeout
            while marker not in out and time.monotonic() < deadline:
                r, _, _ = select.select([master_fd], [], [], 0.05)
                if r:
                    try:
                        chunk = os.read(master_fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    out += chunk
            return out

        assert b"RDY" in read_until(b"RDY", 5.0), f"missing RDY banner: {out!r}"
        # Stay idle > 1.3s to prove default interactive TTY mode runs with unlimited steps (no 100M step_limit Error 2)
        time.sleep(1.3)
        assert proc.poll() is None, f"interactive PTY exited early rc={proc.returncode} out={out!r}"

        live_attrs = termios.tcgetattr(master_fd)
        assert (live_attrs[3] & (termios.ICANON | termios.ECHO)) == 0, (
            f"expected ~ICANON & ~ECHO on live PTY, got lflag=0x{live_attrs[3]:x}"
        )

        # Single raw byte (no Enter), no lowercase 'x' echo from TTY
        os.write(master_fd, b"x")
        assert b"X!" in read_until(b"X!", 5.0), f"missing X! after single raw key: {out!r}"
        assert b"x" not in out, f"unexpected echoed 'x' in PTY output: {out!r}"

        # 3-byte CSI arrow sequence delivered intact
        os.write(master_fd, b"\x1b[A")
        assert b"CSI-OK" in read_until(b"CSI-OK", 5.0), f"missing CSI-OK after ESC[A: {out!r}"

        rc = proc.wait(timeout=5.0)
        assert rc == 0, f"expected clean BDOS 0 exit, got rc={rc} out={out!r}"
        restored = termios.tcgetattr(master_fd)
        assert (restored[3] & (termios.ICANON | termios.ECHO)) == (orig_attrs[3] & (termios.ICANON | termios.ECHO)), (
            f"termios not restored: before=0x{orig_attrs[3]:x} after=0x{restored[3]:x}"
        )
    finally:
        if slave_fd >= 0:
            os.close(slave_fd)
        os.close(master_fd)


def test_adm3a_screen_parser(work: Path) -> None:
    """Verify cpm_runner virtual screen handles ADM-3A 0x1A clear, 0x1E home, and ESC = row col."""
    asm_src = r"""
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 9
    LD DE, msg1
    CALL 5
wait_k:
    LD C, 6
    LD E, $FF
    CALL 5
    OR A
    JR Z, wait_k
    LD C, 9
    LD DE, msg2
    CALL 5
    LD C, 0
    CALL 5
msg1:
    DB $1B, "=", $20 + 5, $20 + 10, "OLD$"
msg2:
    DB $1A, $1B, "=", $20 + 2, $20 + 5, "ADM", $1E, "TOP", $1B, "=", $20 + 23, $20 + 77, "END$"
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    adm_com = work / "ADM3A.COM"
    adm_work = work / "adm3a_work"
    adm_work.mkdir(parents=True, exist_ok=True)
    assemble(asm_src, work / "adm3a.asm", adm_com)

    cli = ControlClient([str(CPM_RUNNER), "--control", "--workdir", str(adm_work), str(adm_com)])
    try:
        idle = cli.call({"cmd": "run_idle", "max_steps": 100000})
        assert idle["reason"] == "idle", f"expected idle after msg1, got {idle}"
        scr1 = cli.call({"cmd": "screen"})
        assert scr1["lines"][5][10:13] == "OLD", f"unexpected row 5 after ESC=: {scr1['lines'][5]!r}"

        cli.call({"cmd": "send_keys", "text": " "})
        fin = cli.call({"cmd": "run_idle", "max_steps": 100000})
        assert fin["reason"] == "exited" and fin["exit_code"] == 0, f"expected clean exit, got {fin}"
        scr2 = cli.call({"cmd": "screen"})
        assert scr2["lines"][5][10:13] == "   ", f"0x1A did not clear OLD: {scr2['lines'][5]!r}"
        assert scr2["lines"][2][5:8] == "ADM", f"unexpected row 2 after ESC=: {scr2['lines'][2]!r}"
        assert scr2["lines"][0][0:3] == "TOP", f"0x1E home failed on row 0: {scr2['lines'][0]!r}"
        assert scr2["lines"][23][77:80] == "END", f"unexpected row 23 after ESC=: {scr2['lines'][23]!r}"
        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()


def main() -> int:
    if WORK_ROOT.exists():
        shutil.rmtree(WORK_ROOT)
    drive_a = WORK_ROOT / "driveA"
    drive_b = WORK_ROOT / "driveB"
    runcpm_dir = WORK_ROOT / "runcpm_dir"
    (runcpm_dir / "A" / "0").mkdir(parents=True)
    (runcpm_dir / "B" / "0").mkdir(parents=True)
    drive_a.mkdir(parents=True)
    drive_b.mkdir(parents=True)
    (drive_a / "lower.txt").write_bytes(b"low\r\n")
    (runcpm_dir / "A" / "0" / "LOWER.TXT").write_bytes(b"low\r\n")

    suite_com = WORK_ROOT / "SUITE.COM"
    runcpm_suite_com = runcpm_dir / "A" / "0" / "SUITE.COM"
    ret_com = WORK_ROOT / "RET.COM"
    halt_com = WORK_ROOT / "HALT.COM"
    hello_com = runcpm_dir / "A" / "0" / "HELLO.COM"

    assemble(ASM_SUITE, WORK_ROOT / "suite.asm", suite_com)
    shutil.copy2(suite_com, runcpm_suite_com)
    assemble(ASM_RET_EXIT, WORK_ROOT / "ret.asm", ret_com)
    assemble(ASM_HALT, WORK_ROOT / "halt.asm", halt_com)

    hello_src = """
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 9
    LD DE, msg
    CALL 5
    LD C, 0
    CALL 5
msg:
    DB "HELLO-DUAL-OK", 13, 10, "$"
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
    assemble(hello_src, WORK_ROOT / "hello.asm", hello_com)

    # 1. Cross-verify HELLO.COM and SUITE.COM (seq & random file I/O) on real RunCPM AND cpm_runner
    runcpm_hello = subprocess.run(
        [str(RUNCPM)],
        cwd=str(runcpm_dir),
        input=b"HELLO\rEXIT\r",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    )
    assert b"HELLO-DUAL-OK" in runcpm_hello.stdout, f"RunCPM missing HELLO output: {runcpm_hello.stdout!r}"

    runcpm_suite = subprocess.run(
        [str(RUNCPM)],
        cwd=str(runcpm_dir),
        input=b"SUITE SEED42\r\x1b[AQAB\x08BC\rZEXIT\r",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    )
    assert b"TAIL: SEED42" in runcpm_suite.stdout, f"RunCPM SUITE missing tail: {runcpm_suite.stdout!r}"
    assert b"ALL PASS" in runcpm_suite.stdout, f"RunCPM SUITE failed: {runcpm_suite.stdout!r}"
    rc_b = (runcpm_dir / "B" / "0" / "TESTB.DAT").read_bytes()
    assert rc_b.startswith(b"DRV_B_OK") and len(rc_b) == 128

    cpm_hello = subprocess.run(
        [str(CPM_RUNNER), str(hello_com)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    )
    assert b"HELLO-DUAL-OK" in cpm_hello.stdout

    # 2. Verify RET-to-$0000 exit and HALT exit code
    ret_res = subprocess.run([str(CPM_RUNNER), str(ret_com)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert ret_res.returncode == 0 and b"RET EXIT OK" in ret_res.stdout

    halt_res = subprocess.run([str(CPM_RUNNER), str(halt_com)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert halt_res.returncode == 1

    # 3. Verify --tpa-top bounds [0x0200, 0xFE00] and 52K TPA guard (BDOS_MIN_TOP = 0xD100)
    for bad_top in ("0x01FF", "0xFE01", "0xFF80"):
        bad_res = subprocess.run(
            [str(CPM_RUNNER), "--tpa-top", bad_top, str(hello_com)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
        )
        assert bad_res.returncode == 2, f"expected exit 2 for --tpa-top {bad_top}, got {bad_res.returncode}"

    for low_top in ("0xC000", "0xD0FF"):
        low_tpa = subprocess.run(
            [str(CPM_RUNNER), "--tpa-top", low_top, "--summary-json", str(suite_com)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert low_tpa.returncode == 0
        assert b"TPA LOW" in low_tpa.stdout
        summary = json.loads(low_tpa.stderr.decode("utf-8").strip())
        assert summary["status"] == "exited" and summary["exit_reason"] == "bdos_0"

    # 4. Full scripted JSON-lines control mode verification on SUITE.COM (starting at exact 0xD100)
    cli = ControlClient([
        str(CPM_RUNNER),
        "--control",
        "--tpa-top", "0xD100",
        "--drive", f"A={drive_a}",
        "--drive", f"B={drive_b}",
        "--strict-drives",
        "--tail", "SEED42",
        str(suite_com),
    ])
    try:
        assert cli.call({"cmd": "ping"})["pong"] is True
        info = cli.call({"cmd": "info"})
        assert info["tpa_top"] == 0xD100 and info["pc"] == 0x0100

        # Verify page zero vector ($0005-$0007)
        p0 = cli.call({"cmd": "read_mem", "addr": 0x0005, "len": 3, "format": "bytes"})["bytes"]
        assert p0 == [0xC3, 0x00, 0xD1], f"bad $0005 vector: {p0}"

        # Inject RNG seed into Z80 RAM at $2000 before running
        cli.call({"cmd": "write_mem", "addr": 0x2000, "hex": "DEADBEEF"})

        # Run until BDOS 6 E=$FF idle poll (requires idle_polls=512 by default, skipping 1-shot flush!)
        idle1 = cli.call({"cmd": "run_idle", "max_steps": 1000000})
        assert idle1["reason"] == "idle", f"expected idle, got {idle1}"

        # Verify B:TESTB.DAT was written on drive B and A:TESTA.DAT was renamed+deleted cleanly
        b_file = (drive_b / "TESTB.DAT").read_bytes()
        assert b_file.startswith(b"DRV_B_OK") and len(b_file) == 128
        assert not (drive_a / "TESTA.DAT").exists()
        assert not (drive_a / "RENAMED.DAT").exists()

        # Verify RAM inspection: stack canary, RNG seed copy, shadow text
        assert cli.call({"cmd": "read_mem", "addr": 0x2300, "len": 2, "format": "bytes"})["bytes"] == [0xCA, 0xFE]
        assert cli.call({"cmd": "read_mem", "addr": 0x2010, "len": 4})["hex"] == "deadbeef"
        assert bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x2100, "len": 6})["hex"]) == b"MORIA8"

        # Verify BDOS console output & ANSI screen state
        out = cli.call({"cmd": "console_out"})
        assert "TAIL: SEED42" in out["text"], f"missing tail in {out['text']!r}"
        assert out["text"].endswith("!"), f"expected flush-then-draw '!', got {out['text']!r}"

        scr = cli.call({"cmd": "screen", "include_attrs": True})
        assert scr["rows"] == 24 and scr["cols"] == 80
        assert scr["lines"][2][9:15] == "GREEN!", f"unexpected screen row 2: {scr['lines'][2]!r}"
        assert scr["fg"][2][9:15] == [2, 2, 2, 2, 2, 2], f"unexpected fg colors: {scr['fg'][2][9:15]}"

        # Send ANSI arrow sequence ESC [ A + 'Q' to satisfy BDOS 6 E=$FF loop -> stops at BDOS 10 wait_input
        cli.call({"cmd": "send_keys", "text": "\x1b[AQ"})
        wait2 = cli.call({"cmd": "run_idle", "max_steps": 1000000})
        assert wait2["reason"] == "wait_input", f"expected wait_input at BDOS 10, got {wait2}"

        # Verify Z80 captured all 4 key bytes (ESC [ A Q)
        klen = cli.call({"cmd": "read_mem", "addr": 0x21FF, "len": 1, "format": "bytes"})["bytes"][0]
        assert klen == 4
        keys = bytes.fromhex(cli.call({"cmd": "read_mem", "addr": 0x2200, "len": 4})["hex"])
        assert keys == b"\x1b[AQ"

        # Supply partial line with backspace editing, resume (should suspend mid-line!), then finish line
        cli.call({"cmd": "send_keys", "text": "AB\x08B"})
        wait3 = cli.call({"cmd": "run", "max_steps": 1000000})
        assert wait3["reason"] == "wait_input", f"expected mid-line wait_input, got {wait3}"

        cli.call({"cmd": "send_keys", "text": "C\r"})
        wait4 = cli.call({"cmd": "run", "max_steps": 1000000})
        assert wait4["reason"] == "wait_input", f"expected wait_input at BDOS 1, got {wait4}"

        cli.call({"cmd": "send_keys", "text": "Z"})
        fin = cli.call({"cmd": "run", "max_steps": 1000000})
        assert fin["reason"] == "exited" and fin["exit_code"] == 0, f"expected clean exit, got {fin}"

        final_out = cli.call({"cmd": "console_out"})["text"]
        assert "ALL PASS" in final_out, f"missing ALL PASS in {final_out!r}"

        # Test drive P: (15) selection & file creation in flat --workdir mode
        drv_p_src = """
    DEVICE NOSLOT64K
    ORG $0100
    LD C, 14
    LD E, 15
    CALL 5
    OR A
    JR NZ, bad
    LD C, 22
    LD DE, fcb_p
    CALL 5
    INC A
    JR Z, bad
    LD C, 9
    LD DE, ok_msg
    CALL 5
    LD C, 0
    CALL 5
bad:
    HALT
ok_msg: DB "DRVP-OK$"
fcb_p:  DB 0, "DRVP    ", "TST"
        DS 24, 0
    SAVEBIN "__COM_OUT__", $0100, $ - $0100
"""
        drvp_com = WORK_ROOT / "DRVP.COM"
        assemble(drv_p_src, WORK_ROOT / "drvp.asm", drvp_com)
        drvp_work = WORK_ROOT / "workdir_p"
        drvp_work.mkdir(parents=True)
        drvp_res = subprocess.run(
            [str(CPM_RUNNER), "--workdir", str(drvp_work), str(drvp_com)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
        )
        assert drvp_res.returncode == 0 and b"DRVP-OK" in drvp_res.stdout
        assert (drvp_work / "DRVP.TST").exists()

        # Verify breakpoints, step, set_regs, and reset command
        cli.call({"cmd": "reset", "com_path": str(suite_com), "tpa_top": 0xE000})
        cli.call({"cmd": "add_breakpoint", "addr": 0x0103})
        bp_res = cli.call({"cmd": "run", "max_steps": 100})
        assert bp_res["reason"] == "breakpoint" and bp_res["pc"] == 0x0103
        st_res = cli.call({"cmd": "step", "count": 1})
        assert st_res["steps_run"] == 1 and st_res["pc"] != 0x0103
        cli.call({"cmd": "clear_breakpoints"})
        cli.call({"cmd": "set_regs", "hl": 0x1234})
        assert cli.call({"cmd": "regs"})["hl"] == 0x1234

        rst = cli.call({"cmd": "reset", "tpa_top": 0xC000})
        assert rst["pc"] == 0x0100
        fin2 = cli.call({"cmd": "run", "max_steps": 1000000})
        assert fin2["reason"] == "exited" and fin2["exit_code"] == 0
        assert "TPA LOW" in cli.call({"cmd": "console_out"})["text"]

        assert cli.close() == 0
    finally:
        if cli.proc.poll() is None:
            cli.proc.kill()

    # 5. M0 review unit tests
    test_bdos6_raw_output_and_bdos9_fault(WORK_ROOT)
    test_bdos_hazards_clobber_and_stack_probe(WORK_ROOT)
    test_strict_fcb_and_readstr_and_idle512(WORK_ROOT)
    test_ldir_lddr_r_and_steps(WORK_ROOT)
    test_bios_seldsk_and_bdos14_select_err(WORK_ROOT)
    test_pty_interactive_tty_and_csi(WORK_ROOT)
    test_adm3a_screen_parser(WORK_ROOT)

    shutil.rmtree(WORK_ROOT)
    print("cpm_runner selftest PASSED (sjasmplus + RunCPM + cpm_runner + strict CP/M 2.2 hazards)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

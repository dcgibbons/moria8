"""M0 measurement checklist (§9) -> build/playtest/m0-report.json.

This is an operational measurement job, not a verification gate: it launches
VICE many times and runs a 20k-step fuzz. Every item records what was measured
or why it could not be.
"""

from __future__ import annotations

import json
import os
import signal
import sys
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable

from . import nav
from .fuzz import Fuzzer
from .game import PAL_CYCLES_PER_SECOND, Game, GameFault, Mode, Observation, derive_rng
from .launch import C64_DISK, PLAYTEST_OUT, ViceProcess, allocate_port, build_identity, sha256
from .vice import ViceError, ViceTimeout
from .worker import Snapshot, Worker

OUT = PLAYTEST_OUT / "m0"
REPORT = PLAYTEST_OUT / "m0-report.json"


def town_character(worker: Worker, seed: int) -> Observation:
    obs = worker.start_at_title()
    game = worker.game
    assert game is not None
    game.seed_title(seed)
    while obs.mode != Mode.COMMAND:
        obs = game.press(game.chargen_key(obs) if obs.mode == Mode.CHARGEN else 0x20)
    return obs


def town_snapshot(worker: Worker, seed: int) -> Snapshot:
    town_character(worker, seed)
    return worker.snapshot(f"town-{seed}", {"seed": seed, "keylog": []})


def timed_ms(fn: Callable[[], object], repeat: int) -> float:
    start = time.perf_counter()
    for _ in range(repeat):
        fn()
    return round((time.perf_counter() - start) / repeat * 1000, 3)


# -- item 1 -----------------------------------------------------------------

def item_round_trips(worker: Worker) -> dict[str, object]:
    town_character(worker, 11)
    game = worker.game
    assert game is not None
    mon, ram = game.mon, game.ram
    result: dict[str, object] = {
        "stopped_ping_ms": timed_ms(mon.ping, 200),
        "stopped_mem_get_1B_ms": timed_ms(lambda: mon.mem_get(0x0400, 1, ram), 200),
        "stopped_mem_get_100B_ms": timed_ms(lambda: mon.mem_get(0x0400, 100, ram), 200),
        "stopped_mem_get_3840B_ms": timed_ms(lambda: mon.mem_get(0xC000, 3840, ram), 100),
    }

    def batch() -> None:
        ids = [mon.send_mem_get(0x0400 + i * 100, 100, ram) for i in range(7)]
        for request_id in ids:
            mon.recv_mem_get(request_id, 100)

    def serial() -> None:
        for i in range(7):
            mon.mem_get(0x0400 + i * 100, 100, ram)

    result["pipelined_7x100B_ms"] = timed_ms(batch, 100)
    result["serial_7x100B_ms"] = timed_ms(serial, 100)
    stop = _stop_here(game)
    result["observe_ms"] = timed_ms(lambda: game.observe(stop), 50)

    # While running: a ping stops the CPU; measure its latency, then resume.
    samples = []
    for _ in range(20):
        mon.resume()
        time.sleep(0.02)
        start = time.perf_counter()
        mon.ping()
        samples.append(time.perf_counter() - start)
        mon.drain_events()
    result["running_ping_ms"] = round(sum(samples) / len(samples) * 1000, 3)
    # Leave the CPU stopped at an input stop again.
    game.press(0x20)
    return result


def _stop_here(game: Game):  # type: ignore[no-untyped-def]
    from .vice import StopInfo
    return StopInfo(pc=game.abi.input_get_key, registers=game.mon.registers())


# -- item 2 -----------------------------------------------------------------

def measure_speed(game: Game, seconds: float = 3.0) -> float:
    """Mcycles/s of emulation while the game idles in its input poll loop."""
    clock0 = game.cpu_clock()
    game.mon.resume()
    wall0 = time.monotonic()
    time.sleep(seconds)
    game.mon.ping()
    wall = time.monotonic() - wall0
    game.mon.drain_events()
    clock1 = game.cpu_clock()
    return round((clock1 - clock0) / wall / 1e6, 2)


def item_emulation_speed(run_dir: Path) -> dict[str, object]:
    result: dict[str, object] = {"note": "town idle poll loop, warp, REU on, sound off"}
    for emulator in ("x64sc", "x64"):
        worker = Worker(run_dir / f"speed-{emulator}", 0, emulator=emulator)
        try:
            town_character(worker, 21)
            game = worker.game
            assert game is not None
            entry: dict[str, object] = {"checkpoint_armed_mcps": measure_speed(game)}
            game.mon.checkpoint_delete(game.input_cp)
            for number in list(game.crash_cps):
                game.mon.checkpoint_delete(number)
            entry["no_checkpoints_mcps"] = measure_speed(game)
            try:
                game.mon.resource_set("Drive8TrueEmulation", 0)
                entry["virtual_drive_mcps"] = measure_speed(game)
            except ViceError as exc:
                entry["virtual_drive_mcps"] = f"not measured: {exc}"
            entry["realtime_factor_armed"] = round(
                float(entry["checkpoint_armed_mcps"]) * 1e6 / PAL_CYCLES_PER_SECOND, 1)
            result[emulator] = entry
        except Exception as exc:  # noqa: BLE001 - record and continue
            result[emulator] = f"error: {exc}"
        finally:
            worker.stop()
    return result


# -- item 3 -----------------------------------------------------------------

def measure_action(game: Game, key: int, label: str) -> tuple[dict[str, object], Observation]:
    before = game.last
    assert before is not None
    clock0 = game.cpu_clock()
    wall0 = time.perf_counter()
    obs = game.press(key)
    wall = time.perf_counter() - wall0
    cycles = game.cpu_clock() - clock0
    return ({"action": label, "key": f"${key:02X}", "cycles": cycles,
             "emulated_ms": round(cycles / PAL_CYCLES_PER_SECOND * 1000, 1),
             "wall_ms": round(wall * 1000, 1), "overlay": [before.overlay, obs.overlay],
             "dlvl": [before.dlvl, obs.dlvl], "mode_after": obs.mode.value}, obs)


def walk_to_stairs(game: Game, obs: Observation, limit: int = 400) -> Observation:
    abi = game.abi
    cols, rows = abi.hal_layout_map_cols, abi.hal_layout_map_rows
    for _ in range(limit):
        if obs.mode != Mode.COMMAND:
            obs = game.press(0x20)
            continue
        tiles = nav.read_map(game)
        stairs = set(nav.find_tiles(tiles, cols, abi.TILE_STAIRS_DN >> 4))
        step = nav.first_step(tiles, cols, rows, obs.pos, stairs, in_town=obs.dlvl == 0)
        if step is None:
            raise RuntimeError(f"no path to stairs on DL{obs.dlvl}")
        if step == (0, 0):
            return obs
        target = (obs.pos[0] + step[0], obs.pos[1] + step[1])
        if tiles[target[1] * cols + target[0]] >> 4 == nav.TYPE_DOOR_CLOSED:
            obs = game.press(ord("O"))
        obs = game.press(nav.DIRECTION_KEYS[step])
    raise RuntimeError("stairs not reached")


def item_action_costs(worker: Worker) -> dict[str, object]:
    obs = town_character(worker, 31)
    game = worker.game
    assert game is not None
    rows: list[dict[str, object]] = []
    for key, label in ((ord("L"), "move"), (ord("5"), "rest one turn"), (0x12, "rest until recovered"),
                       (0xC8, "run west"), (0xCC, "run east")):
        if obs.mode != Mode.COMMAND:
            obs = game.press(0x20)
        row, obs = measure_action(game, key, label)
        rows.append(row)
    obs = walk_to_stairs(game, obs)
    row, obs = measure_action(game, ord(">"), "stairs town->DL1 (tier 1 load)")
    rows.append(row)
    for depth in (2, 3):
        try:
            obs = walk_to_stairs(game, obs)
            row, obs = measure_action(game, ord(">"), f"stairs DL{depth - 1}->DL{depth}")
            rows.append(row)
        except RuntimeError as exc:
            rows.append({"action": f"stairs DL{depth - 1}->DL{depth}", "not_measured": str(exc)})
            break
    for key, label in ((ord("I"), "inventory overlay"), (0x20, "dismiss"), (ord("?"), "help overlay"),
                       (0x03, "cancel")):
        row, obs = measure_action(game, key, label)
        rows.append(row)
    return {"actions": rows}


# -- items 4 and 5 ------------------------------------------------------------

def item_boot_and_snapshots(run_dir: Path) -> dict[str, object]:
    result: dict[str, object] = {}
    worker = Worker(run_dir / "boot", 0)
    try:
        start = time.monotonic()
        game = worker._spawn(autostart=True)
        game.boot()
        result["cold_boot_to_title_s"] = round(time.monotonic() - start, 2)
        worker.stop()
        start = time.monotonic()
        worker.start_at_title()
        result["spawn_and_undump_title_s"] = round(time.monotonic() - start, 2)
        town_character(worker, 41)
        game = worker.game
        assert game is not None
        disk_before = sha256(worker.disk)
        path = worker.workdir / "snapshots" / "size.vsf"
        start = time.perf_counter()
        game.dump(path)
        result["dump_ms"] = round((time.perf_counter() - start) * 1000, 1)
        result["snapshot_bytes"] = path.stat().st_size
        start = time.perf_counter()
        game.undump(path)
        result["undump_ms"] = round((time.perf_counter() - start) * 1000, 1)
        for key in b"LLHH5":
            game.press(key)
        result["worker_disk_unchanged_after_undump_and_play"] = sha256(worker.disk) == disk_before
        result["template_disk_unchanged"] = sha256(C64_DISK) == build_identity()["disk_sha256"]
    finally:
        worker.stop()
    return result


# -- item 6 -----------------------------------------------------------------

def item_cycle_counter(worker: Worker) -> dict[str, object]:
    town_character(worker, 51)
    game = worker.game
    assert game is not None
    names = sorted(game.mon.load_register_ids())
    clocks = [game.cpu_clock()]
    for key in b"LH5":
        game.press(key)
        clocks.append(game.cpu_clock())
    return {"registers": names,
            "total_cycle_register": any(n.upper() in ("CLK", "CLOCK", "CYCLES") for n in names),
            "fallback": "MAINCPU CLK parsed from a binary-monitor dump (0x41)",
            "clock_samples": clocks,
            "monotonic": all(b > a for a, b in zip(clocks, clocks[1:]))}


# -- item 7 -----------------------------------------------------------------

def item_replay(worker: Worker, keys_count: int = 300, runs: int = 10) -> dict[str, object]:
    snapshot = town_snapshot(worker, 61)
    game = worker.game
    assert game is not None
    fuzzer = Fuzzer(worker, seed=61, guided=0.5)
    obs = game.undump(snapshot.path)
    keys: list[int] = []
    fault: tuple[str, int | None] | None = None
    for _ in range(keys_count):
        key = fuzzer.choose(obs)
        try:
            obs = game.press(key)
        except GameFault as exc:
            fault = (exc.kind, exc.pc)
            fault_keys = keys + [key]
            break
        keys.append(key)
    fault_repro: list[bool] = []
    if fault is not None:
        # A finding must replay: the same fault at the same key, every time.
        for _ in range(3):
            worker.restore(snapshot)
            game = worker.game
            assert game is not None
            try:
                for key in fault_keys:
                    game.press(key)
                fault_repro.append(False)
            except GameFault as exc:
                fault_repro.append((exc.kind, exc.pc) == fault)
    hashes = []
    vsf_hashes = []
    for run in range(runs):
        obs = worker.restore(snapshot)
        game = worker.game
        assert game is not None
        for key in keys:
            obs = game.press(key)
        hashes.append(game.ram_hash())
        final = worker.workdir / "snapshots" / "replay-final.vsf"
        game.dump(final)
        vsf_hashes.append(sha256(final))
    worker.restore(snapshot)
    game = worker.game
    assert game is not None
    game.mon.mem_set(game.abi.zp_rng_0, derive_rng(9999, 0), game.ram)
    for key in keys:
        game.press(key)
    reseeded = game.ram_hash()
    return {"keys": len(keys), "runs": runs, "fresh_process_per_run": True,
            "recording_fault": None if fault is None else {"kind": fault[0], "pc": fault[1],
                                                            "replayed": f"{sum(fault_repro)}/3"},
            "final_dlvl": obs.dlvl,
            "ram_hash_identical": f"{hashes.count(hashes[0])}/{runs}",
            "vsf_hash_identical": f"{vsf_hashes.count(vsf_hashes[0])}/{runs}",
            "reseeded_diverges": reseeded != hashes[0]}


# -- items 8 and 9 -------------------------------------------------------------

def fuzz_worker(args: tuple[Path, int, int]) -> dict[str, object]:
    run_dir, worker_id, steps = args
    worker = Worker(run_dir, worker_id)
    try:
        report = Fuzzer(worker, seed=1000 + worker_id).run(steps)
        data = report.as_dict()
        data["restarts"] = worker.restarts
        return data
    finally:
        worker.stop()


def item_fuzz(run_dir: Path, total: int = 20000) -> dict[str, object]:
    result: dict[str, object] = {}
    for workers in (1, 4, 8):
        steps = total // workers
        start = time.monotonic()
        with ThreadPoolExecutor(max_workers=workers) as pool:
            reports = list(pool.map(fuzz_worker, [(run_dir / f"fuzz-{workers}", i, steps)
                                                  for i in range(workers)]))
        wall = time.monotonic() - start
        result[f"workers_{workers}"] = {
            "steps_per_worker": steps, "wall_s": round(wall, 1),
            "aggregate_steps_per_s": round(total / wall, 1),
            "per_worker_steps_per_s": [r["steps_per_s"] for r in reports],
            "max_span_wall_s": max(r["max_span_wall_s"] for r in reports),
            "max_span_jiffies": max(r["max_span_jiffies"] for r in reports),
            "max_span_context": max(reports, key=lambda r: r["max_span_wall_s"])["max_span_context"],
            "findings": [f for r in reports for f in r["findings"]],
            "deaths": sum(r["deaths"] for r in reports),
            "max_dlvl": max(r["max_dlvl"] for r in reports),
            "max_clvl": max(r["max_clvl"] for r in reports),
        }
        if workers == 1:
            result["coverage"] = {k: reports[0][k] for k in (
                "modes", "stages", "unknown_screens", "unknown_screen_kinds", "unknown_samples",
                "characters", "deaths", "spans_over_1s")}
    return result


# -- item 10 ----------------------------------------------------------------

def item_key_feed(worker: Worker) -> dict[str, object]:
    obs = town_character(worker, 71)
    game = worker.game
    assert game is not None
    mon, ram = game.mon, game.ram
    result: dict[str, object] = {"kernal_buffer_limit_XMAX": mon.mem_get(0x0289, 1, ram)[0]}
    # One poked key per stop (the production path).
    x0 = obs.pos[0]
    obs = game.press(ord("L"))
    result["poke_one_key_moves"] = obs.pos[0] - x0
    # Two keys poked at once: input_get_command flushes the buffer on entry.
    x0 = obs.pos[0]
    mon.mem_set(0x0277, b"LL", ram)
    mon.mem_set(game.abi.KBDBUF_COUNT, b"\x02", ram)
    mon.resume()
    obs = game._run_to_input(time.monotonic())
    obs = game.press(0x20)  # space: no-op command, lets a surviving 2nd key show up
    result["poke_two_keys_net_moves"] = obs.pos[0] - x0
    # VICE keyboard feed (0x72): when does the key arrive?
    x0 = obs.pos[0]
    mon.keyboard_feed(b"L")
    stops = 0
    for _ in range(3):
        mon.resume()
        obs = game._run_to_input(time.monotonic())
        stops += 1
        if obs.pos[0] != x0:
            break
    result["vice_feed_moves"] = obs.pos[0] - x0
    result["vice_feed_stops_until_effect"] = stops
    return result


# -- item 11 ----------------------------------------------------------------

def item_isolation(run_dir: Path) -> dict[str, object]:
    result: dict[str, object] = {}
    a = Worker(run_dir / "iso", 0)
    b = Worker(run_dir / "iso", 1)
    try:
        result["private_disks"] = a.disk != b.disk and sha256(a.disk) == sha256(b.disk)
        town_character(a, 81)
        snap_a = a.snapshot("iso-a", {"seed": 81})
        town_character(b, 82)
        assert a.vp is not None and b.vp is not None and a.vp.proc and b.vp.proc
        pid_a = a.vp.proc.pid
        a.vp.kill()
        try:
            os.kill(pid_a, 0)
            a_gone = False
        except ProcessLookupError:
            a_gone = True
        assert b.game is not None
        b.game.mon.ping()
        result["pid_only_kill"] = a_gone and b.vp.alive()
        log = a.workdir / "vice.log"
        result["vice_output_to_log_file"] = log.exists() and log.stat().st_size > 0

        # Forced SIGKILL mid-play, then restart from the snapshot.
        a.restore(snap_a)
        assert a.vp is not None and a.vp.proc is not None and a.game is not None
        os.killpg(a.vp.proc.pid, signal.SIGKILL)
        try:
            a.game.press(ord("L"))
            result["sigkill_detected"] = False
        except ViceError as exc:
            result["sigkill_detected"] = type(exc).__name__
        obs = a.restore(snap_a)
        assert a.game is not None
        for key in b"LLLL":
            obs = a.game.press(key)
        result["restart_after_sigkill_ok"] = obs.mode == Mode.COMMAND

        # Frozen emulator: SIGSTOP, then the 60 s response timeout must fire.
        assert a.vp is not None and a.vp.proc is not None
        os.killpg(a.vp.proc.pid, signal.SIGSTOP)
        start = time.monotonic()
        try:
            a.game.press(ord("H"))
            result["frozen_timeout"] = "not raised"
        except ViceTimeout as exc:
            result["frozen_timeout"] = f"{type(exc).__name__} after {time.monotonic() - start:.1f}s"
        a.stop()  # SIGTERM/SIGKILL the stopped process group
        obs = a.restore(snap_a)
        assert a.game is not None
        result["restart_after_timeout_ok"] = a.game.press(ord("L")).mode == Mode.COMMAND
    finally:
        a.stop()
        b.stop()
    return result


# -- smoke equivalent ---------------------------------------------------------

def item_smoke(run_dir: Path) -> dict[str, object]:
    start = time.monotonic()
    worker = Worker(run_dir / "smoke", 0)
    try:
        obs = town_character(worker, 1)
        from .smoke import checks
        failures = checks(obs)
    finally:
        worker.stop()
    return {"elapsed_s": round(time.monotonic() - start, 2), "failures": failures}


ITEMS: list[tuple[str, Callable[[Path], dict[str, object]]]] = [
    ("smoke", item_smoke),
    ("1_round_trips", lambda d: _with_worker(d, "rt", item_round_trips)),
    ("2_emulation_speed", item_emulation_speed),
    ("3_action_costs", lambda d: _with_worker(d, "actions", item_action_costs)),
    ("4_5_boot_and_snapshots", item_boot_and_snapshots),
    ("6_cycle_counter", lambda d: _with_worker(d, "clock", item_cycle_counter)),
    ("7_replay", lambda d: _with_worker(d, "replay", item_replay)),
    ("8_9_fuzz", item_fuzz),
    ("10_key_feed", lambda d: _with_worker(d, "feed", item_key_feed)),
    ("11_isolation", item_isolation),
]


def _with_worker(run_dir: Path, name: str, fn: Callable[[Worker], dict[str, object]]) -> dict[str, object]:
    worker = Worker(run_dir / name, 0)
    try:
        return fn(worker)
    finally:
        worker.stop()


def exit_criteria(items: dict[str, dict[str, object]]) -> dict[str, object]:
    """Evaluate the M0 exit criterion (§8) from the recorded items."""
    expected = [name for name, _ in ITEMS]
    missing = [n for n in expected if n not in items or "error" in items[n]]
    smoke = items.get("smoke", {})
    replay = items.get("7_replay", {})
    fuzz = items.get("8_9_fuzz", {})
    findings = [f for key, value in fuzz.items() if key.startswith("workers_")
                for f in value.get("findings", [])]  # type: ignore[union-attr]
    distinct = sorted({(f["kind"], f["detail"]) for f in findings})
    coverage = fuzz.get("coverage", {})
    criteria = {
        "all_items_measured": not missing,
        "smoke_within_30s": smoke.get("failures") == [] and float(smoke.get("elapsed_s", 99)) <= 30,
        "replay_identical": replay.get("ram_hash_identical") == "10/10"
        and replay.get("vsf_hash_identical") == "10/10" and replay.get("reseeded_diverges") is True,
        "unknown_prompts_filed": bool(coverage)
        and len(coverage.get("unknown_samples", {})) == coverage.get("unknown_screen_kinds"),
        "no_unexplained_hang": not any(kind == "hang" for kind, _ in distinct),
    }
    return {"pass": all(criteria.values()), "criteria": criteria, "missing_items": missing,
            "distinct_findings": [{"kind": k, "detail": d,
                                   "occurrences": sum(1 for f in findings if (f["kind"], f["detail"]) == (k, d))}
                                  for k, d in distinct]}


def main(argv: list[str]) -> int:
    only = set(argv[1:])
    report: dict[str, object] = {}
    if REPORT.exists():
        report = json.loads(REPORT.read_text())
    report["build"] = build_identity()
    report.setdefault("items", {})
    items = report["items"]
    assert isinstance(items, dict)
    for name, fn in ITEMS:
        if only and name not in only:
            continue
        print(f"[m0] {name} ...", flush=True)
        start = time.monotonic()
        try:
            items[name] = fn(OUT)
        except Exception as exc:  # noqa: BLE001 - every item records its own failure
            items[name] = {"error": f"{type(exc).__name__}: {exc}",
                           "traceback": traceback.format_exc().splitlines()[-6:]}
        items[name]["item_wall_s"] = round(time.monotonic() - start, 1)  # type: ignore[index]
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps(report, indent=1, default=str))
        print(json.dumps(items[name], default=str)[:1500], flush=True)
    report["m0_exit"] = exit_criteria(items)
    REPORT.write_text(json.dumps(report, indent=1, default=str))
    print(json.dumps(report["m0_exit"], indent=1))
    return 0 if report["m0_exit"]["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

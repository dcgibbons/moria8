import json
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest import mock

from moria_playtest import dashboard, queue, records


def record(run_id: str, character: str = "human-mage", outcome: str = "died", **extra) -> dict:
    return {"id": run_id, "queue": "main", "platform": "c64", "character": character, "goal": "deep",
            "seed": 7, "outcome": outcome, "steps": 900, "clvl": extra.pop("clvl", 4), "max_dlvl": 2,
            "started": 1.0, "ended": 2.0, **extra}


class RecordsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_a_record_inserted_twice_is_one_row(self) -> None:
        records.insert(record("r1"), self.home)
        records.insert(record("r1", outcome="reached"), self.home)
        self.assertEqual(records.count(self.home), 1)
        with closing(records.open_ro(self.home)) as db:
            self.assertEqual(records.records(db)[0]["outcome"], "reached")
            self.assertEqual(db.execute('SELECT "commit", dirty FROM runs').fetchone(), (None, None))

    def test_import_skips_a_bad_line_and_keeps_the_order(self) -> None:
        log = self.home / "runs.jsonl"
        log.write_text("\n".join([json.dumps(record("r1")), "{not json", json.dumps(record("r2")), "[1]"]) + "\n")
        self.assertEqual(records.import_jsonl(log, self.home), 2)
        with closing(records.open_ro(self.home)) as db:
            self.assertEqual([r["id"] for r in records.records(db)], ["r1", "r2"])
            self.assertEqual([r["id"] for r in records.records(db, newest=1)], ["r2"])

    def test_a_missing_database_reads_as_nothing(self) -> None:
        self.assertIsNone(records.open_ro(self.home))
        self.assertEqual(records.count(self.home), 0)
        self.assertFalse(records.path(self.home).exists())

    def test_rebuild_replaces_what_was_there(self) -> None:
        records.insert(record("gone"), self.home)
        log = self.home / "runs.jsonl"
        log.write_text(json.dumps(record("r1")) + "\n")
        records.import_jsonl(log, self.home, rebuild=True)
        with closing(records.open_ro(self.home)) as db:
            self.assertEqual([r["id"] for r in records.records(db)], ["r1"])


class ReapTest(unittest.TestCase):
    def test_a_finished_run_goes_to_the_log_and_the_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            q = queue.Queue("deep", home)
            combo = q.take("c64", "r1")
            job = {"id": "r1", "queue": "main", "platform": "c64", "character": combo, "goal": "deep",
                   "seed": 5, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b"}
            queue.write_json(home / "runs" / "r1" / "result.json", record("r1", combo, clvl=9))
            queue.write_json(home / "running.json", {"r1": job})
            service = queue.Service(home, home / "queue.json")
            service.reap(q, {})
            self.assertEqual(json.loads((home / "runs.jsonl").read_text())["clvl"], 9)
            with closing(records.open_ro(home)) as db:
                self.assertEqual(records.records(db), [record("r1", combo, clvl=9)])

    def test_a_database_error_does_not_stop_the_reap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            q = queue.Queue("deep", home)
            combo = q.take("c64", "r1")
            job = {"id": "r1", "queue": "main", "platform": "c64", "character": combo, "goal": "deep",
                   "seed": 5, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b"}
            queue.write_json(home / "runs" / "r1" / "result.json", record("r1", combo))
            queue.write_json(home / "running.json", {"r1": job})
            records.path(home).mkdir()   # a directory where the database should be
            service = queue.Service(home, home / "queue.json")
            service.reap(q, {})
            self.assertEqual(q.platform("c64")["items"][combo]["runs"], 1)
            self.assertIn("r1", (home / "runs.jsonl").read_text())
            self.assertTrue(any("queue.db insert failed" in line for line in service.log_lines))

    def test_the_service_imports_a_log_the_database_lacks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            (home / "runs.jsonl").write_text("".join(json.dumps(record(f"r{n}")) + "\n" for n in range(3)))
            records.insert(record("r0"), home)
            service = queue.Service(home, home / "queue.json")
            service.sync_records()
            self.assertEqual(records.count(home), 3)


class DashboardTest(unittest.TestCase):
    def test_counts_from_the_database_match_the_log(self) -> None:
        runs = [record("r1"), record("r2", clvl=12), record("r3", outcome="reached", clvl=25),
                record("r4", "dwarf-priest", features={"layers": {"fight": 3}, "casts": {
                    "Bless": {"cast": 2, "effect": 1, "evidence": "first"}}}, death={"cause": "orc"}),
                record("r5", "dwarf-priest", features={"casts": {"Bless": {"cast": 1, "evidence": "second"}}}),
                record("r6", outcome="abandoned"), record("r7", queue="ab1"), record("r8", goal="clvl10")]
        runs += [record(f"m{n}", milestones={"clvl5": 1}) for n in range(4)]
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            log = home / "runs.jsonl"
            log.write_text("".join(json.dumps(r) + "\n" for r in runs) + "{torn line\n")
            with mock.patch.dict(dashboard._cache, clear=True):
                from_log = dashboard.queue_runs(home, "deep", queue.COUNTED)
                records.import_jsonl(log, home)
                from_db = dashboard.queue_runs(home, "deep", queue.COUNTED)
                self.assertEqual(from_db, from_log)
                self.assertEqual(from_db["runs"], len(runs))
                self.assertEqual(from_db["features"]["priest"]["spells"]["Bless"]["evidence"], "first")
                self.assertEqual(from_db["ratings"]["human-mage"]["runs"], 7)
                records.insert(record("r9"), home)
                self.assertEqual(dashboard.queue_runs(home, "deep", queue.COUNTED)["ratings"]["human-mage"]["runs"], 8)


if __name__ == "__main__":
    unittest.main()

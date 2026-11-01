"""The continuous queue's run records in SQLite (§23.10): ``queue.db``.

``runs.jsonl`` stays the durable copy: the service appends each finished
run's record there first and then inserts it here, so the dashboard can
query the main queue's counted runs instead of parsing every record on each
change. The database can always be rebuilt from the log:
``python -m moria_playtest.records rebuild``.

One table, ``runs``: the columns the dashboard selects and orders on, and
the whole record as JSON. Rows are in the order they were written (rowid),
like the log's lines. WAL mode lets the dashboard and the publisher read
while the service writes.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
from typing import Any

COLUMNS = ("id", "queue", "platform", "character", "goal", "outcome", "build", "commit", "dirty", "seed", "steps",
           "clvl", "max_dlvl", "started", "ended", "suite")
SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY, queue TEXT, platform TEXT, character TEXT, goal TEXT, outcome TEXT, build TEXT,
    "commit" TEXT, dirty INTEGER, seed INTEGER, steps INTEGER, clvl INTEGER, max_dlvl INTEGER, started REAL,
    ended REAL, suite TEXT, record TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS runs_counted ON runs (queue, goal, outcome);
CREATE INDEX IF NOT EXISTS runs_character ON runs (character);
"""
QUOTED = ", ".join(f'"{c}"' for c in COLUMNS)   # "commit" is an SQL keyword
INSERT = f"INSERT OR REPLACE INTO runs ({QUOTED}, record) VALUES ({', '.join('?' * (len(COLUMNS) + 1))})"


def path(home: Path) -> Path:
    return home / "queue.db"


def connect(home: Path) -> sqlite3.Connection:
    """The writer's connection, creating the database if need be. Autocommit:
    each statement is its own transaction unless one is begun."""
    home.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path(home), isolation_level=None)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript(SCHEMA)
    return db


def open_ro(home: Path) -> sqlite3.Connection | None:
    """A read-only connection for the dashboard; None before the service has
    made the database (``mode=ro`` would not create it, but fail)."""
    if not path(home).exists():
        return None
    try:
        return sqlite3.connect(path(home).resolve().as_uri() + "?mode=ro", uri=True)
    except sqlite3.Error:
        return None


def row(record: dict[str, Any]) -> tuple[Any, ...]:
    return (*(record.get(c) for c in COLUMNS), json.dumps(record, default=str))


def insert(record: dict[str, Any], home: Path) -> None:
    """One finished run's record; a record already there (same id) is replaced."""
    with closing(connect(home)) as db:
        db.execute(INSERT, row(record))


def import_jsonl(source: Path, home: Path, rebuild: bool = False) -> int:
    """Insert every record in ``source`` (a ``runs.jsonl``), in its order, in
    one transaction; lines that do not parse are skipped. ``rebuild`` empties
    the table first. Returns the number of records read."""
    count = 0
    with closing(connect(home)) as db, source.open() as lines:
        db.execute("BEGIN IMMEDIATE")
        try:
            if rebuild:
                db.execute("DELETE FROM runs")
            for line in lines:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict) or "id" not in record:
                    continue
                db.execute(INSERT, row(record))
                count += 1
            db.execute("COMMIT")
        except BaseException:
            db.execute("ROLLBACK")
            raise
    return count


def count(home: Path) -> int:
    """The rows in the database; 0 when there is none yet."""
    db = open_ro(home)
    if db is None:
        return 0
    with closing(db):
        try:
            return db.execute("SELECT count(*) FROM runs").fetchone()[0]
        except sqlite3.Error:
            return 0


def records(db: sqlite3.Connection, where: str = "1", params: tuple[Any, ...] = (),
            newest: int | None = None) -> list[dict[str, Any]]:
    """The full records matching ``where`` (SQL over the indexed columns) in
    the order they were written, or only the ``newest`` of them, newest first."""
    sql = f"SELECT record FROM runs WHERE {where} ORDER BY rowid"
    if newest is not None:
        sql += f" DESC LIMIT {int(newest)}"
    return [json.loads(text) for text, in db.execute(sql, params)]


def main(argv: list[str] | None = None) -> int:
    from .queue import HOME
    parser = argparse.ArgumentParser(prog="moria_playtest.records")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("rebuild", help="re-create queue.db from runs.jsonl")
    parser.parse_args(argv)
    source = HOME / "runs.jsonl"
    if not source.exists():
        parser.error(f"no {source}")
    read = import_jsonl(source, HOME, rebuild=True)
    print(f"{path(HOME)}: {count(HOME)} runs from {read} records in {source}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

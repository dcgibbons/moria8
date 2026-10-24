"""``make playtest-dashboard`` (§6.9): stdlib HTTP server on 127.0.0.1:8064.

Serves playtest/dashboard/index.html and ``/api/status`` for one session
directory (default: the most recently modified one). It only reads files, so it
can never affect a running session.
"""

from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .launch import PLAYTEST_OUT, ROOT

INDEX = ROOT / "playtest" / "dashboard" / "index.html"
SESSIONS = PLAYTEST_OUT / "sessions"


def latest_session() -> Path | None:
    dirs = [d for d in SESSIONS.glob("*") if (d / "summary.json").exists()]
    return max(dirs, key=lambda d: (d / "summary.json").stat().st_mtime) if dirs else None


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def status(session: Path | None) -> dict[str, object]:
    session = session or latest_session()
    if session is None:
        return {"session": None}
    events_path = session / "events.jsonl"
    events = events_path.read_text().splitlines()[-60:] if events_path.exists() else []
    return {"session": session.name,
            "summary": read_json(session / "summary.json"),
            "workers": [w for w in (read_json(p) for p in sorted(session.glob("status-w*.json"))) if w],
            "events": [json.loads(line) for line in events if line.strip()]}


def make_handler(session: Path | None) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - http.server API
            if self.path.startswith("/api/status"):
                body = json.dumps(status(session), default=str).encode()
                kind = "application/json"
            elif self.path in ("/", "/index.html"):
                body, kind = INDEX.read_bytes(), "text/html; charset=utf-8"
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args: object) -> None:
            pass

    return Handler


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-dashboard")
    parser.add_argument("--port", type=int, default=8064)
    parser.add_argument("--session", type=Path, help="session directory (default: latest)")
    args = parser.parse_args(argv)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(args.session))
    print(f"playtest dashboard: http://127.0.0.1:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

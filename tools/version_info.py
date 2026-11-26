#!/usr/bin/env python3
"""Central version and build-channel resolver for all Moria8 ports.

Supports the lifecycle:
  dev builds [0..n] -> rc builds [0..n] -> release -> post-release patch

Resolution inputs:
  - Base SemVer per port in `version.json` (e.g. "2.0.0")
  - Build channel (`BUILD_CHANNEL` or `--channel`): auto (default), dev, rc, release
  - Build counter (`BUILD_NUM` or `--build-num`): optional 0..999 for dev, required 0..999 for rc
  - Explicit suffix (`VERSION_SUFFIX` or `--suffix`): overrides channel/build_num

Display versions (e.g. `v2.1.0-rc1`) are capped at 16 characters so they always fit
Commodore disk directory art (`tools/diskart.py`), 40/80-column title screens,
System Info screens, and cartridge metadata.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Iterable
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VERSION_FILE = REPO_ROOT / "version.json"
ALL_PORTS: tuple[str, ...] = (
    "c64",
    "c128",
    "plus4",
    "apple2",
    "cx16",
    "atari8",
    "bbcmaster",
    "cpm",
)
VALID_CHANNELS: tuple[str, ...] = ("auto", "dev", "rc", "release")
MAX_DISPLAY_LEN = 16  # Commodore directory art slot width (tools/diskart.py)

BASE_SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
BUILD_NUM_RE = re.compile(r"^\d{1,3}$")
TAG_RELEASE_RE = re.compile(r"^v(\d+\.\d+\.\d+)$")
TAG_RC_RE = re.compile(r"^v(\d+\.\d+\.\d+)-rc(\d{1,3})$")
SAFE_SUFFIX_RE = re.compile(r"^-[A-Za-z0-9][A-Za-z0-9.-]*$")


@dataclasses.dataclass(frozen=True)
class PortVersion:
    port: str
    base: str
    bare: str
    display: str
    major: int
    minor: int
    patch: int


@dataclasses.dataclass(frozen=True)
class ResolvedVersions:
    ports: dict[str, PortVersion]
    channel: str
    build_num: str | None
    suffix: str
    source: str
    git_tag: str | None
    git_dirty: bool | None
    release_version: str

    def port(self, name: str) -> PortVersion:
        if name not in self.ports:
            raise KeyError(f"Unknown or unloaded port {name!r}")
        return self.ports[name]


def atomic_write_if_changed(path: Path, text: str) -> bool:
    """Write UTF-8 text atomically only if the destination content changed.

    Returns True when a write occurred, False when identical content already
    existed (preserving the existing mtime for incremental Make builds).
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        try:
            if path.read_text(encoding="utf-8") == text:
                return False
        except OSError:
            pass
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as tmp:
            tmp.write(text)
            tmp_path = Path(tmp.name)
        os.replace(tmp_path, path)
    except BaseException:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)
        raise
    return True


def _inspect_git(repo_root: Path) -> tuple[str | None, bool | None]:
    """Return `(exact_tag, is_dirty)` if git is readable, else `(None, None)`."""
    try:
        status_proc = subprocess.run(
            ["git", "-C", str(repo_root), "status", "--porcelain"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None, None
    if status_proc.returncode != 0:
        return None, None
    dirty = bool(status_proc.stdout.strip())

    try:
        tag_proc = subprocess.run(
            ["git", "-C", str(repo_root), "describe", "--exact-match", "--tags", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None, dirty
    tag = tag_proc.stdout.strip() if tag_proc.returncode == 0 else None
    if tag == "":
        tag = None
    return tag, dirty


def _parse_base_semver(raw_val: object, port: str) -> tuple[str, int, int, int]:
    if not isinstance(raw_val, str) or not raw_val.strip():
        raise ValueError(f"version.json missing string version for {port}")
    cleaned = raw_val.strip()
    if cleaned.lower().startswith("v"):
        cleaned = cleaned[1:]
    m = BASE_SEMVER_RE.match(cleaned)
    if not m:
        raise ValueError(
            f"version.json entry for {port} ({raw_val!r}) must be base SemVer X.Y.Z; "
            "use BUILD_CHANNEL / BUILD_NUM / VERSION_SUFFIX for prerelease suffixes"
        )
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    return f"{major}.{minor}.{patch}", major, minor, patch


def _validate_build_num(raw_num: str, channel: str) -> str:
    if not BUILD_NUM_RE.match(raw_num):
        raise ValueError(
            f"Invalid BUILD_NUM={raw_num!r} for BUILD_CHANNEL={channel} (expected integer 0..999)"
        )
    return str(int(raw_num))


def resolve_versions(
    version_file: Path = DEFAULT_VERSION_FILE,
    *,
    ports: Iterable[str] = ALL_PORTS,
    channel: str | None = None,
    build_num: str | None = None,
    suffix: str | None = None,
    repo_root: Path | None = None,
) -> ResolvedVersions:
    """Load `version.json` and resolve channel/build-number suffixes for requested ports."""
    port_list = tuple(ports)
    if not port_list:
        raise ValueError("At least one port must be requested")
    for p in port_list:
        if p not in ALL_PORTS:
            raise ValueError(f"Unknown port {p!r}; expected one of {ALL_PORTS}")

    raw_json = json.loads(Path(version_file).read_text(encoding="utf-8"))
    if not isinstance(raw_json, dict):
        raise ValueError(f"{version_file} must be a JSON object")

    parsed_bases: dict[str, tuple[str, int, int, int]] = {}
    for p in port_list:
        parsed_bases[p] = _parse_base_semver(raw_json.get(p), p)

    env_suffix = os.environ.get("VERSION_SUFFIX", "")
    env_channel = os.environ.get("BUILD_CHANNEL", "")
    env_num = os.environ.get("BUILD_NUM", "")

    raw_suffix = (suffix if suffix is not None else env_suffix).strip()
    raw_channel = (channel if channel is not None else env_channel).strip().lower() or "auto"
    raw_num = (build_num if build_num is not None else env_num).strip()

    effective_repo = repo_root if repo_root is not None else REPO_ROOT
    git_tag: str | None = None
    git_dirty: bool | None = None

    if raw_suffix:
        norm_suffix = raw_suffix if raw_suffix.startswith("-") else f"-{raw_suffix}"
        if not SAFE_SUFFIX_RE.match(norm_suffix):
            raise ValueError(
                f"Invalid VERSION_SUFFIX={raw_suffix!r}: only [A-Za-z0-9.-] allowed after '-'"
            )
        eff_channel = "custom"
        eff_num: str | None = None
        eff_suffix = norm_suffix
        source = "VERSION_SUFFIX"
    else:
        if raw_channel not in VALID_CHANNELS:
            raise ValueError(
                f"Invalid BUILD_CHANNEL={raw_channel!r}; expected one of {VALID_CHANNELS}"
            )
        if raw_channel == "auto":
            if raw_num:
                raise ValueError(
                    "BUILD_NUM cannot be set when BUILD_CHANNEL=auto; "
                    "pass BUILD_CHANNEL=dev or BUILD_CHANNEL=rc"
                )
            git_tag, git_dirty = _inspect_git(effective_repo)
            distinct_bases = sorted({b[0] for b in parsed_bases.values()})
            if git_tag and git_dirty is False:
                rel_m = TAG_RELEASE_RE.match(git_tag)
                rc_m = TAG_RC_RE.match(git_tag)
                if rel_m:
                    tag_base = rel_m.group(1)
                    if distinct_bases != [tag_base]:
                        raise ValueError(
                            f"Git release tag {git_tag} disagrees with {version_file} ({distinct_bases})"
                        )
                    eff_channel = "release"
                    eff_num = None
                    eff_suffix = ""
                    source = f"git tag {git_tag}"
                elif rc_m:
                    tag_base, rc_num = rc_m.group(1), str(int(rc_m.group(2)))
                    if distinct_bases != [tag_base]:
                        raise ValueError(
                            f"Git RC tag {git_tag} disagrees with {version_file} ({distinct_bases})"
                        )
                    eff_channel = "rc"
                    eff_num = rc_num
                    eff_suffix = f"-rc{rc_num}"
                    source = f"git tag {git_tag}"
                else:
                    eff_channel = "dev"
                    eff_num = None
                    eff_suffix = "-dev"
                    source = f"auto (non-release tag {git_tag})"
            else:
                eff_channel = "dev"
                eff_num = None
                eff_suffix = "-dev"
                if git_tag and git_dirty:
                    source = f"auto (dirty worktree at {git_tag})"
                elif git_dirty is None:
                    source = "auto (git unavailable)"
                elif git_dirty:
                    source = "auto (dirty worktree)"
                else:
                    source = "auto (untagged commit)"
        elif raw_channel == "dev":
            eff_channel = "dev"
            if raw_num:
                eff_num = _validate_build_num(raw_num, "dev")
                eff_suffix = f"-dev{eff_num}"
                source = f"BUILD_CHANNEL=dev BUILD_NUM={eff_num}"
            else:
                eff_num = None
                eff_suffix = "-dev"
                source = "BUILD_CHANNEL=dev"
        elif raw_channel == "rc":
            if not raw_num:
                raise ValueError("BUILD_CHANNEL=rc requires BUILD_NUM=0..999")
            eff_channel = "rc"
            eff_num = _validate_build_num(raw_num, "rc")
            eff_suffix = f"-rc{eff_num}"
            source = f"BUILD_CHANNEL=rc BUILD_NUM={eff_num}"
        else:  # release
            if raw_num:
                raise ValueError("BUILD_CHANNEL=release does not accept BUILD_NUM")
            eff_channel = "release"
            eff_num = None
            eff_suffix = ""
            source = "BUILD_CHANNEL=release"

    resolved_ports: dict[str, PortVersion] = {}
    for p in port_list:
        base, major, minor, patch = parsed_bases[p]
        bare = f"{base}{eff_suffix}"
        display = f"v{bare}"
        if not all(0x21 <= ord(ch) <= 0x7E for ch in display):
            raise ValueError(f"Resolved version {display!r} for {p} contains invalid characters")
        if len(display) > MAX_DISPLAY_LEN:
            raise ValueError(
                f"Resolved version {display!r} for {p} is {len(display)} chars, "
                f"exceeding the {MAX_DISPLAY_LEN}-char Commodore directory art limit"
            )
        resolved_ports[p] = PortVersion(
            port=p,
            base=base,
            bare=bare,
            display=display,
            major=major,
            minor=minor,
            patch=patch,
        )

    displays = sorted({pv.display for pv in resolved_ports.values()})
    release_version = displays[0] if len(displays) == 1 else ""
    return ResolvedVersions(
        ports=resolved_ports,
        channel=eff_channel,
        build_num=eff_num,
        suffix=eff_suffix,
        source=source,
        git_tag=git_tag,
        git_dirty=git_dirty,
        release_version=release_version,
    )


def resolve_port_version(
    version_file: Path,
    port: str,
    *,
    channel: str | None = None,
    build_num: str | None = None,
    suffix: str | None = None,
    repo_root: Path | None = None,
) -> PortVersion:
    """Resolve version fields for a single port from `version_file`."""
    res = resolve_versions(
        version_file,
        ports=(port,),
        channel=channel,
        build_num=build_num,
        suffix=suffix,
        repo_root=repo_root,
    )
    return res.port(port)


def format_stamp(resolved: ResolvedVersions) -> str:
    lines = [
        f"channel={resolved.channel}",
        f"build_num={resolved.build_num or ''}",
        f"suffix={resolved.suffix}",
        f"release_version={resolved.release_version}",
    ]
    for p in ALL_PORTS:
        if p in resolved.ports:
            pv = resolved.ports[p]
            lines.append(f"{p}={pv.display}")
    return "\n".join(lines) + "\n"


def check_release_clean(
    version_file: Path = DEFAULT_VERSION_FILE,
    *,
    repo_root: Path | None = None,
    allow_dirty: bool | None = None,
) -> ResolvedVersions:
    """Validate that signed `release`/`rc` artifacts come from a clean matching git tag."""
    if allow_dirty is None:
        allow_dirty = os.environ.get("ALLOW_DIRTY_RELEASE", "").strip() == "1"
    resolved = resolve_versions(version_file, repo_root=repo_root)
    if allow_dirty:
        return resolved
    if not resolved.release_version:
        raise ValueError("version.json port versions disagree; cannot produce signed release artifacts")
    if resolved.channel not in ("release", "rc"):
        raise ValueError(
            f"Signed artifacts require BUILD_CHANNEL=release or rc (resolved {resolved.channel!r} -> "
            f"{resolved.release_version}). Set ALLOW_DIRTY_RELEASE=1 to override for dry runs."
        )
    effective_repo = repo_root if repo_root is not None else REPO_ROOT
    git_tag, git_dirty = _inspect_git(effective_repo)
    if git_dirty is None:
        raise ValueError(
            "Unable to inspect git state for signed release artifacts; "
            "run from a clean checkout or set ALLOW_DIRTY_RELEASE=1 to override."
        )
    if git_dirty:
        raise ValueError(
            "Working tree has uncommitted/untracked changes; commit or use a clean tag worktree "
            "(or set ALLOW_DIRTY_RELEASE=1 for dry runs)."
        )
    if git_tag != resolved.release_version:
        raise ValueError(
            f"HEAD is not cleanly tagged at {resolved.release_version} (git_tag={git_tag!r}); "
            "tag the commit first or set ALLOW_DIRTY_RELEASE=1 for dry runs."
        )
    return resolved


class _VersionInfoSelfTest(unittest.TestCase):
    def _write_ver(self, root: Path, ver: str = "2.1.0", ports: Iterable[str] = ALL_PORTS) -> Path:
        vf = root / "version.json"
        vf.write_text(json.dumps({p: ver for p in ports}, indent=2) + "\n", encoding="utf-8")
        return vf

    def test_channels_and_formats(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            vf = self._write_ver(Path(td), "2.1.0")
            # dev without BUILD_NUM
            r = resolve_versions(vf, channel="dev", build_num="", suffix="")
            self.assertEqual(r.channel, "dev")
            self.assertEqual(r.release_version, "v2.1.0-dev")
            self.assertEqual(r.port("c64").bare, "2.1.0-dev")
            self.assertEqual(r.port("cpm").major, 2)
            self.assertEqual(r.port("cpm").minor, 1)
            self.assertEqual(r.port("cpm").patch, 0)

            # dev[0..n]
            for num in ("0", "1", "99"):
                rn = resolve_versions(vf, channel="dev", build_num=num, suffix="")
                self.assertEqual(rn.release_version, f"v2.1.0-dev{num}")
                self.assertEqual(rn.port("cx16").bare, f"2.1.0-dev{num}")

            # rc[0..n]
            for num in ("0", "1", "12"):
                rc = resolve_versions(vf, channel="rc", build_num=num, suffix="")
                self.assertEqual(rc.channel, "rc")
                self.assertEqual(rc.release_version, f"v2.1.0-rc{num}")
                self.assertEqual(rc.port("apple2").bare, f"2.1.0-rc{num}")

            # release
            rel = resolve_versions(vf, channel="release", build_num="", suffix="")
            self.assertEqual(rel.channel, "release")
            self.assertEqual(rel.release_version, "v2.1.0")
            self.assertEqual(rel.port("cpm").bare, "2.1.0")

            # custom suffix override
            cus = resolve_versions(vf, channel="dev", build_num="", suffix="alpha1")
            self.assertEqual(cus.channel, "custom")
            self.assertEqual(cus.release_version, "v2.1.0-alpha1")

    def test_validation_errors(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            vf = self._write_ver(root, "2.1.0")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="rc", build_num="", suffix="")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="release", build_num="1", suffix="")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="auto", build_num="1", suffix="")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="bogus", build_num="", suffix="")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="dev", build_num="abc", suffix="")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="dev", build_num="", suffix="-this-is-way-too-long")
            with self.assertRaises(ValueError):
                resolve_versions(vf, channel="dev", build_num="", suffix="-bad space")

            # Base SemVer check rejects embedded suffixes in version.json
            bad_vf = root / "bad.json"
            bad_vf.write_text(json.dumps({p: "2.1.0-rc1" for p in ALL_PORTS}), encoding="utf-8")
            with self.assertRaises(ValueError):
                resolve_versions(bad_vf, channel="release", build_num="", suffix="")

    def test_auto_git_detection(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            vf = self._write_ver(Path(td), "2.1.0")
            this_mod = sys.modules[__name__]

            with mock.patch.object(this_mod, "_inspect_git", return_value=("v2.1.0", False)):
                r = resolve_versions(vf, channel="auto", build_num="", suffix="")
                self.assertEqual(r.channel, "release")
                self.assertEqual(r.release_version, "v2.1.0")

            with mock.patch.object(this_mod, "_inspect_git", return_value=("v2.1.0-rc2", False)):
                r = resolve_versions(vf, channel="auto", build_num="", suffix="")
                self.assertEqual(r.channel, "rc")
                self.assertEqual(r.build_num, "2")
                self.assertEqual(r.release_version, "v2.1.0-rc2")

            with mock.patch.object(this_mod, "_inspect_git", return_value=("v2.0.0", False)):
                with self.assertRaises(ValueError):
                    resolve_versions(vf, channel="auto", build_num="", suffix="")

            with mock.patch.object(this_mod, "_inspect_git", return_value=("v2.1.0", True)):
                r = resolve_versions(vf, channel="auto", build_num="", suffix="")
                self.assertEqual(r.channel, "dev")
                self.assertEqual(r.release_version, "v2.1.0-dev")

            with mock.patch.object(this_mod, "_inspect_git", return_value=(None, False)):
                r = resolve_versions(vf, channel="auto", build_num="", suffix="")
                self.assertEqual(r.channel, "dev")
                self.assertEqual(r.release_version, "v2.1.0-dev")

            with mock.patch.object(this_mod, "_inspect_git", return_value=(None, None)):
                r = resolve_versions(vf, channel="auto", build_num="", suffix="")
                self.assertEqual(r.channel, "dev")
                self.assertEqual(r.release_version, "v2.1.0-dev")

    def test_partial_port_and_atomic_write_mtime(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            partial = root / "partial.json"
            partial.write_text('{"cpm": "2.0.0"}\n', encoding="utf-8")
            pv = resolve_port_version(partial, "cpm", channel="rc", build_num="0", suffix="")
            self.assertEqual(pv.bare, "2.0.0-rc0")
            self.assertEqual(pv.display, "v2.0.0-rc0")

            stamp = root / ".version.stamp"
            self.assertTrue(atomic_write_if_changed(stamp, "channel=dev\n"))
            os.utime(stamp, (1_700_000_000, 1_700_000_000))
            mtime_before = stamp.stat().st_mtime
            self.assertFalse(atomic_write_if_changed(stamp, "channel=dev\n"))
            self.assertEqual(stamp.stat().st_mtime, mtime_before)
            self.assertTrue(atomic_write_if_changed(stamp, "channel=release\n"))
            self.assertNotEqual(stamp.stat().st_mtime, mtime_before)


def _run_selftest() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(_VersionInfoSelfTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version-file", type=Path, default=DEFAULT_VERSION_FILE)
    parser.add_argument("--channel", default=None)
    parser.add_argument("--build-num", default=None)
    parser.add_argument("--suffix", default=None)
    parser.add_argument("--port", choices=ALL_PORTS, default=None)
    parser.add_argument("--bare", action="store_true")
    parser.add_argument("--display", action="store_true")
    parser.add_argument("--print-release", action="store_true")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--write-stamp", type=Path, default=None)
    parser.add_argument("--check-release-clean", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return _run_selftest()

    try:
        if args.check_release_clean:
            res = check_release_clean(args.version_file)
            print(f"Release state verified: {res.release_version} ({res.source})")
            return 0

        if args.port:
            pv = resolve_port_version(
                args.version_file,
                args.port,
                channel=args.channel,
                build_num=args.build_num,
                suffix=args.suffix,
            )
            if args.bare:
                print(pv.bare)
            else:
                print(pv.display)
            return 0

        res = resolve_versions(
            args.version_file,
            channel=args.channel,
            build_num=args.build_num,
            suffix=args.suffix,
        )

        if args.write_stamp is not None:
            atomic_write_if_changed(args.write_stamp, format_stamp(res))
            return 0

        if args.print_release:
            print(res.release_version)
            return 0

        if args.summary:
            bases = sorted({pv.base for pv in res.ports.values()})
            print(f"Base SemVer (version.json): {', '.join(bases)}")
            print(f"Resolved Channel:           {res.channel} ({res.source})")
            if res.build_num is not None:
                print(f"Build Number:               {res.build_num}")
            if res.release_version:
                print(f"Display Version (all 8):    {res.release_version}")
            else:
                for p in ALL_PORTS:
                    print(f"  {p:10s}: {res.ports[p].display}")
            return 0

        print(res.release_version)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

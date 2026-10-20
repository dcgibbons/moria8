#!/usr/bin/env python3
"""Record gameplay on an emulator and cut it into the website's animated GIFs.

  tools/gifcapture/record.py c64       loading art + character creation (clip 1), level 8 Warrior on DL8 (clips 2-4)
  tools/gifcapture/record.py plus4     level 10 Rogue on DL10 (wizard mode), 4 action clips
  tools/gifcapture/record.py c128      level 5 Mage on DL4, 4 action clips
  tools/gifcapture/record.py apple2    level 30 Priest on DL35, 4 action clips

Output: docs/assets/moria8-<platform>-gameplay-<n>.gif. Frame dumps and emulator
scratch files go under build/gifcapture/ (override with GIFCAP_WORK).

Requires the platform disk images in build/ (make disk), ffmpeg, Pillow and numpy,
VICE (x64sc/x128/xplus4) for the Commodore targets, and MAME apple2ee with
A2ROMS=<dir holding apple2ee.zip> for the Apple II. Run on a normal desktop
session: VICE/MAME harnesses use localhost sockets and files.

How it works: VICE is driven through its binary monitor (key feed, screen-RAM
reads, frame grabs); the C128 reads the CIA matrix directly, so its keyboard
routine is patched in RAM to read a monitor-controlled byte. MAME is driven
through rpc.lua. Wizard mode (Ctrl+W) sets up the action clips off-camera.
"""
import os, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from paths import BUILD, WORK

CFG = {
    "c64":    dict(race="DWARF", klass="WARRIOR", name="DURIN", plat="c64", creation_only=True),
    "plus4":  dict(race="HUMAN", klass="ROGUE", name="SHADE", plat="plus4", level=10, dl=10),
    "c128":   dict(race="HUMAN", klass="MAGE", name="ELWING", sex="B", plat="c128", level=5, dl=4, minfrac=0.5, summon_every=8),
    "apple2": dict(race="HUMAN", klass="PRIEST", name="MIRA", sex="B", plat="apple2", level=30, dl=35),
}

def vice_cmd(exe, port, extra, image):
    return [exe, "-console", "-config", "/dev/null", "-default", "+saveres", "-binarymonitor",
            "-binarymonitoraddress", f"ip4://127.0.0.1:{port}", "+sound"] + extra + [str(image)]

def make_game(plat, cfg, out):
    import rec
    from rec import Game
    if plat == "plus4":
        cmd = vice_cmd("xplus4", 6504, ["-drive8truedrive", "-drive8type", "1541", "+busdevice8",
                       "-autostartprgmode", "1", "-autostart"], BUILD / "moria8-plus4.d64")
        g = Game(cmd, 6504, out, (0, 0, 384, 288), (0x0C00, 40, 25), fps=10); g.v.vic = True
    elif plat == "c128":
        cmd = vice_cmd("x128", 6503, ["-80col", "-drive8truedrive", "-drive8type", "1571", "+busdevice8"],
                       BUILD / "moria8-c128.d71")
        g = rec.InjectGame(cmd, 6503, out, (106, 36, 762, 244), (0, 80, 25, 10), fps=10)
        g.v.vic = False; g.scale = (656, 416)
    return g

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in CFG:
        sys.exit(__doc__)
    plat = sys.argv[1]; cfg = dict(CFG[plat])
    WORK.mkdir(parents=True, exist_ok=True); os.chdir(WORK)
    if plat == "c64":
        import gamerec
        cmd = vice_cmd("x64sc", 6502, ["-drive8truedrive", "-drive8type", "1541", "+busdevice8",
                       "-autostartprgmode", "1", "-autostart"], BUILD / "moria8-c64.d64")
        def after(g):
            # clips 2-4: wizard-boosted Warrior fighting on DL8, same style as the other platforms
            import action
            from split import split_encode
            cfg.update(level=8, dl=8)
            g.quiet = True; action.wizard_setup(g, cfg); g.quiet = False
            g.dir = str(WORK / "c64" / "action"); g.n = 0
            shutil.rmtree(g.dir, ignore_errors=True); os.makedirs(g.dir)
            g.trace = []
            g.hold(1); action.action(g, cfg, 36); g.hold(1)
            t = g.trace; moves = [p for i, p in enumerate(t) if i == 0 or p != t[i - 1]]
            print('moves', len(moves), 'reversals', sum(1 for i in range(2, len(moves)) if moves[i] == moves[i - 2])); print(moves)
            split_encode(g.dir, [g.n // 3, 2 * g.n // 3], "c64", fps=10, first=2)
        cfg.update(after=after, cmd=cmd, port=6502, out=str(WORK / "c64" / "frames"), crop=(104, 16, 488, 288),
                   scr=(0x0400, 40, 25), vic=True, art=True)
        gamerec.run(cfg)
        return
    for attempt in range(5):
        try:
            return record_action(plat, cfg)
        except RuntimeError as e:
            print("attempt", attempt, "failed:", e)

def record_action(plat, cfg):
    import action
    from split import split_encode
    if plat == "apple2":
        from mamegame import MameGame
        from PIL import Image
        g = MameGame(str(WORK / "apple2" / "run"), fps=10)
    else:
        g = make_game(plat, cfg, str(WORK / plat / "frames"))
    try:
        action.make_char(g, cfg)
        g.trace = []
        skip = len(g.frames()) if plat == "apple2" else 0
        g.hold(1)
        action.action(g, cfg, 40 if plat == "apple2" else 48); g.hold(1)
        if plat == "apple2":
            out = WORK / "apple2" / "frames"; shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
            for i, f in enumerate(g.frames()[skip:]):
                Image.open(f).convert("RGB").resize((560, 384), Image.NEAREST).save(out / f"f{i:05d}.png")
            n = len(os.listdir(out)); out = str(out)
        else:
            out, n = g.dir, g.n
        split_encode(out, [n // 4, n // 2, 3 * n // 4], plat, fps=10)
    finally:
        t = getattr(g, 'trace', None)
        if t:
            moves = [p for i, p in enumerate(t) if i == 0 or p != t[i - 1]]
            back = sum(1 for i in range(2, len(moves)) if moves[i] == moves[i - 2])
            print(f"moves {len(moves)}, immediate reversals {back}"); print(moves)
        g.close()

if __name__ == "__main__":
    main()

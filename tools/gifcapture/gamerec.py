import sys, re; sys.path.insert(0,'.')
from rec import *
from explore import explore
from lvl import gen_wait
import numpy as np

from paths import ASSETS
GIFDIR = str(ASSETS)

def choose(g, label):
    """press the menu letter whose line contains `label` (e.g. 'ROGUE')."""
    for l in g.text():
        m = re.search(r"\b([A-Z])\) " + label, l)
        if m: g.key(m.group(1), 0); return m.group(1)
    raise RuntimeError("menu entry not found: " + label)

def art_visible(f):
    a = np.asarray(f.crop((136,51,456,251)))
    return ((a[:,:,0]>150)&(a[:,:,1]>110)&(a[:,:,2]<90)).sum() > 3000

def attempt(cfg):
    g = cfg.get("cls", Game)(cfg["cmd"], cfg["port"], cfg["out"], cfg["crop"], cfg["scr"], fps=cfg.get("fps", 10))
    g.v.vic = cfg.get("vic", True)
    g.scale = cfg.get("scale")
    try:
        if cfg.get("art"):
            while True:
                f = g.v.frame()
                if f is not None and art_visible(f): break
                time.sleep(0.2)
            g.hold(5)
        marks = []
        g.wait("N)EW")
        if hasattr(g, "patch"): g.patch()
        g.hold(2)
        g.key("N");  g.wait("CHOOSE YOUR RACE"); g.hold(1.5)
        choose(g, cfg["race"]);  g.wait("ROLL STATISTICS"); g.hold(1)
        g.key("R", 1); g.key("R", 1)
        g.key("\r"); g.wait("CHOOSE YOUR CLASS"); g.hold(1.5)
        choose(g, cfg["klass"]);  g.wait("ENTER YOUR NAME"); g.hold(0.6)
        for ch in cfg["name"]: g.key(ch, 0.3)
        g.key("\r"); g.wait("CHOOSE YOUR SEX"); g.hold(1)
        g.key(cfg.get("sex", "A"));  g.wait("CHARACTER INFO"); g.hold(2.5)
        g.key(" ");  g.wait("WELCOME TO MORIA"); g.hold(1.5)
        marks.append(g.n)
        if cfg.get("creation_only"):
            encode(cfg["out"], f"{GIFDIR}/moria8-{cfg['plat']}-gameplay-1.gif", fps=cfg.get("fps", 10))
            if cfg.get("after"): cfg["after"](g)
            return True
        for _ in range(4):
            goto(g, '1234567')
            if not g.has("DL:"): break
        time.sleep(0.5); g.hold(2.0)
        for _ in range(3):
            if g.has("DL:"): break
            g.key("Q", 0.7)
        for _ in range(4):
            goto(g, '>', maxsteps=60); g.key(">", 0.3)
            if not g.has("DL:0"): break
        if g.has("SLAIN") or g.has("DIED"): raise RuntimeError("died in town")
        gen_wait(g, "DL:1")
        marks.append(g.n)
        for _ in range(6):
            r = explore(g, 0.1, first_closed=True)
            if r != 'closed': break
            g.key("<"); gen_wait(g, "DL:0"); g.key(">"); gen_wait(g, "DL:1")
        g.hold(1.2)
        def dungeon(secs):
            n0 = g.n
            for _ in range(4):
                ok = explore(g, secs - (g.n - n0) / g.fps)
                if ok is True or ok is False: break
                goto(g, '<'); g.key("<"); gen_wait(g, "DL:0"); g.key(">"); gen_wait(g, "DL:1")
            if not ok or g.has("SLAIN") or g.has("DIED"): raise RuntimeError("low hp / died")
        dungeon(cfg.get("dungeon_secs", 14)); marks.append(g.n)
        dungeon(cfg.get("dungeon_secs", 14))
        g.hold(1)
        from split import split_encode
        split_encode(cfg["out"], marks, cfg["plat"], fps=cfg.get("fps", 10))
        return True
    finally:
        print("frames", g.n)
        g.close()

def run(cfg, tries=6):
    for i in range(tries):
        try:
            if attempt(cfg): return
        except Exception as e:
            print("attempt", i, "failed:", e)

import sys, re, time, os; sys.path.insert(0,'.')
from rec import *
from explore import hp, explore
from gamerec import choose
from split import split_encode

def pause(g, s=0.5):
    # let the emulated machine run a bit without capturing
    if hasattr(g, "v"): time.sleep(s)
    else: g.rpc(f"WAIT {s * 0.25}")

def settle(g, secs):
    """let slow work (map reveal, level build) finish without capturing"""
    if hasattr(g, "v"):
        g.v.warp(True); time.sleep(secs); g.v.warp(False); time.sleep(0.6)
    else:
        g.rpc(f"WAIT {secs * 4}")

def wiz_open(g):
    for _ in range(20):
        rows = g.text()
        if any("Q TO CANCEL" in l for l in rows): return True
        if g.more(rows): continue
        if any("WIZARD?" in l for l in rows): g.key("Y"); pause(g); continue
        g.ctrl("W"); pause(g, 0.7)
    raise RuntimeError("wizard menu did not open\n" + "\n".join(g.text()))

def wiz(g, key, arg=None):
    wiz_open(g); g.key(key); pause(g, 0.6)
    if key == "A": settle(g, 6)
    if arg is not None:
        for ch in arg: g.key(ch); pause(g, 0.2)
        g.key("\r"); pause(g, 0.6)
    for _ in range(6):
        rows = g.text()
        if g.more(rows): continue
        if any("Q TO CANCEL" in l for l in rows): g.key("Q"); pause(g, 0.4); continue
        break

def gen_to(g, dl):
    g.xs = None
    if hasattr(g, "wait_gen"): g.wait_gen(dl)
    else:
        from lvl import gen_wait; gen_wait(g, dl)

def make_char(g, cfg):
    g.quiet = True
    g.wait("N)EW")
    if hasattr(g, "patch"): g.patch()
    g.key("N");  g.wait("CHOOSE YOUR RACE")
    choose(g, cfg["race"]);  g.wait("ROLL STATISTICS")
    g.key("\r"); g.wait("CHOOSE YOUR CLASS")
    choose(g, cfg["klass"]);  g.wait("ENTER YOUR NAME")
    for ch in cfg["name"]: g.key(ch); pause(g, 0.15)
    g.key("\r"); g.wait("CHOOSE YOUR SEX")
    g.key(cfg.get("sex", "A"));  g.wait("CHARACTER INFO")
    g.key(" ");  g.wait("WELCOME TO MORIA")
    wizard_setup(g, cfg)
    g.quiet = False

def wizard_setup(g, cfg):
    """From the town: raise the character to cfg['level'], jump to cfg['dl'], full heal."""
    for _ in range(cfg["level"] - 1):
        wiz(g, "X")
    wiz(g, "L", str(cfg["dl"]))
    gen_to(g, "DL:" + str(cfg["dl"]))
    wiz(g, "H")
    wiz(g, "A")          # reveal the level so the character can travel instead of groping in the dark
    g.reveal = True
    g.key(" "); pause(g, 0.4)     # clear the wizard's OK message

def action(g, cfg, secs):
    """explore + fight; wizard-summon monsters periodically and heal when hurt (uncaptured)."""
    n_end = g.n + secs * g.fps
    last_summon = g.n
    last_heal = [-999]
    def heal():
        # don't let healing starve the fight: at most one heal per ~1.5 s unless nearly dead
        h = hp(g.text())
        if h and h[0] > h[1] * 0.3 and g.n - last_heal[0] < 15:
            return False
        last_heal[0] = g.n
        q = g.quiet; g.quiet = True; wiz(g, "H"); g.quiet = q
        return True
    g.on_low = heal
    while g.n < n_end:
        rows = g.text()
        if any(k in l for l in rows for k in ('SLAIN', 'DISK SETUP')): raise RuntimeError('character died')
        busy = any(ch.isalpha() and ch != '@' and ch not in 'EM' for l in rows[1:21] for ch in l)
        if not busy and g.n - last_summon > cfg.get("summon_every", 6) * g.fps:
            g.quiet = True; wiz(g, "S"); g.quiet = False
            last_summon = g.n
        r = explore(g, 3, minfrac=cfg.get('minfrac', 0.75))
        if r == 'stuck':
            g.quiet = True; wiz(g, "T"); g.quiet = False

def run_action(g, cfg):
    make_char(g, cfg)
    g.hold(1)
    action(g, cfg, cfg.get("secs", 48))
    g.hold(1)

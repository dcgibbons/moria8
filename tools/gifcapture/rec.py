import sys, os, socket, subprocess, time, random, struct, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcap import *
from PIL import Image

DIRS = {(-1,-1):'Y',(0,-1):'K',(1,-1):'U',(-1,0):'H',(1,0):'L',(-1,1):'B',(0,1):'J',(1,1):'N'}

class Game:
    """Drives one VICE instance: capture frames, send keys, read screen text."""
    def __init__(self, cmd, port, outdir, crop, scr, fps=12):
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.v = object.__new__(Vice); self.v.rid = 1; self.v.pal = None
        for _ in range(150):
            try: self.v.s = socket.create_connection(("127.0.0.1", port)); break
            except OSError: time.sleep(0.2)
        self.v._req(0xaa)
        self.trail = set()
        self.dir, self.crop, self.fps, self.n = outdir, crop, fps, 0
        self.scr = scr          # (base, cols, rows)
        os.makedirs(outdir, exist_ok=True)
        for f in os.listdir(outdir): os.remove(os.path.join(outdir, f))
    def text(self):
        return screen_text(self.v, *self.scr)
    def has(self, s):
        return any(s in l for l in self.text())
    def shot(self):
        if getattr(self, 'quiet', False): return
        f = self.v.frame()
        if f is not None:
            f = f.crop(self.crop)
            if getattr(self, "scale", None): f = f.resize(self.scale, Image.NEAREST)
            f.save(f"{self.dir}/f{self.n:05d}.png"); self.n += 1
    def hold(self, secs):
        t0 = time.time(); nxt = t0
        while time.time() - t0 < secs:
            self.shot(); nxt += 1 / self.fps
            d = nxt - time.time()
            if d > 0: time.sleep(d)
    def _send(self, k):
        self.v.req(0x72, bytes([len(k)]) + k.encode("latin1"))
    def key(self, k, after=0.0):
        self._send(k)
        if after: self.hold(after)
    def step(self, k, maxw=0.7):
        """send key, capture frames until the screen text changes (or maxw)."""
        before = self.text()
        self._send(k)
        t0 = time.time(); nxt = t0
        while time.time() - t0 < maxw:
            self.shot(); nxt += 1 / self.fps
            d = nxt - time.time()
            if d > 0: time.sleep(d)
            if self.text() != before and time.time() - t0 > 0.12: break
    def enter_wait(self):
        self.v.warp(True); t0 = time.time()
        while time.time() - t0 < 30 and any("DL:" in l for l in self.text()): time.sleep(0.2)
        time.sleep(0.5); self.v.warp(False); time.sleep(0.6)
    def pos(self):
        """player map coordinates (zp_player_x/y at $2B/$2C on every platform)"""
        d = self.v.req(0x01, struct.pack("<BHHBH", 0, 0x2B, 0x2C, 0, 0))[1]
        return (d[2], d[3])
    def ctrl(self, ch):
        self._send(chr(ord(ch) - 64))
    def more(self, rows=None):
        rows = rows or self.text()
        if any("-MORE-" in l for l in rows):
            self.key(" ", 0.25); return True
        return False
    def wait(self, s, maxw=90, quiet=0.6):
        """warp (no capture) until text s is on screen and stable."""
        self.v.warp(True); t0 = time.time(); ok = False
        while time.time() - t0 < maxw:
            if self.has(s): ok = True; break
            time.sleep(0.15)
        time.sleep(quiet)
        self.v.warp(False); time.sleep(0.7)
        if not ok: self.v.frame().save("fail.png"); raise RuntimeError("timeout waiting for " + s + "\n" + "\n".join(self.text()))
    def close(self):
        try: self.proc.kill()
        except Exception: pass

def encode(outdir, out, fps=10, width=-1):
    avi = outdir + ".mkv"
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-framerate",str(fps),
                    "-i",f"{outdir}/f%05d.png","-vf","pad=iw:trunc(iw*3/4/2)*2:0:(oh-ih)/2:black","-c:v","ffv1",avi], check=True)
    from paths import ROOT
    subprocess.run([f"{ROOT}/tools/make_gameplay_gif.sh", avi, out, "0", "", str(width)], check=True, env={**os.environ, "FPS": str(fps)})

from collections import deque
def bfs_dir(rows, target, r0=1, r1=21, walk=".", avoid="", extra=()):
    """first step direction from '@' toward nearest `target` glyph over walkable glyphs."""
    me = None
    for r in range(r0, r1):
        c = rows[r].find('@')
        if c >= 0: me = (c, r); break
    if me is None: return None
    prev = {me: None}; q = deque([me])
    while q:
        p = q.popleft()
        if p != me and rows[p[1]][p[0]] in target:
            while prev[p] != me: p = prev[p]
            return (p[0]-me[0], p[1]-me[1])
        for d in DIRS:
            n = (p[0]+d[0], p[1]+d[1])
            if n in prev or not (r0 <= n[1] < r1) or not (0 <= n[0] < len(rows[n[1]])): continue
            ch = rows[n[1]][n[0]]
            if ch in target or ch in walk or n in extra:
                prev[n] = p; q.append(n)
    return None

import string
def goto(g, target, hold=0.15, maxsteps=150):
    for _ in range(maxsteps):
        rs = g.text()
        if g.more(rs): continue
        d = bfs_dir(rs, target, walk=".", extra=g.trail) or bfs_dir(rs, target, walk="." + string.ascii_letters.replace('@',''), extra=g.trail)
        if d is None: return False
        me = None
        for r in range(1, 21):
            c = rs[r].find('@')
            if c >= 0: me = (c, r); break
        enters = me and rs[me[1]+d[1]][me[0]+d[0]] in target and target != ">"
        g.step(DIRS[d])
        if enters:
            g.enter_wait()
            return True
    return False


class InjectGame(Game):
    """C128: the game reads the CIA matrix directly, so patch cia_scan_petscii to
    `lda VAR; rts` and drive VAR from the monitor instead of feeding the KERNAL buffer."""
    ENTRY = 0x27D1
    VAR = 0x27D5
    def patched(self):
        d = self.v.req(0x01, struct.pack("<BHHBH", 0, self.ENTRY, self.ENTRY + 3, 0, 0))[1][2:]
        return d[0] == 0xAD
    def patch(self):
        e, d = self.v.req(0x01, struct.pack("<BHHBH", 0, self.ENTRY, self.ENTRY + 3, 0, 0))
        assert d[2:6] == bytes([0x08, 0x78, 0xA9, 0xFF]), d.hex()
        self.poke(self.VAR, [0])
        self.poke(self.ENTRY, [0xAD, self.VAR & 255, self.VAR >> 8, 0x60])
    def poke(self, addr, data):
        self.v.req(0x02, struct.pack("<BHHBH", 0, addr, addr + len(data) - 1, 0, 0) + bytes(data))
    def dwell(self, secs):
        t0 = time.time(); nxt = t0
        while time.time() - t0 < secs:
            self.shot(); nxt += 1 / self.fps
            d = nxt - time.time()
            if d > 0: time.sleep(d)
    def _send(self, k):
        if not self.patched() and self.v.req(0x01, struct.pack("<BHHBH", 0, self.ENTRY, self.ENTRY + 3, 0, 0))[1][2:6] == bytes([0x08, 0x78, 0xA9, 0xFF]): self.patch()
        for ch in k:
            self.poke(self.VAR, [ord(ch)]); self.dwell(0.14)
            self.poke(self.VAR, [0]); self.dwell(0.1)

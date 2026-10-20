import os, subprocess, time, glob, shutil
from rec import DIRS

from paths import A2ROMS as ROM, BUILD
IMG = str(BUILD / "moria8-apple2.po")

class MameGame:
    def __init__(self, work, fps=10):
        work = os.path.abspath(work); self.work = work; self.fps = fps; self.n = 0; self.trail = set()
        shutil.rmtree(work, ignore_errors=True)
        for d in ("cfg","nv","inp","sta","snap"): os.makedirs(f"{work}/{d}")
        self.cmdf = f"{work}/cmd.txt"; self.respf = f"{work}/resp.txt"
        lua = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "rpc.lua")).read()
        lua = lua.replace("STARTFILE", f"{work}/started.txt").replace("CMDFILE", self.cmdf).replace("RESPFILE", self.respf)
        open(f"{work}/rpc.lua", "w").write(lua)
        env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
        cmd = ["mame","apple2ee","-rompath",ROM,
            "-cfg_directory",f"{work}/cfg","-nvram_directory",f"{work}/nv","-input_directory",f"{work}/inp",
            "-state_directory",f"{work}/sta","-snapshot_directory",f"{work}/snap","-flop1",IMG,
            "-autoboot_script",f"{work}/rpc.lua","-video","soft","-sound","none","-nothrottle",
            "-seconds_to_run","299"]
        for attempt in range(8):
            try: os.remove(f"{work}/started.txt")
            except FileNotFoundError: pass
            self.proc = subprocess.Popen(cmd, env=env, stdout=open(f"{work}/out.txt","w"), stderr=subprocess.STDOUT)
            t0 = time.time()
            while time.time() - t0 < 6 and not os.path.exists(f"{work}/started.txt"): time.sleep(0.1)
            if os.path.exists(f"{work}/started.txt"): break
            self.proc.kill(); self.proc.wait(); time.sleep(1)
        else:
            raise RuntimeError("mame lua script never started")
    def rpc(self, line, timeout=300):
        try: os.remove(self.respf)
        except FileNotFoundError: pass
        tmp = self.cmdf + ".w"
        open(tmp, "w").write(line + "\n"); os.rename(tmp, self.cmdf)
        t0 = time.time()
        while time.time() - t0 < timeout:
            if os.path.exists(self.respf):
                s = open(self.respf).read()
                if s.endswith("END\n"): return s[:-5]
            time.sleep(0.01)
        raise RuntimeError("rpc timeout: " + line)
    def text(self):
        return [l.upper() for l in self.rpc("TEXT").split("\n")]
    def has(self, s): return any(s in l for l in self.text())
    def _k(self, k):
        m = {"\r":"RET"," ":"SPC","\x1b":"ESC"}
        return m.get(k, k)
    def key(self, k, after=0.0):
        if k in "<>": self.rpc("SHIFT " + {"<":",",">":"."}[k])
        else: self.rpc("KEY " + self._k(k))
        if after: self.hold(after)
    def hold(self, secs):
        if getattr(self, 'quiet', False):
            self.rpc(f"WAIT {secs}"); return
        n = max(1, round(secs * self.fps))
        self.rpc(f"SNAP {n} {1/self.fps}"); self.n += n
    def step(self, k, maxw=0.7):
        before = len(glob.glob(f"{self.work}/snap/apple2ee/*.png"))
        if k in "<>":
            self.rpc("SHIFT " + {"<":",",">":"."}[k]); self.hold(0.3)
        else:
            self.rpc(f"STEP {self._k(k)} {maxw}")
        self.n += len(glob.glob(f"{self.work}/snap/apple2ee/*.png")) - before
    def pos(self):
        a, b = self.rpc("ZP").split()
        return (int(a), int(b))
    def ctrl(self, ch):
        self.rpc("CTRL " + ch)
    def more(self, rows=None):
        rows = rows or self.text()
        if any("-MORE-" in l for l in rows):
            self.key(" ", 0.25); return True
        return False
    def wait(self, s, maxw=120, quiet=0.3):
        t0 = time.time()
        while time.time() - t0 < maxw:
            if self.has(s):
                self.rpc(f"WAIT {quiet}"); return
            self.rpc("WAIT 0.5")
        raise RuntimeError("timeout waiting for " + s + "\n" + "\n".join(self.text()))
    def enter_wait(self):
        t0 = time.time()
        while time.time() - t0 < 60 and any("DL:" in l for l in self.text()): self.rpc("WAIT 0.5")
        self.rpc("WAIT 0.5")
    def wait_gen(self, dl):
        t0 = time.time()
        while time.time() - t0 < 120:
            rows = self.text()
            if not any("GENERATING" in l for l in rows) and any(dl in l for l in rows): break
            self.rpc("WAIT 0.5")
        self.trail.clear()
    def frames(self):
        return sorted(glob.glob(f"{self.work}/snap/apple2ee/*.png"))
    def close(self):
        try: self.rpc("QUIT", timeout=5)
        except Exception: pass
        try: self.proc.kill()
        except Exception: pass

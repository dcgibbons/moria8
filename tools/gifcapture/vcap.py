import socket, struct, subprocess, time, os, sys
from PIL import Image

class Vice:
    def __init__(self, cmd, port):
        self.p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.rid = 1
        for _ in range(100):
            try:
                self.s = socket.create_connection(("127.0.0.1", port)); break
            except OSError: time.sleep(0.2)
        self.pal = None
        self.req(0xaa)
    def _rd(self, n):
        b = b""
        while len(b) < n:
            c = self.s.recv(n - len(b))
            if not c: raise EOFError
            b += c
        return b
    def req(self, cmd, body=b""):
        r = self._req(cmd, body)
        if cmd != 0xaa: self._req(0xaa)
        return r
    def _req(self, cmd, body=b""):
        self.rid += 1
        self.s.sendall(struct.pack("<BBIIB", 2, 2, len(body), self.rid, cmd) + body)
        while True:
            h = self._rd(12)
            _, _, ln, typ, err, rid = struct.unpack("<BBIBBI", h)
            data = self._rd(ln)
            if rid == self.rid: return err, data
    def keys(self, text):
        # chunks of 8, wait for kbd buffer to drain
        for i in range(0, len(text), 8):
            t = text[i:i+8].encode("latin1")
            self.req(0x72, bytes([len(t)]) + t)
            time.sleep(0.15)
    def warp(self, on):
        name = b"Speed"
        self.req(0x52, bytes([1, len(name)]) + name + bytes([4]) + struct.pack("<I", 10000 if on else 100))
    def frame(self):
        if self.pal is None:
            _, d = self.req(0x91, bytes([1 if getattr(self, "vic", True) else 0]))
            n = struct.unpack("<H", d[:2])[0]; o = 2; pal = []
            for _ in range(n):
                l = d[o]; pal += list(d[o+1:o+4]); o += 1 + l
            self.pal = pal
        _, d = self.req(0x84, bytes([1 if getattr(self, "vic", True) else 0, 0]))
        il = struct.unpack("<I", d[:4])[0]
        dw, dh, xo, yo, iw, ih, bpp = struct.unpack("<HHHHHHB", d[4:17])
        bl = struct.unpack("<I", d[4+il:8+il])[0]
        buf = d[-bl:]
        if len(buf) != dw*dh: return None
        im = Image.frombytes("P", (dw, dh), buf)
        im.putpalette(self.pal + [0]*(768-len(self.pal)))
        self.geo = (dw, dh, xo, yo, iw, ih)
        return im.convert("RGB")
    def close(self):
        try: self.p.kill()
        except Exception: pass

class Rec:
    def __init__(self, v, outdir, fps=12):
        self.v, self.dir, self.fps, self.n = v, outdir, fps, 0
        os.makedirs(outdir, exist_ok=True)
        for f in os.listdir(outdir): os.remove(os.path.join(outdir, f))
    def run(self, secs, keys=None, kdelay=0.0):
        """capture for secs real-time at fps; feed keys string (chars sent one per kdelay s)."""
        t0 = time.time(); nxt = t0; ki = 0; lastk = t0
        while time.time() - t0 < secs:
            if keys and ki < len(keys) and time.time() - lastk >= kdelay:
                self.v.req(0x72, bytes([1]) + keys[ki].encode("latin1")); ki += 1; lastk = time.time()
            fr = self.v.frame()
            if fr is not None: fr.save(f"{self.dir}/f{self.n:05d}.png"); self.n += 1
            nxt += 1 / self.fps
            d = nxt - time.time()
            if d > 0: time.sleep(d)

def settle(v, quiet=2.0, maxw=60):
    """warp until the frame stops changing for `quiet` real seconds."""
    import hashlib
    v.warp(True); last=None; t_last=time.time(); t0=time.time()
    while time.time()-t0 < maxw:
        f=v.frame()
        h=hashlib.md5(f.tobytes()).hexdigest() if f else None
        if h!=last: last=h; t_last=time.time()
        elif time.time()-t_last>=quiet: break
        time.sleep(0.2)
    v.warp(False); time.sleep(0.6)

def screen_text(v, base=0x0400, cols=40, rows=25, bank=0):
    e, d = v.req(0x01, struct.pack("<BHHBH", 0, base, base + cols*rows - 1, 0, bank))
    n = struct.unpack("<H", d[:2])[0]; b = d[2:2+n]
    out = []
    for r in range(rows):
        s = ""
        for c in range(cols):
            x = b[r*cols+c] & 0x7f
            s += chr(x + 64) if x < 32 else chr(x) if x < 96 else "?"
        out.append(s)
    return out

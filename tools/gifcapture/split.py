import os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rec import encode
from paths import ASSETS
GIF = str(ASSETS) + "/"
def split_encode(frames_dir, marks, plat, fps=10, first=1, trim=6):
    """Cut frames into len(marks)+1 clips (marks = frame counts ending each clip but the last),
    written as moria8-<plat>-gameplay-<first..>.gif.  The first `trim` frames are dropped:
    they still show the wizard's "OK" message."""
    fs = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))[trim:]
    marks = [m - trim for m in marks]
    bounds = [0] + list(marks) + [len(fs)]
    for i in range(len(bounds) - 1):
        d = f"{frames_dir}_clip{first+i}"
        shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
        for j, f in enumerate(fs[bounds[i]:bounds[i+1]]):
            shutil.copy(os.path.join(frames_dir, f), f"{d}/f{j:05d}.png")
        encode(d, GIF + f"moria8-{plat}-gameplay-{first+i}.gif", fps=fps)

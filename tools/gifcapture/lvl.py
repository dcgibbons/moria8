import time
def gen_wait(g, dl):
    g.trail.clear()
    g.v.warp(True); t0=time.time()
    while time.time()-t0<60:
        if not g.has("GENERATING") and g.has(dl): break
        time.sleep(0.2)
    g.v.warp(False); time.sleep(0.6)
def fresh_level(g, explore_fn, probe_secs=0.0):
    """re-roll level 1 via < and > (uncaptured) until the arrival room has an exit."""
    return

import re, random
from collections import deque
from rec import DIRS

AVOID = 'EM'  # floating eyes paralyze and molds never move; don't melee them
FLOOR = ".'/+$!?=_|\\([]{}~&*,-"
ITEMS = "$!?=_|\\([]{}~&*,"

# orthogonal moves first so equal-length paths run straight rather than stair-stepping
ORDER = [(0, -1), (1, 0), (0, 1), (-1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]

def hp(rows):
    for l in rows:
        m = re.search(r"HP:\s*(\d+)/\s*(\d+)", l)
        if m: return int(m.group(1)), int(m.group(2))
    return None

class _State:
    def __init__(self):
        self.goal = None; self.bad = set(); self.recent = deque(maxlen=8)
        self.waits = 0; self.mons = set(); self.visited = set(); self.nogoal = 0
        self.probe = None; self.probe_from = None; self.lastwp = None; self.fight = 0

def explore(g, secs, r0=2, r1=21, minfrac=0.5, first_closed=False):
    """Walk like a person: commit to one goal at a time, fight what is adjacent, let moving
    monsters come to us, never shuffle back and forth.  Returns True when time is up,
    False if HP is low (no heal hook), 'closed' / 'stuck' when there is nowhere to go."""
    st = getattr(g, "xs", None) or _State(); g.xs = st
    n0 = g.n; first = True
    while g.n - n0 < secs * g.fps:
        rows = g.text()
        if g.more(rows): continue
        h = hp(rows)
        if any(k in l for l in rows for k in ('TOO AFRAID', 'BLINDS YOU', 'YOU ARE BLIND', 'CONFUSED')) and getattr(g, 'on_low', None):
            if g.on_low(): continue
        if h and h[0] < h[1] * minfrac:
            if getattr(g, "on_low", None):
                if g.on_low(): continue
            else:
                return False
        W = len(rows[0])
        grid = {(c, r): rows[r][c] for r in range(r0, r1) for c in range(W)}
        me = next((p for p, ch in grid.items() if ch == '@'), None)
        if me is None: g.key(" ", 0.3); continue
        wp = g.pos(); off = (wp[0] - me[0], wp[1] - me[1])
        def W_(p): return (p[0] + off[0], p[1] + off[1])
        st.visited.add(wp); g.trail.add(me)
        if getattr(g, 'trace', None) is not None: g.trace.append(wp)

        def at(d): return grid.get((me[0] + d[0], me[1] + d[1]), ' ')
        # 1. melee: strike whatever is adjacent, preferring the first in a fixed order
        adj = [d for d in ORDER if at(d).isalpha() and at(d) not in AVOID]
        if adj:
            st.waits = 0; st.goal = None; st.fight += 1
            if st.fight > 14: st.fight = 0; return 'stuck'   # a slog: break off and relocate
            st.lastwp = wp
            g.step(DIRS[adj[0]]); continue

        if not adj: st.fight = 0
        mons = {p for p, ch in grid.items() if ch.isalpha() and ch != '@' and ch not in AVOID}
        near = [p for p in mons if max(abs(p[0] - me[0]), abs(p[1] - me[1])) <= 6]
        moving = bool(near) and not ({W_(p) for p in near} <= st.mons)
        st.mons = {W_(p) for p in mons}
        # 2. something is coming: stand and let it arrive instead of chasing it around
        if near and moving and st.waits < 5:
            st.waits += 1; g.key(".", 0.3); continue
        if not near: st.waits = 0

        danger = {(p[0] + dx, p[1] + dy) for p, ch in grid.items() if ch in AVOID for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
        def walkable(ch): return ch in FLOOR or (ch.isalpha() and ch not in AVOID)
        def is_goal(p):
            ch = grid.get(p, ' ')
            if p == me or W_(p) in st.bad: return False
            if (ch.isalpha() and ch not in AVOID) or ch in ITEMS: return True
            if ch in ".'" and W_(p) not in st.visited:
                for d in ORDER:
                    n = (p[0] + d[0], p[1] + d[1])
                    if grid.get(n, '#') == ' ' and r0 < n[1] < r1 - 1 and 0 < n[0] < W - 1: return True
            return False

        # BFS from me; remember parents so we can walk any chosen goal
        prev = {me: None}; dist = {me: 0}; q = deque([me]); order = []
        while q:
            p = q.popleft(); order.append(p)
            for d in ORDER:
                n = (p[0] + d[0], p[1] + d[1])
                if n in prev or n not in grid or n in danger: continue
                if walkable(grid[n]): prev[n] = p; dist[n] = dist[p] + 1; q.append(n)
        # 3. keep the committed goal while it is still valid and reachable
        sg = None if st.goal is None else (st.goal[0] - off[0], st.goal[1] - off[1])
        if getattr(g, "reveal", False):
            # whole level is mapped: travel purposefully between items and far-off spots
            if sg == me: st.bad.add(st.goal); sg = None; st.goal = None
            ok_goal = sg is not None and sg in prev and W_(sg) not in st.bad
            if not ok_goal:
                items = [p for p in order if grid[p] in ITEMS and W_(p) not in st.bad]
                far = [p for p in order if 8 <= dist[p] <= 40 and grid[p] == '.' and W_(p) not in st.bad]
                hd = (wp[0] - st.lastwp[0], wp[1] - st.lastwp[1]) if st.lastwp else (0, 0)
                ahead = [p for p in far if (p[0] - me[0]) * hd[0] + (p[1] - me[1]) * hd[1] > 0]
                nxt = items[0] if items else (random.choice(ahead or far) if far else None)
                st.goal = None if nxt is None else W_(nxt); sg = nxt
        elif sg is None or sg not in prev or not is_goal(sg):
            nxt = next((p for p in order if is_goal(p)), None)
            st.goal = None if nxt is None else W_(nxt)
            sg = nxt
        if first and first_closed and st.goal is None: return 'closed'
        first = False
        if sg is None and st.probe_from is not None and wp == st.probe_from and st.probe is not None:
            st.bad.add(st.probe)            # bumped into an unseen wall
        st.probe = None
        if sg is None:
            # dark corridor ahead: the floor is not drawn until we stand on it, so feel forward
            head = (wp[0] - st.lastwp[0], wp[1] - st.lastwp[1]) if st.lastwp else (0, 0)
            cand = [d for d in ORDER if at(d) == ' ' and W_((me[0] + d[0], me[1] + d[1])) not in st.bad
                    and W_((me[0] + d[0], me[1] + d[1])) not in st.visited
                    and r0 < me[1] + d[1] < r1 - 1 and 0 < me[0] + d[0] < W - 1]
            if cand:
                d = max(cand, key=lambda d: (d[0] * head[0] + d[1] * head[1], d in ORDER[:4]))
                st.probe = W_((me[0] + d[0], me[1] + d[1])); st.probe_from = wp; st.lastwp = wp
                g.step(DIRS[d]); continue
        if sg is None:
            st.nogoal += 1
            if st.nogoal >= 2: st.nogoal = 0; st.bad.clear(); st.visited.clear(); return 'stuck'
            g.key(" ", 0.3); continue
        st.nogoal = 0
        # 4. dithering guard: revisiting a recent square means this goal is not working out
        st.recent.append(wp)
        if list(st.recent).count(wp) >= 3:
            st.bad.add(st.goal); st.goal = None; st.recent.clear(); continue
        p = sg
        while prev[p] != me: p = prev[p]
        st.lastwp = wp
        g.step(DIRS[(p[0] - me[0], p[1] - me[1])])
    return True

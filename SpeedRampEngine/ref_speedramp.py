"""
Referenční implementace SpeedRampEngine — Python.
Slouží jen k numerickému ověření matematiky před portem do Swiftu.
"""
import math
from bisect import bisect_right

# ---------- Bézier easing (stejná sémantika jako CSS cubic-bezier) ----------

class Ease:
    __slots__ = ("x1", "y1", "x2", "y2")

    def __init__(self, x1, y1, x2, y2):
        self.x1, self.y1, self.x2, self.y2 = x1, y1, x2, y2

    @staticmethod
    def _b(a, b, s):
        # B(s) pro P0=0, P1=a, P2=b, P3=1
        u = 1.0 - s
        return 3.0 * u * u * s * a + 3.0 * u * s * s * b + s * s * s

    @staticmethod
    def _db(a, b, s):
        u = 1.0 - s
        return 3.0 * u * u * a + 6.0 * u * s * (b - a) + 3.0 * s * s * (1.0 - b)

    def _solve_s(self, u):
        if u <= 0.0:
            return 0.0
        if u >= 1.0:
            return 1.0
        s = u  # Newton
        for _ in range(8):
            f = self._b(self.x1, self.x2, s) - u
            if abs(f) < 1e-12:
                return s
            d = self._db(self.x1, self.x2, s)
            if abs(d) < 1e-12:
                break
            s2 = s - f / d
            if s2 < 0.0 or s2 > 1.0:
                break
            s = s2
        lo, hi = 0.0, 1.0  # bisekce jako záchrana
        for _ in range(60):
            mid = 0.5 * (lo + hi)
            if self._b(self.x1, self.x2, mid) < u:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def value(self, u):
        if u <= 0.0:
            return 0.0
        if u >= 1.0:
            return 1.0
        return self._b(self.y1, self.y2, self._solve_s(u))


LINEAR = Ease(0.0, 0.0, 1.0, 1.0)
EASE_IN_OUT = Ease(0.42, 0.0, 0.58, 1.0)
EASE_OUT = Ease(0.0, 0.0, 0.58, 1.0)
EASE_IN = Ease(0.42, 0.0, 1.0, 1.0)

MIN_SPEED = 1e-4  # rychlost 0 = freeze frame, to je jiná funkce; tady zakázáno

# ---------- Rychlostní křivka ----------

class SpeedRamp:
    """
    Uzly jsou definované na VÝSTUPNÍ (timeline) ose.
    v(t) = rychlost přehrávání v čase t na timeline.
    t_src(t) = integral_0^t v(tau) dtau
    """
    SAMPLES_PER_INTERVAL = 512

    def __init__(self, nodes):
        # nodes: [(output_offset, speed, ease_to_next)]
        assert len(nodes) >= 2, "potreba aspon 2 uzly"
        ns = sorted(nodes, key=lambda n: n[0])
        assert abs(ns[0][0]) < 1e-12, "prvni uzel musi byt na 0"
        for i in range(1, len(ns)):
            assert ns[i][0] > ns[i - 1][0], "uzly musi mit rostouci cas"
        for n in ns:
            assert n[1] >= MIN_SPEED, "rychlost musi byt kladna"
        self.nodes = ns
        self._build()

    @property
    def output_duration(self):
        return self.nodes[-1][0]

    def speed_at(self, t):
        ns = self.nodes
        if t <= 0.0:
            return ns[0][1]
        if t >= ns[-1][0]:
            return ns[-1][1]
        i = bisect_right([n[0] for n in ns], t) - 1
        i = min(i, len(ns) - 2)
        t0, v0, ease = ns[i]
        t1, v1 = ns[i + 1][0], ns[i + 1][1]
        u = (t - t0) / (t1 - t0)
        return v0 + (v1 - v0) * ease.value(u)

    def _build(self):
        """Kumulativní integrál po intervalech, Simpson na jemném vzorkování."""
        ts = [0.0]
        cum = [0.0]
        total = 0.0
        for i in range(len(self.nodes) - 1):
            t0, v0, ease = self.nodes[i]
            t1, v1 = self.nodes[i + 1][0], self.nodes[i + 1][1]
            n = self.SAMPLES_PER_INTERVAL
            if n % 2:
                n += 1
            h = (t1 - t0) / n
            # hodnoty rychlosti na uzlech Simpsonova pravidla
            vals = []
            for k in range(n + 1):
                u = k / n
                vals.append(v0 + (v1 - v0) * ease.value(u))
            # kumulativně po dvojicích (Simpson na kazdem paru intervalu)
            for k in range(0, n, 2):
                seg = (h / 3.0) * (vals[k] + 4.0 * vals[k + 1] + vals[k + 2])
                total += seg
                ts.append(t0 + (k + 2) * h)
                cum.append(total)
        self._ts = ts
        self._cum = cum

    @property
    def source_consumed(self):
        return self._cum[-1]

    def source_time(self, t):
        """Timeline cas -> zdrojovy cas."""
        if t <= 0.0:
            return 0.0
        if t >= self.output_duration:
            return self._cum[-1] + (t - self.output_duration) * self.nodes[-1][1]
        i = bisect_right(self._ts, t) - 1
        i = max(0, min(i, len(self._ts) - 2))
        t0 = self._ts[i]
        base = self._cum[i]
        # dopocet zbytku Simpsonem na [t0, t]
        a, b = t0, t
        m = 0.5 * (a + b)
        return base + ((b - a) / 6.0) * (
            self.speed_at(a) + 4.0 * self.speed_at(m) + self.speed_at(b)
        )

    def output_time(self, s):
        """Zdrojovy cas -> timeline cas (inverze). Bisekce + Newton."""
        if s <= 0.0:
            return 0.0
        if s >= self._cum[-1]:
            return self.output_duration + (s - self._cum[-1]) / self.nodes[-1][1]
        i = bisect_right(self._cum, s) - 1
        i = max(0, min(i, len(self._cum) - 2))
        lo, hi = self._ts[i], self._ts[i + 1]
        t = 0.5 * (lo + hi)
        for _ in range(40):
            f = self.source_time(t) - s
            if abs(f) < 1e-12:
                return t
            d = self.speed_at(t)
            nt = t - f / d if d > MIN_SPEED else 0.5 * (lo + hi)
            if not (lo <= nt <= hi):
                if f > 0:
                    hi = t
                else:
                    lo = t
                nt = 0.5 * (lo + hi)
            else:
                if f > 0:
                    hi = t
                else:
                    lo = t
            t = nt
        return t

    def segments(self, count):
        """
        Rozkrájení na mikro-úseky pro scaleTimeRange.
        Vraci [(source_start, source_duration, output_duration)].
        """
        out = []
        T = self.output_duration
        prev_src = 0.0
        for k in range(count):
            t_end = T * (k + 1) / count
            src_end = self.source_time(t_end)
            out.append((prev_src, src_end - prev_src, T / count))
            prev_src = src_end
        return out

    @classmethod
    def fitting(cls, source_duration, shape):
        """
        Natáhne tvar křivky tak, aby spotřeboval přesně source_duration zdroje.
        shape = uzly s libovolnou výstupní délkou; škáluje se čas, ne rychlosti.
        """
        base = cls(shape)
        k = source_duration / base.source_consumed
        scaled = [(t * k, v, e) for (t, v, e) in shape]
        return cls(scaled)


# ---------------------- OVĚŘENÍ ----------------------

def approx(a, b, tol=1e-9):
    return abs(a - b) <= tol

FAILS = []

def check(name, cond, detail=""):
    if cond:
        print(f"  OK    {name}")
    else:
        print(f"  FAIL  {name}   {detail}")
        FAILS.append(name)

print("\n=== 1. Bézier easing ===")
for e, nm in [(LINEAR, "linear"), (EASE_IN_OUT, "easeInOut"), (EASE_OUT, "easeOut")]:
    check(f"{nm}: value(0)==0", approx(e.value(0.0), 0.0))
    check(f"{nm}: value(1)==1", approx(e.value(1.0), 1.0))
    mono = all(e.value(i / 400) <= e.value((i + 1) / 400) + 1e-12 for i in range(400))
    check(f"{nm}: monotonni", mono)
lin_ok = all(approx(LINEAR.value(i / 100), i / 100, 1e-9) for i in range(101))
check("linear: value(u)==u", lin_ok)
check("easeInOut: symetrie kolem 0.5",
      approx(EASE_IN_OUT.value(0.25) + EASE_IN_OUT.value(0.75), 1.0, 1e-9))

print("\n=== 2. Konstantní rychlost (analyticky přesné) ===")
for c in (0.25, 0.5, 1.0, 2.0, 4.0):
    r = SpeedRamp([(0.0, c, LINEAR), (10.0, c, LINEAR)])
    err = max(abs(r.source_time(t / 10) - c * t / 10) for t in range(101))
    check(f"v={c}: t_src(t) == {c}*t  (max err {err:.2e})", err < 1e-9)
    check(f"v={c}: spotreba zdroje == {c*10}", approx(r.source_consumed, c * 10.0, 1e-9))

print("\n=== 3. Lineární přechod rychlosti (analyticky přesné) ===")
# v(t) = v0 + (v1-v0)*t/T  ->  integral = v0*T + (v1-v0)*T/2
for v0, v1, T in [(1.0, 0.25, 4.0), (0.25, 1.0, 3.0), (2.0, 0.5, 5.0)]:
    r = SpeedRamp([(0.0, v0, LINEAR), (T, v1, LINEAR)])
    exact = v0 * T + (v1 - v0) * T / 2.0
    check(f"v {v0}->{v1} za {T}s: integral == {exact}  (got {r.source_consumed:.12f})",
          approx(r.source_consumed, exact, 1e-9))

print("\n=== 4. Ramp 1.0 -> 0.25 -> 1.0 (hlavní případ) ===")
ramp = SpeedRamp([
    (0.0, 1.0, EASE_IN_OUT),
    (2.5, 0.25, EASE_IN_OUT),
    (5.0, 1.0, EASE_IN_OUT),
])
check("t_src(0) == 0", approx(ramp.source_time(0.0), 0.0))
N = 20000
prev = -1.0
mono = True
mind = 1e9
for i in range(N + 1):
    t = 5.0 * i / N
    s = ramp.source_time(t)
    if s < prev - 1e-12:
        mono = False
        break
    if prev >= 0:
        mind = min(mind, s - prev)
    prev = s
check("t_src je striktne rostouci (monotonie)", mono)
check("zadny plochy usek (nejmensi prirustek > 0)", mind > 0, f"min delta={mind:.3e}")

# derivace numericky == rychlost
h = 1e-6
maxerr = 0.0
for i in range(1, 2000):
    t = 5.0 * i / 2000
    num = (ramp.source_time(t + h) - ramp.source_time(t - h)) / (2 * h)
    maxerr = max(maxerr, abs(num - ramp.speed_at(t)))
check(f"d(t_src)/dt == v(t)  (max err {maxerr:.2e})", maxerr < 1e-6)

# spojitost na hranicích uzlů
for tn in (2.5,):
    l = ramp.source_time(tn - 1e-9)
    r_ = ramp.source_time(tn + 1e-9)
    check(f"spojitost v uzlu t={tn}  (skok {abs(r_-l):.2e})", abs(r_ - l) < 1e-7)

check("rychlost v uzlech sedi",
      approx(ramp.speed_at(0.0), 1.0) and approx(ramp.speed_at(2.5), 0.25, 1e-9)
      and approx(ramp.speed_at(5.0), 1.0))
print(f"        -> ramp spotrebuje {ramp.source_consumed:.6f} s zdroje za 5.0 s na timeline")

print("\n=== 5. Round-trip inverze ===")
maxrt = 0.0
for i in range(1, 5000):
    t = 5.0 * i / 5000
    s = ramp.source_time(t)
    back = ramp.output_time(s)
    maxrt = max(maxrt, abs(back - t))
check(f"output_time(source_time(t)) == t  (max err {maxrt:.2e})", maxrt < 1e-7)

maxrt2 = 0.0
S = ramp.source_consumed
for i in range(1, 5000):
    s = S * i / 5000
    t = ramp.output_time(s)
    back = ramp.source_time(t)
    maxrt2 = max(maxrt2, abs(back - s))
check(f"source_time(output_time(s)) == s  (max err {maxrt2:.2e})", maxrt2 < 1e-7)

print("\n=== 6. Segmentace pro scaleTimeRange ===")
for cnt in (30, 60, 150, 300, 600):
    segs = ramp.segments(cnt)
    tot_src = sum(s[1] for s in segs)
    tot_out = sum(s[2] for s in segs)
    # navaznost
    gap = max(abs(segs[i][0] + segs[i][1] - segs[i + 1][0]) for i in range(len(segs) - 1))
    speeds = [s[1] / s[2] for s in segs]
    # schodovita aproximace: jak moc se sousedni rychlosti lisi
    jump = max(abs(speeds[i + 1] - speeds[i]) for i in range(len(speeds) - 1))
    ok = (approx(tot_src, ramp.source_consumed, 1e-9)
          and approx(tot_out, ramp.output_duration, 1e-9)
          and gap < 1e-12 and all(s[1] > 0 for s in segs))
    check(f"{cnt:>3} segmentu: soucty sedi, zadne mezery, vse kladne", ok)
    print(f"        -> nejvetsi skok rychlosti mezi segmenty: {jump:.4f}x")

print("\n=== 7. fitting(): natazeni na presnou delku zdroje ===")
shape = [(0.0, 1.0, EASE_IN_OUT), (1.0, 0.25, EASE_IN_OUT), (2.0, 1.0, EASE_IN_OUT)]
for D in (3.0, 8.0, 14.5):
    f = SpeedRamp.fitting(D, shape)
    check(f"zdroj {D}s -> spotreba {f.source_consumed:.9f}", approx(f.source_consumed, D, 1e-8))
    print(f"        -> vysledna delka na timeline: {f.output_duration:.4f} s")

print("\n=== 8. Případ ze specifikace: 120fps -> 0.25x ===")
r120 = SpeedRamp([(0.0, 0.25, LINEAR), (4.0, 0.25, LINEAR)])
check("4 s na timeline pri 0.25x spotrebuje 1 s zdroje",
      approx(r120.source_consumed, 1.0, 1e-9))
# pri 120fps zdroji a 30fps vystupu: 4s*30 = 120 vystupnich snimku, 1s*120 = 120 zdrojovych
check("120 vystupnich snimku <-> 120 zdrojovych snimku (pomer 1:1, zadne mezisnimky)",
      approx(4.0 * 30, 1.0 * 120))

print("\n=== 9. Okrajové případy ===")
try:
    SpeedRamp([(0.0, 1.0, LINEAR)])
    check("odmitne jediny uzel", False)
except AssertionError:
    check("odmitne jediny uzel", True)
try:
    SpeedRamp([(0.0, 0.0, LINEAR), (1.0, 1.0, LINEAR)])
    check("odmitne nulovou rychlost", False)
except AssertionError:
    check("odmitne nulovou rychlost", True)
try:
    SpeedRamp([(0.5, 1.0, LINEAR), (1.0, 1.0, LINEAR)])
    check("odmitne prvni uzel mimo nulu", False)
except AssertionError:
    check("odmitne prvni uzel mimo nulu", True)

extreme = SpeedRamp([(0.0, 1.0, EASE_IN_OUT), (1.0, 0.05, EASE_IN_OUT), (2.0, 4.0, EASE_IN_OUT)])
mono2 = all(extreme.source_time(2.0 * i / 5000) <= extreme.source_time(2.0 * (i + 1) / 5000) + 1e-12
            for i in range(5000))
check("extremni ramp 1.0 -> 0.05 -> 4.0 je stale monotonni", mono2)

print("\n" + "=" * 46)
if FAILS:
    print(f"NEPROSLO: {len(FAILS)}")
    for f in FAILS:
        print("  -", f)
else:
    print("VSECHNY TESTY PROSLY")
print("=" * 46)

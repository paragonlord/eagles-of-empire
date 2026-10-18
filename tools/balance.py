#!/usr/bin/env python3
"""AI-vs-AI balance pass over every scenario (tools/balance.luau drives the sim headless).

Usage: tools/balance.py [--seeds 5] [--jobs 4] [--difficulties easy,normal,hard] [--only jena,...]
                        [--md docs/balance.md]
Every (scenario, difficulty, seed) is played for the scenario's time limit (40 min for full
battles) with both sides under the same AI difficulty. Prints a per-scenario table and the
degenerate outcomes it flags (see docs/balance.md for the thresholds).
"""
import argparse
import collections
import json
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import test as harness  # noqa: E402  (tools/test.py: bundle helpers)

ROOT = harness.ROOT
FULL_MINUTES = 40
EPISODE_MINUTES = 10
# player (France) is listed first; "lopsided" = history was a rout, a 100 % win rate is fine.
HISTORY = {
    "jena": ("france", "French victory (decisive)", True),
    "jena_landgrafenberg": ("france", "Closewitz and Cospeda taken", True),
    "jena_vierzehnheiligen": ("france", "village taken, Grawert's line shot to pieces", False),
    "auerstedt": ("france", "French victory (Davout outnumbered 2:1)", True),
    "auerstedt_hassenhausen": ("france", "Gudin held Hassenhausen", False),
    "auerstedt_spielberg": ("france", "Friant turned the Prussian left", False),
    "austerlitz": ("france", "French victory (decisive)", True),
    "austerlitz_pratzen": ("france", "Pratzen taken", False),
    "austerlitz_sokolnitz": ("france", "Telnitz/Sokolnitz held, allied left stuck", False),
    "waterloo": ("britain", "Allied victory (decisive)", True),
    "waterloo_hougoumont": ("britain", "Hougoumont held all day", False),
    "waterloo_lahayesainte": ("france", "La Haye Sainte fell", False),
}
FULL = [s for s in HISTORY if "_" not in s]


def bundle(jobs):
    prelude = (ROOT / "tools" / "prelude.luau").read_text(encoding="utf-8")
    sources = {k: v for k, v in harness.collect().items() if not k.startswith("Tests/")}
    driver = (ROOT / "tools" / "balance.luau").read_text(encoding="utf-8")
    table = "{" + ",".join(
        "{scenario=%s,difficulty=%s,seed=%d,minutes=%d}" % (json.dumps(j[0]), json.dumps(j[1]), j[2], j[3]) for j in jobs
    ) + "}"
    sources["Tests/balance"] = driver.replace("__JOBS__", table, 1)
    entries = ",\n".join(f"  [{json.dumps(k)}] = {harness.luau_string(v)}" for k, v in sources.items())
    out = prelude.replace("__SOURCES__", "{\n" + entries + "\n}", 1)
    return out.replace("__FILTER__", repr("[slow] balance"), 1)


def run(jobs, workers):
    luau = os.path.expanduser("~/.local/bin/luau")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    # round-robin so each worker gets a similar mix of long and short battles
    buckets = [jobs[i::workers] for i in range(workers)]
    procs = []
    for i, bucket in enumerate(buckets):
        if not bucket:
            continue
        p = build / f"balance_{i}.luau"
        p.write_text(bundle(bucket), encoding="utf-8")
        procs.append((p, subprocess.Popen([luau, "-O2", str(p)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)))
    rows = []
    for p, proc in procs:
        out, _ = proc.communicate()
        for line in out.splitlines():
            if line.startswith("BAL\t"):
                rows.append(parse(line.split("\t")[1:]))
            elif line.startswith("FAIL"):
                print(out, file=sys.stderr)
                raise SystemExit("balance run failed")
        p.unlink(missing_ok=True)
    return rows


def parse(c):
    def side(s):
        name, rest = s.split(":")
        deployed, cas, forms, routs, shat, lost = map(int, rest.split("/"))
        return dict(faction=name, deployed=deployed, casualties=cas, formations=forms, routs=routs, shattered=shat, lost=lost)

    return dict(
        scenario=c[0], difficulty=c[1], seed=int(c[2]), winner=c[3], reason=c[4], duration=float(c[5]),
        contact=float(c[6]) if c[6] else None, cannon=int(c[7]), charges=int(c[8]), flips=int(c[9]), contested=c[10] == "1",
        sides=[side(c[11]), side(c[12])],
    )


def summarize(rows):
    """Per (scenario, difficulty): aggregates + flags."""
    groups = collections.OrderedDict()
    for r in rows:
        groups.setdefault((r["scenario"], r["difficulty"]), []).append(r)
    out = []
    for (sc, diff), rs in groups.items():
        n = len(rs)
        hist_winner, hist_text, lopsided = HISTORY[sc]
        wins = collections.Counter(r["winner"] for r in rs)
        reasons = collections.Counter(r["reason"] for r in rs)
        dur = sum(r["duration"] for r in rs) / n
        contact = [r["contact"] for r in rs if r["contact"] is not None]
        cas = []
        shat = []
        for i in range(2):
            cas.append(sum(r["sides"][i]["casualties"] / max(1, r["sides"][i]["deployed"]) for r in rs) / n)
            shat.append(sum(r["sides"][i]["shattered"] / max(1, r["sides"][i]["formations"]) for r in rs) / n)
        routs = [sum(r["sides"][i]["routs"] for r in rs) / n for i in range(2)]
        lost = [sum(r["sides"][i]["lost"] for r in rs) / n for i in range(2)]
        factions = [rs[0]["sides"][0]["faction"], rs[0]["sides"][1]["faction"]]
        flags = []
        top, topN = wins.most_common(1)[0]
        if topN / n >= 0.9 and top != "draw" and not (lopsided and top == hist_winner):
            flags.append(f"{top} wins {topN}/{n}" + (" against history" if top != hist_winner else ""))
        if wins["draw"] / n >= 0.9:
            flags.append(f"draw {wins['draw']}/{n}")
        if dur < 240:
            flags.append(f"ends in {dur / 60:.1f} min")
        if len(contact) < n:
            flags.append(f"no contact in {n - len(contact)} seeds")
        for i in range(2):
            if cas[i] > 0.6:
                flags.append(f"{factions[i]} casualties {cas[i] * 100:.0f}%")
            if cas[i] < 0.05:
                flags.append(f"{factions[i]} casualties {cas[i] * 100:.0f}%")
            if shat[i] > 0.5:
                flags.append(f"{factions[i]} {shat[i] * 100:.0f}% of formations shattered")
        if all(r["cannon"] == 0 for r in rs):
            flags.append("artillery never fires")
        if all(r["charges"] == 0 for r in rs):
            flags.append("cavalry never charges")
        if not any(r["contested"] for r in rs) and not any(r["flips"] for r in rs):
            flags.append("objectives never contested")
        timeouts = sum(1 for r in rs if r["reason"].startswith("Time expired"))
        if sc not in FULL and timeouts == n and sum(r["flips"] for r in rs) == 0:
            flags.append("decided by the clock alone")
        out.append(dict(
            scenario=sc, difficulty=diff, n=n, wins=wins, reasons=reasons, duration=dur, contact=sum(contact) / len(contact) if contact else None,
            cas=cas, routs=routs, shat=shat, lost=lost, flips=sum(r["flips"] for r in rs) / n, cannon=sum(r["cannon"] for r in rs) / n,
            charges=sum(r["charges"] for r in rs) / n, factions=factions, history=hist_text, flags=flags,
        ))
    return out


def table(summary, md=False):
    head = ["scenario", "diff", "winner (n)", "reason", "min", "contact", "cas% F/E", "routs F/E", "shat F/E", "lost F/E", "flips", "guns", "charges", "history", "flags"]
    lines = []
    if md:
        lines.append("| " + " | ".join(head) + " |")
        lines.append("|" + "---|" * len(head))
    else:
        lines.append("\t".join(head))
    for s in summary:
        wins = " ".join(f"{k} {v}" for k, v in s["wins"].most_common())
        reason = s["reasons"].most_common(1)[0][0]
        cols = [
            s["scenario"], s["difficulty"], wins, reason, f"{s['duration'] / 60:.1f}",
            f"{s['contact'] / 60:.1f}" if s["contact"] is not None else "-",
            f"{s['cas'][0] * 100:.0f}/{s['cas'][1] * 100:.0f}", f"{s['routs'][0]:.1f}/{s['routs'][1]:.1f}",
            f"{s['shat'][0] * 100:.0f}%/{s['shat'][1] * 100:.0f}%", f"{s['lost'][0]:.1f}/{s['lost'][1]:.1f}",
            f"{s['flips']:.1f}", f"{s['cannon']:.0f}", f"{s['charges']:.1f}", s["history"], "; ".join(s["flags"]) or "-",
        ]
        lines.append(("| " + " | ".join(cols) + " |") if md else "\t".join(cols))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--difficulties", default="easy,normal,hard")
    ap.add_argument("--only", default=None)
    ap.add_argument("--md", default=None, help="write the table as Markdown to this file")
    args = ap.parse_args()
    scenarios = args.only.split(",") if args.only else list(HISTORY)
    jobs = [
        (sc, d, seed, FULL_MINUTES if sc in FULL else EPISODE_MINUTES)
        for sc in scenarios for d in args.difficulties.split(",") for seed in range(1, args.seeds + 1)
    ]
    # longest battles first so the round-robin spreads them
    jobs.sort(key=lambda j: -j[3])
    t0 = time.time()
    rows = run(jobs, args.jobs)
    summary = summarize(rows)
    print(table(summary))
    print(f"\n{len(rows)} battles in {time.time() - t0:.0f} s wall")
    flagged = [s for s in summary if s["flags"]]
    print(f"{len(flagged)} flagged:")
    for s in flagged:
        print(f"  {s['scenario']}/{s['difficulty']}: {'; '.join(s['flags'])}")
    if args.md:
        pathlib.Path(args.md).write_text(table(summary, md=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

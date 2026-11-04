#!/usr/bin/env python3
"""Generate and validate the Trailblazer Dash campaign.

Every level is generated here, at build time, and shipped as data. The game
replays that data verbatim, so the fairness validator and the runtime can never
drift apart: there is one definition of where each obstacle sits.

Usage:
    python3 Tools/campaign.py            # regenerate + validate
    python3 Tools/campaign.py --check    # validate the shipped file only
"""

from __future__ import annotations

import json
import math
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN_PATH = ROOT / "Resources" / "Campaign" / "campaign.json"
REPORT_PATH = ROOT / "Docs" / "CampaignValidation.md"
FIXTURE_PATH = ROOT / "Tests" / "fixtures" / "campaign_summary.json"

LEVELS_PER_REGION = 25
LANES = (-1, 0, 1)

# --- fairness constants (mirrored in Scripts/Track/TrackBuilder.gd) ----------
MIN_ROW_GAP_TIME = 0.95          # seconds between obstacle rows at current speed
MIN_ACTION_GAP_TIME = 1.05       # seconds between a jump row and a slide row
REACTION_BUDGET = 0.62           # seconds of clear road before the first row
STUMBLE_BUDGET = 2               # hits allowed before a run ends (3rd ends it)


@dataclass
class Region:
    id: int
    name: str
    tagline: str
    ground: str
    accent: str
    sky: str
    fog: str
    props: list[str]
    surface: str
    tempo: int
    root: int
    scale: str
    ambience: list[str]
    mix: list[str] = field(default_factory=list)   # obstacle mix tags
    landmark: str = "beacon"


REGION_ROWS = [
    # id, name, tagline, ground, accent, sky, fog, props, surface, tempo, root, scale, ambience, mix, landmark
    (1, "Sunmeadow Valley", "Where the Wayfinder path begins", "#6dbf5a", "#ffd166", "#9fd8ff", "#d9f0ff",
     ["tree_round", "rock_small", "fern"], "grass", 104, 60, "major", ["birds", "wind", "meadow"], ["hurdle", "block"], "banner"),
    (2, "Whisperwood Forest", "Old trees, older stories", "#3d7a4f", "#9ff5b8", "#8fc7c0", "#c8e8dd",
     ["tree_pine", "log", "mushroom"], "grass", 100, 57, "minor", ["forest", "leaves", "birds"], ["hurdle", "bar", "block"], "ruin_arch"),
    (3, "Riverstone Crossing", "Every bridge is a promise", "#5b7f8a", "#7fd8ff", "#a7d7ee", "#d6eef8",
     ["rock_big", "reed", "ruin_pillar"], "stone", 96, 62, "dorian", ["river", "water", "birds"], ["bar", "block", "mover"], "ruin_arch"),
    (4, "Golden Coast", "Salt air and long light", "#e8cf94", "#ffb44d", "#ffe0a8", "#fff0cf",
     ["palm", "rock_small", "banner"], "sand", 112, 64, "major", ["waves", "gulls", "coast"], ["hurdle", "block", "mover"], "banner"),
    (5, "Ember Canyon", "The rock remembers the fire", "#a8563a", "#ff8a4d", "#e9a07a", "#f6d1b8",
     ["rock_big", "obsidian", "ruin_pillar"], "rock", 118, 55, "phrygian", ["canyon", "wind", "rockfall"], ["bar", "block", "mover"], "ruin_pillar"),
    (6, "Cloudpeak Mountains", "A road drawn on the sky", "#93a9bf", "#dfefff", "#bcd6ee", "#e8f3ff",
     ["tree_pine", "rock_big", "ice_spire"], "stone", 92, 58, "major", ["alpine", "wind", "eagle"], ["bar", "hurdle", "block"], "banner"),
    (7, "Frostfall Highlands", "Quiet, until the ice sings", "#d9edf7", "#9fe8ff", "#cfe9ff", "#f2fbff",
     ["ice_spire", "tree_pine", "rock_small"], "snow", 88, 53, "minor", ["snow", "wind", "ice"], ["bar", "block", "mover"], "crystal"),
    (8, "Verdant Jungle", "The green keeps its own time", "#2f8f5f", "#9dff8a", "#8fe0b8", "#d3f7e0",
     ["palm", "fern", "ruin_arch"], "grass", 122, 61, "major", ["jungle", "insects", "water"], ["hurdle", "bar", "block"], "ruin_arch"),
    (9, "Clockwork City", "Every street is a mechanism", "#6f6355", "#ffc766", "#8a8f9e", "#d4cdbc",
     ["gear", "lamp_post", "timber_frame"], "metal", 128, 56, "dorian", ["machinery", "gears", "city"], ["block", "bar", "mover"], "gear"),
    (10, "Crystal Caverns", "Light gets lost down here", "#4b4270", "#b99cff", "#6b5fa8", "#cdc2ff",
     ["crystal", "rock_big", "obsidian"], "stone", 90, 51, "minor", ["cave", "drips", "resonance"], ["bar", "block", "mover"], "crystal"),
    (11, "Starlight Desert", "The dunes keep the sky's score", "#d9b978", "#fff1b8", "#f3d79a", "#fdf0cd",
     ["cactus", "ruin_pillar", "rock_small"], "sand", 108, 63, "major", ["desert", "wind", "night"], ["hurdle", "block", "mover"], "ruin_pillar"),
    (12, "Moonwater Marsh", "Follow the lanterns, not the lights", "#3f6f63", "#86ffd0", "#7fb4a8", "#d2efe6",
     ["reed", "fern", "ruin_pillar"], "mud", 84, 54, "dorian", ["marsh", "frogs", "water"], ["bar", "block", "hurdle"], "lantern"),
    (13, "Thunder Ridge", "Run between the flashes", "#5d6a7e", "#bcd6ff", "#8b9ab4", "#dbe6f7",
     ["rock_big", "obsidian", "lamp_post"], "rock", 132, 57, "phrygian", ["storm", "rain", "thunder"], ["block", "bar", "mover"], "pylon"),
    (14, "Skygarden Isles", "Mind the gap, admire the view", "#86c9a8", "#d8ffe8", "#a8d8f0", "#e4f7ff",
     ["topiary", "tree_round", "banner"], "grass", 110, 65, "major", ["altitude", "wind", "birds"], ["bar", "hurdle", "mover"], "banner"),
    (15, "Ironwood Frontier", "Built fast, built loud", "#8a6242", "#ffb066", "#c9a98a", "#f0ddc8",
     ["timber_frame", "crate", "gear"], "wood", 124, 59, "dorian", ["sawmill", "engines", "timber"], ["block", "bar", "mover"], "banner"),
    (16, "Sapphire Archipelago", "Seven islands, one road", "#8fbfc9", "#7fe0ff", "#a9e2f2", "#e0f6ff",
     ["palm", "rock_big", "banner"], "sand", 106, 66, "major", ["waves", "seabirds", "harbor"], ["hurdle", "block", "mover"], "ruin_arch"),
    (17, "Ashen Volcano", "Do not stop to admire it", "#53322f", "#ff6a3d", "#8a4a3a", "#d9a08a",
     ["obsidian", "rock_big", "lamp_post"], "rock", 136, 50, "phrygian", ["lava", "rumble", "steam"], ["bar", "block", "mover"], "beacon"),
    (18, "Celestial Gardens", "Grown by people who loved light", "#9d8fd0", "#ffe0ff", "#c6b8ee", "#efe6ff",
     ["topiary", "ruin_arch", "crystal"], "grass", 94, 68, "major", ["garden", "chimes", "wind"], ["hurdle", "bar", "block"], "lantern"),
    (19, "Forgotten Kingdom", "The Wayfinders were here first", "#7d7f8f", "#d7d9ff", "#a9adc4", "#e2e4f2",
     ["ruin_pillar", "ruin_arch", "statue"], "stone", 82, 52, "minor", ["ruins", "echo", "wind"], ["bar", "block", "mover"], "ruin_arch"),
    (20, "Heart of Avelora", "The last beacon is yours to light", "#c9a15a", "#ffd166", "#f0c98a", "#ffeec9",
     ["beacon", "crystal", "ruin_arch"], "stone", 140, 62, "major", ["aether", "wind", "choir"], ["block", "bar", "mover"], "beacon"),
]


def regions() -> list[Region]:
    out = []
    for row in REGION_ROWS:
        (rid, name, tagline, ground, accent, sky, fog, props, surface, tempo, root, scale,
         ambience, mix, landmark) = row
        out.append(Region(rid, name, tagline, ground, accent, sky, fog, props, surface,
                          tempo, root, scale, ambience, mix, landmark))
    return out


SPARK_NAMES = [
    "First Light", "Morning Sprint", "Wayfinder's Start", "Sunrise Steps", "Green Gate",
    "Long Meadow", "Windward", "Soft Landing", "Bright Path", "Beacon Glow",
    "Trail Warm", "Open Road", "High Grass", "Shy Horizon", "Kind Wind",
    "Lantern Run", "Bridge Song", "Far Hills", "Gold Hour", "First Relic",
    "Wide Sky", "New Route", "Stone Marker", "Last Light", "Wayfinder's Rest",
]


def level_name(region: Region, local: int) -> str:
    return SPARK_NAMES[local % len(SPARK_NAMES)]


POWER_POOL = [
    "magnet", "shield", "speed", "slow", "double_jump", "hover",
    "multiplier", "relic_finder", "long_slide", "lucky_spark",
]

OBSTACLE_WEIGHTS = {
    "hurdle": 0.34,
    "bar": 0.26,
    "block": 0.30,
    "mover": 0.10,
}


def speed_at(level: dict, z: float) -> float:
    a, b = level["spd"]
    t = max(0.0, min(1.0, z / max(1.0, level["len"])))
    # Ease-in: most of the climb happens in the back half of the run.
    return a + (b - a) * (t * t * (3 - 2 * t) * 0.55 + t * 0.45)


def row_gap(speed: float, rng: random.Random) -> float:
    base = max(16.0, speed * 1.15)
    return round(base + rng.uniform(0.5, 4.5), 2)


def route_for(level: dict) -> list[list[float]]:
    """The lane a runner takes when they always pick the nearest open lane.

    Sparks, relics and power-ups are placed on this route, and the validator
    walks the same function, so "reachable" is measured on a route that exists
    rather than on a best case across all three lanes.
    """
    lane = 0
    route: list[list[float]] = []
    for row in level["rows"]:
        free = [l for l in LANES if row["c"][l + 1] not in ("x", "m")]
        if not free:
            free = [lane]
        lane = min(free, key=lambda l: (abs(l - lane), l))
        route.append([row["z"], lane])
    return route


def lane_at_z(level: dict, z: float) -> int:
    lane = 0
    for row_z, row_lane in level["route"]:
        if row_z > z:
            break
        lane = int(row_lane)
    return lane


def generate_level(region: Region, local: int, number: int, seed: int) -> dict:
    rng = random.Random(seed)
    region_t = (region.id - 1) / 19.0
    difficulty = min(1.0, region_t * 0.78 + (local / 24.0) * 0.42)

    base = round(8.4 + region_t * 5.4 + local * 0.045, 2)
    top = round(base + 3.4, 2)
    length = int(min(880, 350 + region_t * 240 + local * 15))
    level = {
        "id": number,
        "region": region.id,
        "local": local + 1,
        "name": level_name(region, local),
        "seed": seed,
        "len": length,
        "spd": [base, top],
        "diff": round(difficulty, 3),
        "rows": [],
        "sparks": [],
        "powers": [],
        "relics": [],
        "pools": [],
        "beacon": {"z": length - 12, "need": 0},
    }

    # Obstacle rows ---------------------------------------------------------
    z = length * 0.09 + 14.0
    reachable = {0}
    last_action_z = -999.0
    rows: list[dict] = []
    row_count_target = int(9 + difficulty * 18 + rng.randint(0, 3))
    while len(rows) < row_count_target and z < length - 30:
        speed = speed_at(level, z)
        gap = row_gap(speed, rng)
        kind_roll = rng.random()
        # Early regions: mostly one obstacle. Later: more two-lane pressure.
        two_lane = kind_roll < (0.12 + difficulty * 0.42) and len(rows) > 3

        pickable = [k for k in ("hurdle", "bar", "block", "mover") if k in region.mix]
        weights = [OBSTACLE_WEIGHTS[k] for k in pickable]
        kind = rng.choices(pickable, weights=weights, k=1)[0]
        if "block" not in pickable:
            kind = "block"

        # Keep jump/slide rows far enough apart to be fair at speed.
        if kind in ("hurdle", "bar") and (z - last_action_z) < speed * MIN_ACTION_GAP_TIME:
            kind = "block" if difficulty > 0.3 else "hurdle"
            if kind == "hurdle" and (z - last_action_z) < speed * MIN_ACTION_GAP_TIME:
                kind = "block"

        cells = ["", "", ""]
        if kind == "hurdle":
            lane = rng.choice(list(LANES))
            cells[lane + 1] = "h"
            if two_lane and rng.random() < 0.55:
                cells[rng.choice([l for l in LANES if l != lane]) + 1] = "h"
        elif kind == "bar":
            lane = rng.choice(list(LANES))
            cells[lane + 1] = "b"
            if two_lane and rng.random() < 0.5:
                cells[rng.choice([l for l in LANES if l != lane]) + 1] = "b"
        elif kind == "mover":
            lane = rng.choice(list(LANES))
            cells[lane + 1] = "m"
        else:
            blocked = [rng.choice(list(LANES))] if not two_lane else rng.sample(list(LANES), 2)
            for lane in blocked:
                cells[lane + 1] = "x"

        free = {lane for lane in LANES if cells[lane + 1] not in ("x", "m")}
        if not free:
            # Never submit an all-blocked row: clear one lane and use a hurdle.
            lane = rng.choice(list(LANES))
            cells[lane + 1] = "h"
            free = set(LANES)
        # The player must be able to reach a free lane from where they can be.
        if not (free & reachable):
            lane = min(reachable, key=lambda l: (abs(l), rng.random()))
            cells[lane + 1] = ""
            free.add(lane)

        if kind in ("hurdle", "bar"):
            last_action_z = z

        rows.append({"z": round(z, 2), "c": cells})
        new_reachable = set()
        for lane in free:
            for d in (-1, 0, 1):
                if lane + d in LANES and lane + d in free:
                    new_reachable.add(lane + d)
        reachable = new_reachable or free
        z += gap

    level["rows"] = rows
    level["route"] = [[round(row_z, 1), int(row_lane)] for row_z, row_lane in route_for(level)]

    # Spark chains, laid along the route so every one of them is collectable.
    spark_rng = random.Random(seed ^ 0x5F37)
    sparks: list[list[float]] = []
    z = 30.0
    while z < length - 20:
        count = spark_rng.randint(4, 8)
        sparks.append([round(z, 1), lane_at_z(level, z), count])
        z += 26 + spark_rng.uniform(2, 14)
    level["sparks"] = sparks
    max_sparks = sum(s[2] for s in sparks)

    # Power-up crates -------------------------------------------------------
    pools = spark_rng.sample(POWER_POOL, k=min(len(POWER_POOL), 5 if region.id < 4 else 6))
    level["pools"] = pools
    powers = []
    z = 60.0
    idx = 0
    while z < length - 60:
        powers.append([round(z, 1), lane_at_z(level, z), pools[idx % len(pools)]])
        idx += 1
        z += 118 + spark_rng.uniform(0, 55)
    level["powers"] = powers

    # Relics ---------------------------------------------------------------
    relic_count = 2 if local < 6 else 3
    relic_z = [length * 0.36, length * 0.62, length * 0.84][:relic_count]
    level["relics"] = [[round(z + spark_rng.uniform(-6, 6), 1), lane_at_z(level, z)]
                       for z in relic_z]

    # Objective and stars ---------------------------------------------------
    target = int(max_sparks * (0.42 + 0.16 * difficulty))
    objective_kind = "sparks"
    if local in (7, 16) and region.id % 3 == 0:
        objective_kind = "relics"
    elif local == 12 and region.id % 4 == 0:
        objective_kind = "clean"
    elif local == 22:
        objective_kind = "time"
    level["obj"] = {"t": objective_kind, "n": target if objective_kind == "sparks" else relic_count}

    three_kind = "clean" if local % 3 == 0 else ("relics" if local % 3 == 1 else "time")
    three_n = relic_count if three_kind == "relics" else 0
    level["star"] = {"sparks": int(max_sparks * 0.72), "three": three_kind, "n": three_n}
    level["hits"] = STUMBLE_BUDGET
    level["dur"] = round(length / ((base + top) * 0.5), 1)
    level["max_sparks"] = max_sparks
    return level


def validate_level(level: dict, region: Region) -> tuple[bool, list[str], dict]:
    """Deterministic fairness + completability check over the shipped data."""
    problems: list[str] = []
    rows = level["rows"]
    if not rows:
        problems.append("no obstacle rows")

    prev_z = 0.0
    last_action_z = -999.0
    reachable = {0}
    min_reaction = 99.0
    for row in rows:
        z = row["z"]
        cells = row["c"]
        if len(cells) != 3:
            problems.append(f"row at {z} does not have three lanes")
        free = {lane for lane in LANES if cells[lane + 1] not in ("x", "m")}
        if not free:
            problems.append(f"row at {z} blocks every lane")
        speed = speed_at(level, z)
        reaction = (z - prev_z) / max(0.001, speed)
        min_reaction = min(min_reaction, reaction)
        if reaction < MIN_ROW_GAP_TIME:
            problems.append(f"row at {z} arrives {reaction:.2f}s after the last (min {MIN_ROW_GAP_TIME})")
        if not (free & reachable):
            problems.append(f"row at {z} leaves no lane reachable from the previous row")
        if any(cells[lane + 1] in ("h", "b") for lane in LANES):
            if z - last_action_z < speed * MIN_ACTION_GAP_TIME:
                problems.append(f"jump/slide at {z} is too close to the previous one at {last_action_z}")
            last_action_z = z
        new_reachable = set()
        for lane in free:
            for d in (-1, 0, 1):
                if lane + d in LANES and lane + d in free:
                    new_reachable.add(lane + d)
        reachable = new_reachable or free
        prev_z = z

    # Sparks: every chain is placed on the route, so the route collects all of them.
    # Verifying that here also catches any future generator change that moves a
    # chain off the route without updating the route data.
    collected = 0
    off_route = 0
    for z, spark_lane, count in level["sparks"]:
        if lane_at_z(level, z) == spark_lane:
            collected += count
        else:
            off_route += 1
    if off_route:
        problems.append(f"{off_route} spark chains sit off the validated route")
    level["_collected"] = collected
    if level["obj"]["t"] == "sparks" and collected < level["obj"]["n"]:
        problems.append(f"objective wants {level['obj']['n']} sparks, route can reach {collected}")
    if level["star"]["sparks"] > collected:
        problems.append(f"two-star spark target {level['star']['sparks']} exceeds reachable {collected}")

    relics = level["relics"]
    if len(relics) < 2:
        problems.append("fewer than two relics")
    if level["obj"]["t"] == "relics" and len(relics) < level["obj"]["n"]:
        problems.append("relic objective cannot be satisfied")
    for z, _lane in relics:
        if not (10 < z < level["len"] - 8):
            problems.append(f"relic at {z} is outside the running section")

    if level["len"] < 200:
        problems.append("level too short to be a real run")
    if level["dur"] > 120:
        problems.append(f"level takes {level['dur']}s (over the 120s budget)")

    powers = level["powers"]
    if not powers:
        problems.append("no power-up crates")
    for z, lane_index, power in powers:
        if power not in POWER_POOL:
            problems.append(f"unknown power-up {power}")
        if lane_index not in LANES:
            problems.append("power-up crate outside the lanes")
        if lane_at_z(level, z) != lane_index:
            problems.append(f"power-up at {z} is not on the route")

    # Beacon needs to be collectible from the sparks on the route.
    level["beacon"]["need"] = int(collected * 0.55)

    stats = {
        "rows": len(rows),
        "obstacles": sum(1 for r in rows for c in r["c"] if c),
        "sparks": sum(s[2] for s in level["sparks"]),
        "reachable_sparks": collected,
        "powers": len(powers),
        "relics": len(relics),
        "min_reaction_s": round(min_reaction, 2),
        "duration_s": level["dur"],
    }
    return (not problems), problems, stats


def build(verbose: bool = True) -> dict:
    regions_list = regions()
    levels: list[dict] = []
    report_rows: list[dict] = []
    rejected = 0
    retries_total = 0
    number = 1

    for region in regions_list:
        for local in range(LEVELS_PER_REGION):
            base_seed = 1_000_003 * number + region.id * 7919 + local * 104_729
            accepted = None
            problems: list[str] = []
            stats: dict = {}
            attempt = 0
            for attempt in range(26):
                seed = base_seed + attempt * 65_537
                candidate = generate_level(region, local, number, seed)
                ok, problems, stats = validate_level(candidate, region)
                if ok:
                    accepted = candidate
                    break
            if accepted is None:
                rejected += 1
                accepted = generate_level(region, local, number, base_seed)
                ok, problems, stats = validate_level(accepted, region)
                accepted["invalid"] = True
            retries_total += attempt
            levels.append(accepted)
            report_rows.append({
                "id": number,
                "region": region.id,
                "seed": accepted["seed"],
                "status": "REJECTED" if accepted.get("invalid") else "VERIFIED",
                "retries": attempt,
                "stats": stats,
                "problems": problems,
            })
            number += 1

    campaign = {
        "version": 1,
        "levels_per_region": LEVELS_PER_REGION,
        "regions": [
            {
                "id": r.id,
                "name": r.name,
                "tagline": r.tagline,
                "ground": r.ground,
                "accent": r.accent,
                "sky": r.sky,
                "fog": r.fog,
                "props": r.props,
                "surface": r.surface,
                "tempo": r.tempo,
                "root": r.root,
                "scale": r.scale,
                "ambience": r.ambience,
                "landmark": r.landmark,
            }
            for r in regions_list
        ],
        "levels": levels,
    }

    CAMPAIGN_PATH.parent.mkdir(parents=True, exist_ok=True)
    CAMPAIGN_PATH.write_text(json.dumps(campaign, separators=(",", ":")))

    verified = sum(1 for r in report_rows if r["status"] == "VERIFIED")
    summary = {
        "levels": len(levels),
        "verified": verified,
        "rejected": rejected,
        "regions": len(regions_list),
        "retries": retries_total,
        "bytes": CAMPAIGN_PATH.stat().st_size,
        "levels_per_region": LEVELS_PER_REGION,
    }
    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(json.dumps(summary, indent=2) + "\n")

    write_report(report_rows, summary)
    if verbose:
        print(f"{len(levels)} levels, {verified} VERIFIED, {rejected} REJECTED, "
              f"{retries_total} regeneration retries, {summary['bytes']/1024:.0f} KiB")
    return summary


def write_report(rows: list[dict], summary: dict) -> None:
    by_region: dict[int, list[dict]] = {}
    for row in rows:
        by_region.setdefault(row["region"], []).append(row)

    lines = [
        "# Campaign validation",
        "",
        "Generated by `Tools/campaign.py`. The game replays these exact rows, so",
        "this report describes the shipped levels rather than an approximation.",
        "",
        f"- Levels: **{summary['levels']}** across **{summary['regions']}** regions",
        f"- Verified: **{summary['verified']}**",
        f"- Rejected: **{summary['rejected']}**",
        f"- Regeneration retries: **{summary['retries']}**",
        f"- Payload: **{summary['bytes'] / 1024:.0f} KiB**",
        "",
        "## Rules checked",
        "",
        f"- Every obstacle row leaves at least one open lane.",
        f"- Row spacing is at least **{MIN_ROW_GAP_TIME:.2f}s** of travel at that point in the run.",
        f"- Jump and slide rows are at least **{MIN_ACTION_GAP_TIME:.2f}s** apart.",
        "- The open lane in each row is reachable from the open lane of the previous row,",
        "  so no row requires crossing two lanes in one gap.",
        "- Spark and two-star targets are reachable by a greedy route through the open lanes.",
        "- Relic and power-up placements sit inside the running section.",
        "- Every level finishes inside the 120 second budget.",
        "",
        "## Per region",
        "",
        "| Region | Levels | Verified | Rows | Obstacles | Sparks | Power-ups | Relics | Min gap (s) |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for region_id in sorted(by_region):
        group = by_region[region_id]
        ok = sum(1 for r in group if r["status"] == "VERIFIED")
        stats = group[0]["stats"]
        avg = lambda key: sum(r["stats"].get(key, 0) for r in group) / max(1, len(group))
        lines.append(
            f"| {region_id}. {regions()[region_id - 1].name} | {len(group)} | {ok} | "
            f"{avg('rows'):.0f} | {avg('obstacles'):.0f} | {avg('reachable_sparks'):.0f} | "
            f"{avg('powers'):.1f} | {avg('relics'):.1f} | {min(r['stats'].get('min_reaction_s', 9) for r in group):.2f} |"
        )

    problems = [r for r in rows if r["status"] != "VERIFIED"]
    lines += ["", "## Rejected levels", ""]
    if problems:
        for row in problems:
            lines.append(f"- Level {row['id']} (region {row['region']}): {'; '.join(row['problems'])}")
    else:
        lines.append("None. Every level passed every rule above.")
    lines.append("")
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(lines))


def check() -> int:
    if not CAMPAIGN_PATH.exists():
        print("campaign.json is missing; run Tools/campaign.py", file=sys.stderr)
        return 1
    campaign = json.loads(CAMPAIGN_PATH.read_text())
    regions_list = regions()
    failures = 0
    for level in campaign["levels"]:
        region = regions_list[level["region"] - 1]
        ok, problems, _stats = validate_level(level, region)
        if not ok:
            failures += 1
            print(f"level {level['id']}: {'; '.join(problems)}", file=sys.stderr)
    total = len(campaign["levels"])
    if total != 500:
        failures += 1
        print(f"expected 500 levels, found {total}", file=sys.stderr)
    for region in regions_list:
        count = sum(1 for level in campaign["levels"] if level["region"] == region.id)
        if count != LEVELS_PER_REGION:
            failures += 1
            print(f"region {region.id} has {count} levels", file=sys.stderr)
    print(f"checked {total} levels, {failures} problems")
    return 1 if failures else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(check())
    summary = build()
    sys.exit(0 if summary["rejected"] == 0 else 1)

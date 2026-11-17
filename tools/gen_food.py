# /// script
# requires-python = ">=3.11"
# ///
"""Generate Data/Food.lua from the game's data tables on wago.tools.

Usage:
    uv run tools/gen_food.py              # newest wowf build
    uv run tools/gen_food.py --build 1.60.1.70959

The output lists every food and drink item with what it restores over its full
duration and the level it needs, plus the effects (auras) the eating bar
watches for.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import tempfile
import urllib.request
from collections import defaultdict
from pathlib import Path

PRODUCT = "wowf"
BASE = "https://wago.tools"
TABLES = (
    "Item",
    "ItemSparse",
    "ItemEffect",
    "ItemXItemEffect",
    "SpellEffect",
    "SpellInterrupts",
    "SpellMisc",
    "SpellDuration",
    "SpellCastingRequirements",
    "SpellName",
)

# SpellEffect.Effect
APPLY_AURA = 6
# SpellEffect.EffectAura
AURA_REGEN_HEALTH = 84  # flat health every 5 seconds
AURA_REGEN_POWER = 85  # flat power every 5 seconds
AURA_PCT_HEALTH = 20  # percent of maximum health every period
AURA_PCT_POWER = 21  # percent of maximum power every period
POWER_MANA = 0
# SpellInterrupts.AuraInterruptFlags_0: the aura ends when you stand up.
# This bit is what separates food and drink from elixirs that restore mana.
NOT_SEATED = 0x40000
# Item.ClassID values that are never eaten: raw fish are trade goods here.
CLASS_TRADE_GOODS = 7
CLASS_QUEST = 12
JUNK_NAME = re.compile(r"deprecated|unused|\btest\b|\bold\b|\[ph\]|\bdnt\b|^zz", re.IGNORECASE)
# Two raw fish are filed as consumables instead of trade goods: Raw Winter
# Squid and Large Raw Mightfish. A name test would also catch Raw Black
# Truffle, which is vendor food, so they are listed by ID.
RAW_FISH_CONSUMABLES = {13755, 13893}
TRIGGER_DEPTH = 3

csv.field_size_limit(10**9)


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read()


def newest_build() -> str:
    builds = json.loads(fetch(f"{BASE}/api/builds"))
    return builds[PRODUCT][0]["version"]


def load_tables(build: str) -> dict[str, list[dict[str, str]]]:
    cache = Path(tempfile.gettempdir()) / "biscuitbreak-db2" / build
    cache.mkdir(parents=True, exist_ok=True)
    tables = {}
    for name in TABLES:
        path = cache / f"{name}.csv"
        if not path.exists():
            print(f"  downloading {name}", file=sys.stderr)
            path.write_bytes(fetch(f"{BASE}/db2/{name}/csv?build={build}"))
        with open(path, newline="", encoding="utf-8") as handle:
            tables[name] = list(csv.DictReader(handle))
        if not tables[name]:
            raise SystemExit(f"{name} is empty for build {build}")
    return tables


def base_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Rows for the normal difficulty only."""
    return [row for row in rows if int(row.get("DifficultyID", 0) or 0) == 0]


class Data:
    def __init__(self, tables: dict[str, list[dict[str, str]]]):
        self.spell_names = {int(r["ID"]): r["Name_lang"] for r in tables["SpellName"]}
        self.effects: dict[int, list[dict[str, str]]] = defaultdict(list)
        for row in base_rows(tables["SpellEffect"]):
            self.effects[int(row["SpellID"])].append(row)
        self.interrupt_flags = {
            int(r["SpellID"]): int(r["AuraInterruptFlags_0"]) for r in base_rows(tables["SpellInterrupts"])
        }
        durations = {int(r["ID"]): int(r["Duration"]) for r in tables["SpellDuration"]}
        self.duration = {
            int(r["SpellID"]): durations.get(int(r["DurationIndex"]), 0) / 1000 for r in base_rows(tables["SpellMisc"])
        }
        self.required_area = {
            int(r["SpellID"]): int(r["RequiredAreasID"] or 0) for r in tables["SpellCastingRequirements"]
        }
        self.item_class = {int(r["ID"]): int(r["ClassID"]) for r in tables["Item"]}
        self.items = {int(r["ID"]): r for r in tables["ItemSparse"]}
        effects_by_id = {int(r["ID"]): r for r in tables["ItemEffect"]}
        # item -> spells it casts when used (TriggerType 0)
        self.use_spells: dict[int, list[int]] = defaultdict(list)
        for row in tables["ItemXItemEffect"]:
            effect = effects_by_id.get(int(row["ItemEffectID"]))
            if effect and int(effect["TriggerType"]) == 0 and int(effect["SpellID"]) > 0:
                self.use_spells[int(row["ItemID"])].append(int(effect["SpellID"]))

    def seated(self, spell: int) -> bool:
        return bool(self.interrupt_flags.get(spell, 0) & NOT_SEATED)

    def regen(self, spell: int) -> dict[str, float]:
        """What one seated spell restores over its whole duration.

        Returns a dict with any of hp, mp (flat totals) and hpPct, mpPct
        (percent of maximum, totals). Empty when the spell is not food.
        """
        if not self.seated(spell):
            return {}
        duration = self.duration.get(spell, 0)
        rows = [r for r in self.effects.get(spell, []) if int(r["Effect"]) == APPLY_AURA]
        # A percent effect with no period of its own ticks with its sibling.
        periods = [int(r["EffectAuraPeriod"]) for r in rows if int(r["EffectAuraPeriod"]) > 0]
        default_period = periods[0] if periods else 1000
        out: dict[str, float] = defaultdict(float)
        for row in rows:
            aura = int(row["EffectAura"])
            points = float(row["EffectBasePointsF"])
            power = int(row["EffectMiscValue_0"])
            if aura == AURA_REGEN_HEALTH:
                out["hp"] += points / 5 * duration
            elif aura == AURA_REGEN_POWER and power == POWER_MANA:
                out["mp"] += points / 5 * duration
            elif aura in (AURA_PCT_HEALTH, AURA_PCT_POWER):
                if aura == AURA_PCT_POWER and power != POWER_MANA:
                    continue
                period = int(row["EffectAuraPeriod"]) or default_period
                key = "hpPct" if aura == AURA_PCT_HEALTH else "mpPct"
                out[key] += points * duration / (period / 1000)
        return {key: value for key, value in out.items() if value > 0}

    def walk(self, spell: int) -> list[int]:
        """The spell and every spell it triggers, to TRIGGER_DEPTH levels."""
        seen: list[int] = []

        def visit(current: int, depth: int) -> None:
            if current in seen or depth > TRIGGER_DEPTH:
                return
            seen.append(current)
            for row in self.effects.get(current, []):
                triggered = int(row["EffectTriggerSpell"] or 0)
                if triggered > 0:
                    visit(triggered, depth + 1)

        visit(spell, 0)
        return seen


def build_food(data: Data):
    food: dict[int, dict] = {}
    auras: dict[int, set[str]] = defaultdict(set)
    skipped: dict[str, list[str]] = defaultdict(list)

    for item, use_spells in sorted(data.use_spells.items()):
        sparse = data.items.get(item)
        if not sparse:
            continue
        totals: dict[str, float] = defaultdict(float)
        visited: list[int] = []
        for use_spell in use_spells:
            for spell in data.walk(use_spell):
                visited.append(spell)
                restored = data.regen(spell)
                for key, value in restored.items():
                    totals[key] += value
                # Record the aura even when the item is skipped below, so the
                # bar still shows for food you eat by hand.
                if "hp" in restored or "hpPct" in restored:
                    auras[spell].add("hp")
                if "mp" in restored or "mpPct" in restored:
                    auras[spell].add("mp")
        if not totals:
            continue

        name = sparse["Display_lang"]
        label = f"{item} {name}"
        if JUNK_NAME.search(name) or not name:
            skipped["junk name"].append(label)
        elif data.item_class.get(item) in (CLASS_TRADE_GOODS, CLASS_QUEST) or item in RAW_FISH_CONSUMABLES:
            skipped["raw fish, trade good or quest item"].append(label)
        elif any(data.required_area.get(spell, 0) for spell in visited):
            skipped["works only in one area"].append(label)
        elif int(sparse["MinFactionID"] or 0) > 0:
            skipped["needs a reputation"].append(label)
        else:
            entry = {"name": name, "level": int(sparse["RequiredLevel"] or 0)}
            for key in ("hp", "mp"):
                if totals.get(key):
                    entry[key] = round(totals[key])
            for key in ("hpPct", "mpPct"):
                if totals.get(key):
                    entry[key] = min(100, round(totals[key]))
            food[item] = entry
    return food, auras, skipped


def render(build: str, food: dict[int, dict], auras: dict[int, set[str]], data: Data) -> str:
    lines = [
        f"-- GENERATED by tools/gen_food.py from wago.tools, build {build}. Do not edit.",
        f"-- {len(food)} food and drink items, {len(auras)} effects.",
        "",
        "local _, ns = ...",
        "",
        f'ns.FoodBuild = "{build}"',
        "",
        "-- item ID = what the item restores over its full duration, and the level it needs.",
        "-- hp, mp: flat totals. hpPct, mpPct: percent of your maximum.",
        "ns.Food = {",
    ]
    for item, entry in sorted(food.items()):
        fields = [f"{key} = {entry[key]}" for key in ("hp", "mp", "hpPct", "mpPct") if key in entry]
        fields.append(f"level = {entry['level']}")
        lines.append(f"    [{item}] = {{ {', '.join(fields)} }}, -- {entry['name']}")
    lines += [
        "}",
        "",
        "-- effect (aura) spell ID = what it restores while it is on you.",
        "ns.Auras = {",
    ]
    for spell, kinds in sorted(auras.items()):
        kind = "both" if len(kinds) == 2 else next(iter(kinds))
        lines.append(f'    [{spell}] = "{kind}", -- {data.spell_names.get(spell, "?")}')
    lines += ["}", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", help="client build, such as 1.60.1.70959. Default: newest wowf build.")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Data" / "Food.lua",
        help="output file. Default: Data/Food.lua in the addon.",
    )
    args = parser.parse_args()

    build = args.build or newest_build()
    print(f"build {build}", file=sys.stderr)
    data = Data(load_tables(build))
    food, auras, skipped = build_food(data)
    if len(food) < 100:
        raise SystemExit(f"only {len(food)} food items found: the data layout probably changed")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(build, food, auras, data), encoding="utf-8", newline="\n")

    print(f"wrote {args.out}: {len(food)} items, {len(auras)} effects")
    for reason, labels in sorted(skipped.items()):
        print(f"skipped, {reason}: {len(labels)}")
        for label in labels:
            print(f"    {label}")


if __name__ == "__main__":
    main()

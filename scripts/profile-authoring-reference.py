#!/usr/bin/env python3
"""Generate BetterBots manual profile authoring reference tables."""

from __future__ import annotations

import argparse
import difflib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HADRONS_ROOT = REPO_ROOT.parent / "hadrons-blessing"
DEFAULT_OUTPUT = REPO_ROOT / "docs" / "bot" / "profile-authoring-reference.md"
CORE_CLASSES = ("veteran", "zealot", "psyker", "ogryn")


JsonObject = dict[str, Any]


@dataclass(frozen=True)
class Registry:
    entities: list[JsonObject]
    aliases_by_entity_id: dict[str, list[JsonObject]]
    blessing_family_by_trait_id: dict[str, str]
    source_snapshot_ids: list[str]


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def _load_records(root: Path) -> list[JsonObject]:
    records: list[JsonObject] = []
    for path in sorted(root.glob("*.json")):
        value = _load_json(path)
        if not isinstance(value, list):
            raise ValueError(f"{path} must contain a JSON array")
        records.extend(value)
    return records


def _entity_attr(entity: JsonObject, key: str) -> str | None:
    attributes = entity.get("attributes")
    if not isinstance(attributes, dict):
        return None
    value = attributes.get(key)
    return value if isinstance(value, str) else None


def _engine_key(canonical_entity_id: str | None) -> str:
    if not canonical_entity_id:
        return ""
    return canonical_entity_id.rsplit(".", 1)[-1]


def _title(value: str) -> str:
    return value.replace("_", " ").title()


def _md(value: object) -> str:
    text = "" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ")


def _label_for_entity(entity: JsonObject, registry: Registry) -> str:
    ui_name = entity.get("ui_name")
    if isinstance(ui_name, str) and ui_name.strip():
        return ui_name.strip()

    aliases = registry.aliases_by_entity_id.get(str(entity.get("id")), [])
    preferred = sorted(
        (
            alias
            for alias in aliases
            if alias.get("confidence") == "high"
            and alias.get("alias_kind") in {"gameslantern_name", "community_name", "guide_name"}
            and isinstance(alias.get("text"), str)
        ),
        key=lambda alias: (-int(alias.get("rank_weight", 0)), str(alias.get("text"))),
    )
    if preferred:
        return str(preferred[0]["text"])

    internal_name = entity.get("internal_name")
    return str(internal_name) if isinstance(internal_name, str) else str(entity.get("id", ""))


def _load_registry(hadrons_root: Path) -> Registry:
    ground_truth = hadrons_root / "data" / "ground-truth"
    entities = _load_records(ground_truth / "entities")
    aliases = _load_records(ground_truth / "aliases")
    edges = _load_json(ground_truth / "edges" / "shared.json")

    aliases_by_entity_id: dict[str, list[JsonObject]] = {}
    for alias in aliases:
        entity_id = alias.get("candidate_entity_id")
        if isinstance(entity_id, str):
            aliases_by_entity_id.setdefault(entity_id, []).append(alias)

    blessing_family_by_trait_id: dict[str, str] = {}
    for edge in edges:
        if edge.get("type") != "instance_of":
            continue
        trait_id = edge.get("from_entity_id")
        family_id = edge.get("to_entity_id")
        if isinstance(trait_id, str) and isinstance(family_id, str):
            blessing_family_by_trait_id[trait_id] = _engine_key(family_id)

    source_snapshot_ids = sorted(
        {
            str(entity["source_snapshot_id"])
            for entity in entities
            if isinstance(entity.get("source_snapshot_id"), str)
        }
    )
    return Registry(entities, aliases_by_entity_id, blessing_family_by_trait_id, source_snapshot_ids)


def weapon_item_path(entity: JsonObject) -> str:
    slot = _entity_attr(entity, "slot")
    internal_name = entity.get("internal_name")
    if slot not in {"melee", "ranged"} or not isinstance(internal_name, str):
        raise ValueError(f"Cannot derive weapon content path for {entity.get('id')}")
    return f"content/items/weapons/player/{slot}/{internal_name}"


def blessing_item_path(entity: JsonObject) -> str:
    family = _entity_attr(entity, "weapon_family")
    internal_name = entity.get("internal_name")
    if not family or not isinstance(internal_name, str):
        raise ValueError(f"Cannot derive blessing content path for {entity.get('id')}")
    family_candidates = {family}
    family_candidates.add(f"bespoke_{family}")
    if "_" in family:
        family_candidates.add(family.split("_", 1)[1])
    for candidate in sorted(family_candidates, key=len, reverse=True):
        prefix = f"weapon_trait_bespoke_{candidate}_"
        if internal_name.startswith(prefix):
            return f"content/items/traits/bespoke_{family}/{internal_name[len(prefix):]}"
    raise ValueError(f"Unexpected blessing internal name for {entity.get('id')}: {internal_name}")


def perk_item_path(entity: JsonObject) -> str:
    slot = _entity_attr(entity, "slot")
    internal_name = entity.get("internal_name")
    if slot not in {"melee", "ranged"} or not isinstance(internal_name, str):
        raise ValueError(f"Cannot derive perk content path for {entity.get('id')}")

    category = f"{slot}_common"
    exceptions = {
        "weapon_trait_increase_crit_chance": "wield_increase_crit_chance",
        "weapon_trait_increase_damage_elites": "wield_increase_elite_enemy_damage",
        "weapon_trait_increase_stamina": "wield_increase_stamina",
        "weapon_trait_ranged_increased_reload_speed": "wield_increase_reload_speed",
    }
    if internal_name in exceptions:
        perk_name = exceptions[internal_name]
    else:
        prefix = f"weapon_trait_{slot}_common_"
        if internal_name.startswith(prefix):
            perk_name = internal_name[len(prefix) :]
        elif internal_name.startswith("weapon_trait_ranged_increase_"):
            perk_name = "wield_increase_" + internal_name[len("weapon_trait_ranged_increase_") :]
        elif internal_name.startswith("weapon_trait_increase_"):
            perk_name = "wield_increase_" + internal_name[len("weapon_trait_increase_") :]
        elif internal_name.startswith("weapon_trait_reduce_"):
            perk_name = "wield_reduce_" + internal_name[len("weapon_trait_reduce_") :]
        elif internal_name.startswith("weapon_trait_reduced_"):
            perk_name = "wield_reduce_" + internal_name[len("weapon_trait_reduced_") :]
        else:
            raise ValueError(f"Unexpected perk internal name for {entity.get('id')}: {internal_name}")
        if perk_name.startswith("wield_increased_"):
            perk_name = "wield_increase_" + perk_name[len("wield_increased_") :]
        perk_name = perk_name.replace("damage_elites", "elite_enemy_damage")
        perk_name = perk_name.replace("damage_hordes", "horde_enemy_damage")
        perk_name = perk_name.replace("damage_specials", "special_enemy_damage")
    return f"content/items/perks/{category}/{perk_name}"


def _weapon_rows(registry: Registry) -> list[list[str]]:
    rows: list[list[str]] = []
    for entity in registry.entities:
        if entity.get("kind") != "weapon":
            continue
        rows.append(
            [
                _label_for_entity(entity, registry),
                str(_entity_attr(entity, "slot") or ""),
                _engine_key(str(entity["id"])),
                weapon_item_path(entity),
            ]
        )
    return sorted(rows, key=lambda row: (row[1], row[0].lower(), row[2]))


def _class_node_rows(class_name: str, registry: Registry) -> list[list[str]]:
    rows: list[list[str]] = []
    class_entities = [entity for entity in registry.entities if entity.get("domain") == class_name]
    tree_by_talent = {
        _entity_attr(entity, "talent_internal_name"): entity
        for entity in class_entities
        if entity.get("kind") == "tree_node" and _entity_attr(entity, "talent_internal_name")
    }
    for entity in class_entities:
        if entity.get("kind") not in {"ability", "aura", "keystone", "talent", "talent_modifier"}:
            continue
        engine_key = str(entity.get("internal_name"))
        tree_entity = tree_by_talent.get(engine_key)
        tree_type = _entity_attr(tree_entity, "tree_type") if tree_entity else None
        rows.append(
            [
                _label_for_entity(entity, registry),
                tree_type or str(entity.get("kind", "")),
                engine_key,
            ]
        )
    return sorted(rows, key=lambda row: (row[1], row[0].lower(), row[2]))


def _perk_rows(registry: Registry) -> list[list[str]]:
    rows: list[list[str]] = []
    for entity in registry.entities:
        if entity.get("kind") != "weapon_perk":
            continue
        rows.append(
            [
                _label_for_entity(entity, registry),
                str(_entity_attr(entity, "slot") or ""),
                str(entity.get("internal_name")),
                perk_item_path(entity),
            ]
        )
    return sorted(rows, key=lambda row: (row[1], row[0].lower(), row[2]))


def _blessing_rows(registry: Registry) -> list[list[str]]:
    rows: list[list[str]] = []
    for entity in registry.entities:
        if entity.get("kind") != "weapon_trait":
            continue
        entity_id = str(entity.get("id"))
        blessing_family = registry.blessing_family_by_trait_id.get(entity_id, "")
        display_name = "(no display name)" if not blessing_family or blessing_family.startswith("weapon_trait_") else _title(blessing_family)
        rows.append(
            [
                display_name,
                str(_entity_attr(entity, "slot") or ""),
                str(_entity_attr(entity, "weapon_family") or ""),
                str(entity.get("internal_name")),
                blessing_item_path(entity),
            ]
        )
    return sorted(rows, key=lambda row: (row[0].lower(), row[2], row[3]))


def _table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = [
        "| " + " | ".join(_md(header) for header in headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(_md(value) for value in row) + " |")
    return lines


def render_reference(hadrons_root: Path) -> str:
    registry = _load_registry(hadrons_root)
    snapshots = ", ".join(registry.source_snapshot_ids[:3])
    if len(registry.source_snapshot_ids) > 3:
        snapshots += ", ..."

    lines = [
        "# BetterBots Profile Authoring Reference",
        "",
        "<!-- Generated by scripts/profile-authoring-reference.py. Do not edit tables by hand. -->",
        "",
        "This file maps common in-game build terms to the exact strings BetterBots profile templates need.",
        "Regenerate it with `make profile-authoring-reference` after updating [`hadrons-blessing`](https://github.com/hummat/hadrons-blessing).",
        "",
        f"Source snapshots: `{snapshots}`",
        "",
    ]
    lines.extend(
        [
            "## Weapon loadout paths",
            "",
            "Use these in `loadout.slot_primary` and `loadout.slot_secondary`.",
            "",
        ]
    )
    lines.extend(_table(["In-game name", "Slot", "Template id", "Loadout path"], _weapon_rows(registry)))
    lines.extend(["", "## Class talent keys", ""])
    for class_name in CORE_CLASSES:
        lines.extend([f"### {_title(class_name)}", ""])
        lines.extend(_table(["In-game name", "Tree type", "Talent key"], _class_node_rows(class_name, registry)))
        lines.append("")
    lines.extend(
        [
            "## Weapon perk paths",
            "",
            "Use these under `weapon_overrides.<slot>.perks` via `_perk_override(\"...\")` or `_perk_id(...)`.",
            "",
        ]
    )
    lines.extend(_table(["In-game name", "Slot", "Engine trait", "Override path"], _perk_rows(registry)))
    lines.extend(
        [
            "",
            "## Weapon blessing paths",
            "",
            "Blessing names are display-name families. The override path is weapon-family-specific; copy the exact path for the weapon family you are editing.",
            "",
        ]
    )
    lines.extend(_table(["Blessing family", "Slot", "Weapon family", "Engine trait", "Override path"], _blessing_rows(registry)))
    lines.append("")
    return "\n".join(lines)


def _write_if_changed(path: Path, content: str) -> bool:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def _check(path: Path, content: str) -> int:
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if old == content:
        return 0
    diff = difflib.unified_diff(
        old.splitlines(),
        content.splitlines(),
        fromfile=str(path),
        tofile=f"{path} (generated)",
        lineterm="",
    )
    sys.stderr.write("\n".join(list(diff)[:200]) + "\n")
    sys.stderr.write(f"{path} is stale; run `python3 scripts/profile-authoring-reference.py generate`.\n")
    return 1


def run_self_test() -> None:
    weapon = {
        "id": "shared.weapon.plasmagun_p1_m1",
        "kind": "weapon",
        "internal_name": "plasmagun_p1_m1",
        "attributes": {"slot": "ranged"},
    }
    assert weapon_item_path(weapon) == "content/items/weapons/player/ranged/plasmagun_p1_m1"

    blessing = {
        "id": "shared.weapon_trait.weapon_trait_bespoke_powersword_p1_extended_activation_duration_on_chained_attacks",
        "kind": "weapon_trait",
        "internal_name": "weapon_trait_bespoke_powersword_p1_extended_activation_duration_on_chained_attacks",
        "attributes": {"slot": "melee", "weapon_family": "powersword_p1"},
    }
    assert (
        blessing_item_path(blessing)
        == "content/items/traits/bespoke_powersword_p1/extended_activation_duration_on_chained_attacks"
    )

    perk = {
        "id": "shared.weapon_perk.melee.weapon_trait_melee_common_wield_increased_super_armor_damage",
        "kind": "weapon_perk",
        "internal_name": "weapon_trait_melee_common_wield_increased_super_armor_damage",
        "attributes": {"slot": "melee"},
    }
    assert perk_item_path(perk) == "content/items/perks/melee_common/wield_increase_super_armor_damage"

    elite_perk = {
        "id": "shared.weapon_perk.melee.weapon_trait_increase_damage_elites",
        "kind": "weapon_perk",
        "internal_name": "weapon_trait_increase_damage_elites",
        "attributes": {"slot": "melee"},
    }
    assert perk_item_path(elite_perk) == "content/items/perks/melee_common/wield_increase_elite_enemy_damage"

    with TemporaryDirectory() as tmp_dir:
        root = Path(tmp_dir)
        (root / "data" / "ground-truth" / "entities").mkdir(parents=True)
        (root / "data" / "ground-truth" / "aliases").mkdir(parents=True)
        (root / "data" / "ground-truth" / "edges").mkdir(parents=True)
        (root / "data" / "builds" / "bot").mkdir(parents=True)
        entities = [
            weapon,
            perk,
            blessing,
            {"id": "veteran.ability.veteran_test", "kind": "ability", "domain": "veteran", "internal_name": "veteran_test"},
            {
                "id": "veteran.tree_node.node_test",
                "kind": "tree_node",
                "domain": "veteran",
                "internal_name": "node_test",
                "attributes": {"talent_internal_name": "veteran_test", "tree_type": "ability"},
            },
        ]
        for class_name in CORE_CLASSES:
            entities.append(
                {
                    "id": f"{class_name}.talent.{class_name}_talent",
                    "kind": "talent",
                    "domain": class_name,
                    "internal_name": f"{class_name}_talent",
                    "attributes": {},
                }
            )
        _write_if_changed(root / "data" / "ground-truth" / "entities" / "all.json", json.dumps(entities))
        _write_if_changed(
            root / "data" / "ground-truth" / "aliases" / "all.json",
            json.dumps(
                [
                    {
                        "text": "M35 Magnacore Mk II Plasma Gun",
                        "candidate_entity_id": "shared.weapon.plasmagun_p1_m1",
                        "alias_kind": "gameslantern_name",
                        "confidence": "high",
                        "rank_weight": 100,
                    }
                ]
            ),
        )
        _write_if_changed(
            root / "data" / "ground-truth" / "edges" / "shared.json",
            json.dumps(
                [
                    {
                        "type": "instance_of",
                        "from_entity_id": blessing["id"],
                        "to_entity_id": "shared.name_family.blessing.cycler",
                    }
                ]
            ),
        )
        rendered = render_reference(root)
        assert "M35 Magnacore Mk II Plasma Gun" in rendered
        assert "content/items/traits/bespoke_powersword_p1/extended_activation_duration_on_chained_attacks" in rendered
        assert "veteran_test" in rendered


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("generate", "check"), default="generate")
    parser.add_argument("--hadrons-root", type=Path, default=DEFAULT_HADRONS_ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--self-test", action="store_true", help="run generator unit self-test and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        run_self_test()
        return 0

    if not args.hadrons_root.exists():
        raise SystemExit(f"hadrons-blessing root not found: {args.hadrons_root}")

    content = render_reference(args.hadrons_root)
    if args.command == "check":
        return _check(args.output, content)

    changed = _write_if_changed(args.output, content)
    print(f"{'Updated' if changed else 'Already current'} {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

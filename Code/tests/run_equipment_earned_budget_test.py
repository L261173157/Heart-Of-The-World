#!/usr/bin/env python3
"""正常主线收入的新白装Boss验收；默认先真正完成13个C1–C5独立进程。

仅测试预算替代方案：291金币，190强化、100两件固定白装，保留五份已支付饭团。
不伪造装备、掉落、Boss或角色资源。--from-save只允许明确报告的本地复用。
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

from run_campaign_earned_boss_test import EarnedEvidence, isolated_runtime, stop_driver
from run_campaign_earned_budget_test import C2_PHASES, STORY_PHASES

PROJECT = Path(__file__).resolve().parents[1]
MARKER = "=== EQUIPMENT EARNED BUDGET PASS ==="
PHASE_MARKER = "=== EQUIPMENT EARNED BOSS PASS"
PREFIXES = ("EQUIPMENT_EARNED_PURCHASE ", "EARNED_PREFIGHT ",
            "EARNED_ECOLOGY_AGING ", "EARNED_COMBAT_RESULT ")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", nargs="?", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--from-save", type=Path,
                        help="Explicit local acceleration with separately verified genuine C5 bytes")
    parser.add_argument("--log-dir", type=Path, help="Keep generated isolated checkpoint/log/evidence files")
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if binary is None:
        parser.error("Godot executable could not be resolved")
    godot = str(Path(binary).resolve())
    directory = (contextlib.nullcontext(str(args.log_dir.resolve())) if args.log_dir
                 else tempfile.TemporaryDirectory(prefix="hotw-equipment-earned-"))
    with directory as value:
        root = Path(value)
        root.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        with isolated_runtime(env):
            return run_suite(args, parser, godot, root, env)


def run_suite(args, parser, godot: str, root: Path, env: dict[str, str]) -> int:
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    version = subprocess.check_output([godot, "--version"], env=env, text=True).strip()
    if not version.startswith("4.7.stable"):
        parser.error("Earned equipment acceptance requires Godot4.7 stable")
    evidence = EarnedEvidence(root, godot, version, env, "equipment_earned_budget")
    evidence.manifest["scope"] = {
        "source": "13 genuine main-story producer processes unless --from-save is explicitly supplied",
        "budget": "291 actual gold: weapon1/vigor2 upgrades190, white sword50+shield50, balance1; then actual C6:s1 pays12",
        "equipment": "real lava travel/exploration unlocks ilvl10; actual offer/purchase/equip services; fixed white only",
        "combat": "expert touch bot observes committed circle/sector/ground-target telegraphs, current obstacles and own cooldowns with 180ms reaction delay and 18px clearance; casts only in visible recovery; actual movement/dash/cast/recovery; original live Boss, real collision and damage",
        "limits": "frozen ecology/unrelated actors during combat, normal natural regeneration, five paid food; no human or iPhone performance claim",
    }
    evidence.write()
    source = root / "genuine-c5.json"
    if args.from_save:
        supplied = args.from_save.resolve()
        if not supplied.is_file():
            parser.error("--from-save must be an existing genuine C5 save")
        if supplied != source:
            shutil.copyfile(supplied, source)
        evidence.manifest["supplied_source"] = evidence.snapshot(supplied, evidence.directory / "supplied-source.json")
        evidence.write()
        print("Local acceleration: independently produced genuine C5 save; source-generation phases skipped", flush=True)
    else:
        source.unlink(missing_ok=True)
        Path(str(source) + ".campaign_expected").unlink(missing_ok=True)
        for phases, scene, frames, timeout, marker, error_case in (
            (C2_PHASES, "campaign_acceptance_test", 160000, 300, "=== CAMPAIGN ACCEPTANCE PASS", "campaign_acceptance"),
            (STORY_PHASES, "campaign_story_acceptance_test", 200000, 420, "=== CAMPAIGN STORY ACCEPTANCE PASS", "campaign_story"),
        ):
            for phase in phases:
                command = [godot, "--headless", "--path", str(PROJECT),
                           f"res://tests/{scene}.tscn", "--quit-after", str(frames), "--", phase]
                passed, text, _ = evidence.run("source-" + phase, source, command, timeout,
                    marker, error_case, root / ("source-" + phase + ".log"))
                print(text, end="", flush=True)
                if not passed:
                    evidence.finish(False, "source-" + phase)
                    return 1
    evidence.manifest["genuine_c5_source"] = evidence.snapshot(source)
    evidence.manifest["source_processes"] = 0 if args.from_save else 13
    evidence.write()
    print("EQUIPMENT_EARNED_SOURCE " + json.dumps({
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "source_processes": evidence.manifest["source_processes"],
        "fixture": "generated isolated test data, never user save",
    }), flush=True)

    results: list[dict] = []

    def phase(name: str, checkpoint: Path, action: str, seed: int = 0) -> bool:
        command = [godot, "--headless", "--path", str(PROJECT),
                   "res://tests/equipment_earned_budget_test.tscn", "--", action, str(seed)]
        passed, text, row = evidence.run(name, checkpoint, command, 900,
            PHASE_MARKER, "equipment_earned_budget", root / (name + ".log"), prefixes=PREFIXES)
        results.append(row)
        print(f"{name}: {'PASS' if passed else 'FAIL'} ({row['wall_seconds']}s wall)", flush=True)
        for prefix in PREFIXES:
            key = prefix.strip()
            if key in row:
                print("EQUIPMENT_EARNED_RESULT " + json.dumps({"name": name, key: row[key]}, ensure_ascii=False), flush=True)
        if not passed:
            print(text, end="", flush=True)
            evidence.finish(False, name)
        return passed

    prepared = root / "prepared.json"
    shutil.copyfile(source, prepared)
    if not phase("prepare", prepared, "prepare"):
        return 1
    reckless = root / "reckless.json"
    shutil.copyfile(prepared, reckless)
    if not phase("reckless", reckless, "reckless", 2):
        return 1
    for index in range(2):
        checkpoint = root / f"young-{index + 1}.json"
        shutil.copyfile(prepared, checkpoint)
        if not phase(f"young-{index + 1}", checkpoint, "mobile", 11 + index):
            return 1
    aged = root / "aged.json"
    shutil.copyfile(prepared, aged)
    if not phase("age", aged, "age", 5):
        return 1
    for index in range(2):
        checkpoint = root / f"aged-{index + 1}.json"
        shutil.copyfile(aged, checkpoint)
        if not phase(f"aged-{index + 1}", checkpoint, "mobile", 21 + index):
            return 1
    fights = [row["EARNED_COMBAT_RESULT"] for row in results
              if "EARNED_COMBAT_RESULT" in row and row["name"] != "reckless"]
    if len(fights) != 4 or not all(fight["won"] and not fight["died"]
                                 and fight["boss_anchor_unchanged"] for fight in fights):
        evidence.finish(False, "missing four real original-Boss wins")
        return 1
    summary = {
        "source_processes": evidence.manifest["source_processes"],
        "four_wins": [{"age": fight["boss_age"], "seconds": fight["seconds"],
                       "food_used": fight["food_used"], "hp_min": fight["hp_min"],
                       "mp_min": fight["mp_min"], "damage_events": fight["damage_events"],
                       "dashes": fight["actual_dashes"], "gold_before_kill": fight["gold_before_kill"]}
                      for fight in fights],
        "build": fights[0]["equipment_build"],
    }
    (root / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    evidence.manifest["summary"] = summary
    evidence.finish(True)
    print("EQUIPMENT_EARNED_SUMMARY " + json.dumps(summary, ensure_ascii=False), flush=True)
    print(MARKER, flush=True)
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop_driver)
    raise SystemExit(main())

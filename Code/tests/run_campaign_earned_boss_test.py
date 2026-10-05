#!/usr/bin/env python3
"""Cold-repeat normal-budget combat from an externally verified genuine C5 save.

This is an acceptance harness, not a fabricated start-to-finish gameplay fixture.
It requires the actual C1-C5 receipt/save artifact. No production files are edited.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from run_headless import unexpected_errors

PROJECT = Path(__file__).resolve().parents[1]
MARKER = "=== CAMPAIGN EARNED BOSS PASS"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", type=Path)
    parser.add_argument("genuine_c5_save", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--skip-aged", action="store_true")
    args = parser.parse_args()
    godot = args.godot.resolve()
    source = args.genuine_c5_save.resolve()
    output = args.output.resolve()
    if not source.is_file() or not godot.is_file():
        parser.error("Godot binary and genuine C5 save must exist")
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for key, folder in [("HOME", "home"), ("XDG_CACHE_HOME", "cache"),
                        ("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data")]:
        path = output / folder
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    version = subprocess.check_output([str(godot), "--version"], text=True, env=env).strip()
    if not version.startswith("4.7.stable"):
        parser.error("This acceptance requires Godot 4.7 stable, not PATH fallback")
    manifest = {"engine": version, "source": str(source), "source_sha256": digest(source),
                "harness_sha256": digest(PROJECT / "tests/campaign_earned_boss_test.gd"),
                "results": [], "limitations": [
                    "The source main ledger is genuine; its capacity-fixture inventory is discarded",
                    "Only five verified paid chapter bonus foods are reconstructed; 280 gold buys upgrades",
                    "Ecology and unrelated actors are frozen during isolated live original-Boss combat",
                    "Optional aging advances 1199 normal WorldSim bridge ticks, not human play",
                    "Bot reads AI state and collision geometry; this is not novice difficulty or iPhone QA",
                    "Touch commands include standard Godot mouse-emulation events for ordinary menu tabs",
                    "MoreBtn closes More; MoreClose clipped-row regression is tested separately"]}

    def run(name: str, checkpoint: Path, phase: str, seed: int = 0) -> bool:
        env["HOTW_TEST_SAVE"] = str(checkpoint)
        input_hash = digest(checkpoint)
        started = time.monotonic()
        command = [str(godot), "--headless", "--path", str(PROJECT),
                   "res://tests/campaign_earned_boss_test.tscn", "--", phase, str(seed)]
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=900)
        log = result.stdout + result.stderr
        (output / f"{name}.log").write_text(log)
        errors = unexpected_errors("campaign_earned_boss", log)
        row = {"name": name, "phase": phase, "rng_seed_offset": seed,
               "input_sha256": input_hash, "output_sha256": digest(checkpoint),
               "wall_seconds": round(time.monotonic()-started, 3),
               "returncode": result.returncode, "unexpected_errors": errors,
               "passed": result.returncode == 0 and MARKER in log and not errors}
        for line in log.splitlines():
            for prefix in ["EARNED_PREFIGHT ", "EARNED_ECOLOGY_AGING ",
                           "EARNED_COMBAT_RESULT ", "EARNED_STORY_COMPLETE "]:
                if line.startswith(prefix):
                    row[prefix.strip()] = json.loads(line[len(prefix):])
        manifest["results"].append(row)
        (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        print(f"{name}: {'PASS' if row['passed'] else 'FAIL'} ({row['wall_seconds']}s wall)", flush=True)
        if not row["passed"]:
            print(log, end="", flush=True)
        return bool(row["passed"])

    prepared = output / "prepared.json"
    shutil.copy2(source, prepared)
    if not run("prepare", prepared, "prepare"):
        return 1
    reckless = output / "reckless.json"
    shutil.copy2(prepared, reckless)
    if not run("reckless", reckless, "reckless", 2):
        return 1
    first_win = None
    for index in range(max(2, args.repeats)):
        checkpoint = output / f"young-{index+1}.json"
        shutil.copy2(prepared, checkpoint)
        if not run(f"young-{index+1}", checkpoint, "mobile", 11+index):
            return 1
        if first_win is None:
            first_win = checkpoint
    if not args.skip_aged:
        aged = output / "aged.json"
        shutil.copy2(prepared, aged)
        if not run("age", aged, "age", 5):
            return 1
        for index in range(max(2, args.repeats)):
            checkpoint = output / f"aged-{index+1}.json"
            shutil.copy2(aged, checkpoint)
            if not run(f"aged-{index+1}", checkpoint, "mobile", 21+index):
                return 1
    complete = output / "normal-complete.json"
    shutil.copy2(first_win, complete)
    if not run("normal-complete", complete, "finish", 31):
        return 1
    print("=== CAMPAIGN EARNED BOSS COLD REPEATS PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""真实完成前两章后，独立进程验证双路线、后四章及唯一团聚终局。"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors
from run_campaign_lifecycle_test import run_phase as run_chapter_two


def run_story(godot: str, project: Path, env: dict[str, str], phase: str) -> bool:
    result = subprocess.run(
        [godot, "--headless", "--path", str(project),
         "res://tests/campaign_story_acceptance_test.tscn", "--quit-after", "200000", "--", phase],
        env=env, capture_output=True, text=True, timeout=420)
    output = result.stdout + result.stderr
    print(f"[campaign story lifecycle: {phase}]", flush=True)
    print(output, end="", flush=True)
    return (result.returncode == 0 and "=== CAMPAIGN STORY ACCEPTANCE PASS" in output
            and not unexpected_errors("campaign_story", output))


def snapshot(save: Path) -> tuple[bytes, bytes]:
    return save.read_bytes(), Path(str(save) + ".campaign_expected").read_bytes()


def restore(save: Path, saved: tuple[bytes, bytes]) -> None:
    # 分支夹具只恢复此前真实完成并验证的字节，不编造完成证据或更改奖励。
    save.write_bytes(saved[0])
    Path(str(save) + ".campaign_expected").write_bytes(saved[1])


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-campaign-story-") as temp:
        root = Path(temp)
        env = os.environ.copy()
        for key, name in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                          ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            directory = root / name
            directory.mkdir()
            env[key] = str(directory)
        save = root / "save.json"
        env["HOTW_TEST_SAVE"] = str(save)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        if "--from-save" in sys.argv:
            source = Path(sys.argv[sys.argv.index("--from-save") + 1]).resolve()
            shutil.copyfile(source, save)
            shutil.copyfile(Path(str(source) + ".campaign_expected"), Path(str(save) + ".campaign_expected"))
        else:
            for phase in ("chapter1", "depart", "rune_partial", "runes", "rescue", "beacon99", "claim"):
                if not run_chapter_two(godot, project, env, phase):
                    return 1
        if not run_story(godot, project, env, "c3_prepare"):
            return 1
        prepared = snapshot(save)
        for route in ("near", "outer"):
            restore(save, prepared)
            if not run_story(godot, project, env, "c3_" + route + "_partial"):
                return 1
            if not run_story(godot, project, env, "c3_" + route):
                return 1
            q = json.loads(save.read_bytes())["campaign_quest"]
            proof = q["quests"]["watch_c3_swamp:s3"]["evidence"]["watch_c3_swamp:s3:reach"]
            if proof.get("route") != route or not proof.get("traversed"):
                print("FAIL the persisted route does not match the path actually walked")
                return 1
        for phase in ("c4", "c5_partial", "c5_finish"):
            if not run_story(godot, project, env, phase):
                return 1
        before_finale = snapshot(save)
        if not run_story(godot, project, env, "c6_live") or not run_story(godot, project, env, "read_defeat"):
            return 1
        restore(save, before_finale)
        if not run_story(godot, project, env, "c6_prepare_empty"):
            return 1
        if not run_story(godot, project, env, "ending_reunion"):
            return 1
        state = json.loads(save.read_bytes())["campaign_quest"]
        q = state["quests"]["watch_c6_lava:s4"]
        conclusion = q.get("evidence", {}).get("watch_c6_lava:s4:ending", {})
        if state.get("ending") != "reunion" or q.get("choice") or conclusion.get("kind") != "conclude" or "choice" in conclusion or not q.get("receipt", {}).get("paid"):
            print("FAIL single conclusion evidence and one-time paid receipt were not persisted together")
            return 1
        before = save.read_bytes()
        if not run_story(godot, project, env, "read_ending"):
            return 1
        if save.read_bytes() != before:
            print("FAIL read-only cold ending verification changed saved rewards")
            return 1
        print("=== CAMPAIGN STORY LIFECYCLE PASS ===", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""失联前哨的真实独立进程往返：证据、里程碑、修复待领、旧版迁移。"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors

PHASES = ("clue", "recovery", "rescue", "repair", "claim", "paid")


def run_phase(godot: str, project: Path, env: dict[str, str], phase: str) -> bool:
    command = [godot, "--headless", "--path", str(project),
               "res://tests/outpost_chapter_contract_test.tscn", "--quit-after", "120000",
               "--", f"--cold-{phase}"]
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=240)
    output = result.stdout + result.stderr
    print(f"[outpost chapter lifecycle: {phase}]", flush=True)
    print(output, end="")
    return (result.returncode == 0 and "=== OUTPOST CHAPTER CONTRACT PASS" in output
            and not unexpected_errors("outpost_chapter_contract", output))


def run_depleted_cold(godot: str, project: Path, env: dict[str, str], save: Path) -> bool:
    if not run_phase(godot, project, env, "depleted-write"):
        return False
    old = json.loads(save.read_text())
    old["version"] = 12
    old.pop("outpost_quest", None)
    save.write_text(json.dumps(old, ensure_ascii=False))
    return run_phase(godot, project, env, "depleted-finish")


def run_embedded_cold(godot: str, project: Path, env: dict[str, str], save: Path) -> bool:
    if not run_phase(godot, project, env, "embedded-write"):
        return False
    embedded = json.loads(Path(str(save) + ".outpost_expected").read_text())["embedded"]
    embedded_save = json.loads(save.read_text())
    embedded_save["explored"] = base64.b64encode(bytes([255]) * 5000).decode()
    embedded_save.pop("exploration_v2", None)
    embedded_save["player"]["position"] = embedded["player"]
    for row in embedded_save["ecology"]["instances"]:
        if row["id"] == embedded["ids"][0]:
            row["spawn_pos"] = embedded["wall"]
            row["hp"] = 7.25
        elif row["id"] == embedded["ids"][1]:
            row["spawn_pos"] = embedded["outside"]
            row["hp"] = 9.25
    save.write_text(json.dumps(embedded_save, ensure_ascii=False))
    Path(str(save) + ".outpost_expected").write_text(json.dumps({"embedded": embedded}))
    return run_phase(godot, project, env, "embedded-actor")


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-outpost-chapter-lifecycle-") as temp:
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
        if "--depleted-only" in sys.argv:
            if not run_depleted_cold(godot, project, env, save):
                return 1
            print("=== OUTPOST DEPLETED COLD PASS ===")
            return 0
        if "--embedded-only" in sys.argv:
            if not run_embedded_cold(godot, project, env, save):
                return 1
            print("=== OUTPOST EMBEDDED COLD PASS ===")
            return 0
        snapshots = {}
        for phase in PHASES:
            if not run_phase(godot, project, env, phase):
                return 1
            if not save.is_file():
                print("FAIL isolated outpost save is missing")
                return 1
            current = json.loads(save.read_text())
            snapshots[phase] = current
            quest = current.get("outpost_quest", {})
            evidence = quest.get("evidence", {})
            if quest.get("id") != "lost_outpost_v1":
                print("FAIL stable chapter ID missing from persisted save")
                return 1
            if phase == "clue" and (not evidence.get("patrol_read") or evidence.get("entrance_read")):
                print("FAIL first clue must not manufacture second clue or milestone")
                return 1
            if phase == "recovery" and (not evidence.get("aid_taken") or evidence.get("tools_taken")
                                         or evidence.get("rescued")):
                print("FAIL partial recovery must preserve unique bag without auto-rescue")
                return 1
            if phase == "rescue" and (not evidence.get("rescued") or evidence.get("signpost_repaired")
                                      or "outpost:lost_watch" in current.get("checkpoints", [])):
                print("FAIL pre-repair save must not unlock checkpoint")
                return 1
            if phase == "repair" and (not evidence.get("signpost_repaired")
                                      or current.get("inventory", {}).get("onigiri") != 99
                                      or "outpost:lost_watch" not in current.get("checkpoints", [])):
                print("FAIL completed physical repair and pending99 reward must coexist")
                return 1
            if phase == "paid" and current != snapshots["claim"]:
                print("FAIL paid cold reader rewrote saved reward or world data")
                return 1
        # 独立旧档夹具取自刚刚真实完成的世界，只改为已定义的v12紧凑任务存储。
        # 迁移读取绝不通过发送虚构的玩家动作事件来伪造新章节的完成。
        for mode in ("paid", "pending", "progress"):
            legacy = json.loads(json.dumps(snapshots["rescue"]))
            new_chapter = legacy.pop("outpost_quest")
            legacy["version"] = 12
            legacy["checkpoints"] = [c for c in legacy.get("checkpoints", []) if c != "outpost:lost_watch"]
            raw_target = new_chapter.get("target", {})
            target = {key: raw_target[key] for key in ("region_id", "species", "pos", "key", "need", "kill_start") if key in raw_target}
            legacy["explored"] = base64.b64encode(bytes([255]) * 5000).decode()
            legacy.pop("exploration_v2", None)
            if not target:
                print("FAIL real ecological target absent for legacy migration fixture")
                return 1
            key = target["region_id"] + "|" + target["species"]
            compact = {
                "id": "camp_ecology_v1", "version": 1, "active": mode != "paid",
                "paid": mode == "paid", "last_summary": mode == "paid",
                "stage": "completed" if mode == "paid" else ("return" if mode == "pending" else "act"),
                "investigated": True, "choice": "ransack", "outcome": "" if mode == "progress" else "ransack",
                "target": target, "kills": [], "ransacks": [] if mode == "progress" else [key],
                "surveys": [key], "history": ["旧版真实世界紧凑任务迁移夹具"],
                "gold": 39, "xp": 44, "bonus": "onigiri",
                "paid_gold": 39 if mode == "paid" else 0, "paid_xp": 44 if mode == "paid" else 0,
                "next_clue": "旧版已付后续线索" if mode == "paid" else ""}
            legacy["camp_quest"] = compact
            save.write_text(json.dumps(legacy, ensure_ascii=False))
            Path(str(save) + ".outpost_expected").write_text(json.dumps({
                "camp_quest": compact, "gold": legacy["gold"], "inventory": legacy["inventory"],
                "world_seed": legacy["world_seed"]}, ensure_ascii=False))
            if not run_phase(godot, project, env, "legacy-" + mode):
                return 1
        if not run_embedded_cold(godot, project, env, save):
            return 1
        for damage in ("id", "chain"):
            invalid = json.loads(json.dumps(snapshots["claim"]))
            if damage == "id":
                invalid["outpost_quest"]["id"] = "other_outpost_v1"
            else:
                invalid["outpost_quest"]["evidence"]["aid_taken"] = False
            save.write_text(json.dumps(invalid, ensure_ascii=False))
            if not run_phase(godot, project, env, "invalid-" + damage):
                return 1
        if not run_depleted_cold(godot, project, env, save):
            return 1
        print("=== OUTPOST CHAPTER LIFECYCLE PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""独立进程任务领奖/存档回归；由统一入口先导入 Godot 工程。"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-quest-lifecycle-") as temp:
        sandbox = Path(temp)
        env = os.environ.copy()
        for name, directory in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                                ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            target = sandbox / directory
            target.mkdir()
            env[name] = str(target)
        save = sandbox / "save.json"
        env["HOTW_TEST_SAVE"] = str(save)
        env.pop("HOTW_QUEST_SHOTS", None)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        saved_paid = None
        for phase in ("write", "claim", "paid"):
            command = [godot, "--headless", "--path", str(project),
                       "res://tests/quest_clarity_test.tscn", "--quit-after", "10000",
                       "--", f"--cold-{phase}"]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=40)
            output = result.stdout + result.stderr
            print(f"[quest lifecycle: {phase}]", flush=True)
            print(output, end="")
            if result.returncode or "=== QUEST CLARITY PASSED" not in output or unexpected_errors("quest_clarity", output):
                return 1
            if not save.is_file():
                print("FAIL expected isolated quest save is missing")
                return 1
            data = json.loads(save.read_text())
            if phase == "write":
                active = data["quests"]["active"]
                if len(active) != 1 or active[0].get("claim_at_npc") is not True \
                        or active[0]["progress"] != active[0]["need"] \
                        or data["tracked_quest_id"] != active[0]["id"]:
                    print("FAIL serialized ready state or selected quest differs from runtime contract")
                    return 1
            elif phase == "claim":
                receipt = data["quests"].get("receipts", {}).get("lm_clarity_collect", {})
                if data["quests"]["active"] or not receipt or data["inventory"].get("gold-key") != 1:
                    print("FAIL serialized paid receipt or inventory is incomplete")
                    return 1
                saved_paid = data
            elif data != saved_paid:
                print("FAIL paid verification process changed the persisted quest rewards")
                return 1
        print("=== QUEST LIFECYCLE PASSED ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

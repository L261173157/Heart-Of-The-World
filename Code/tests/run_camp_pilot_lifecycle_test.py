#!/usr/bin/env python3
"""营地首章真实死亡/贡献/溢出待领取/支付收据的独立进程存档回归。"""
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
    with tempfile.TemporaryDirectory(prefix="hotw-camp-pilot-lifecycle-") as temp:
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
        paid = None
        for phase in ("write", "pending", "claim", "paid", "old"):
            if phase == "old":
                legacy = json.loads(save.read_text())
                legacy.pop("camp_quest", None)
                legacy["version"] = 10
                legacy["inventory"]["fish"] = 1
                legacy["quests"] = {
                    "active": [{"id": "legacy_preserved", "landmark_id": "camp_old_npc", "giver": "旧草药师",
                                "kind": "collect", "title": "旧材料进度", "item": "fish", "need": 2,
                                "progress": 1, "gold": 31, "xp": 7, "claim_at_npc": True}],
                    "completed": {"camp_old_npc": 4}, "receipts": {}, "last_receipt": ""}
                legacy["tracked_quest_id"] = "legacy_preserved"
                save.write_text(json.dumps(legacy, ensure_ascii=False))
                Path(str(save) + ".camp_expected").write_text(json.dumps({
                    "quests": legacy["quests"], "tracked_quest_id": legacy["tracked_quest_id"],
                    "gold": legacy["gold"], "world_seed": legacy["world_seed"],
                    "inventory": legacy["inventory"]}, ensure_ascii=False))
            command = [godot, "--headless", "--path", str(project),
                       "res://tests/camp_pilot_contract_test.tscn", "--quit-after", "20000",
                       "--", f"--cold-{phase}"]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=100)
            output = result.stdout + result.stderr
            print(f"[camp pilot lifecycle: {phase}]", flush=True)
            print(output, end="")
            if result.returncode or "=== CAMP PILOT CONTRACT PASS" not in output \
                    or unexpected_errors("camp_pilot_contract", output):
                return 1
            if not save.is_file():
                print("FAIL isolated pilot save is missing")
                return 1
            current = json.loads(save.read_text())
            if phase == "write":
                ledger = current["camp_quest"]
                if not ledger["investigated"] or len(ledger["kills"]) != 1 or ledger["paid"]:
                    print("FAIL first kill / investigated / unpaid ledger not persisted")
                    return 1
            elif phase == "pending":
                ledger = current["camp_quest"]
                if ledger["stage"] != "completed" or not ledger["paid"] or current["inventory"].get("onigiri") != 99 or not any(r.get("item_id") == "onigiri" and r.get("count", 0) > 0 for r in current.get("pending_items", {}).values()):
                    print("FAIL paid full-inventory contract and pending item were not persisted")
                    return 1
            elif phase == "claim":
                if not current["camp_quest"]["paid"] or current["camp_quest"]["stage"] != "completed":
                    print("FAIL paid ledger not persisted")
                    return 1
                paid = current
            elif phase == "paid" and current != paid:
                print("FAIL paid cold reader changed persisted reward data")
                return 1
        print("=== CAMP PILOT LIFECYCLE PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

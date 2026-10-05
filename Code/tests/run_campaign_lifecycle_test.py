#!/usr/bin/env python3
"""战役实景的独立进程生命周期；不用共享内存/伪造收据替代真实完成。"""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors

PHASES = ("chapter1", "depart", "rune_partial", "runes", "rescue", "beacon99", "claim", "safety", "death", "paid")
C2 = "watch_c2_forest"


def limit_file_size() -> None:
    import resource
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))


def run_phase(godot: str, project: Path, env: dict[str, str], phase: str) -> bool:
    command = [godot, "--headless", "--path", str(project),
               "res://tests/campaign_acceptance_test.tscn", "--quit-after", "160000",
               "--", phase]
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=300,
                            preexec_fn=limit_file_size if phase.startswith("fail_") else None)
    output = result.stdout + result.stderr
    print(f"[campaign lifecycle: {phase}]", flush=True)
    print(output, end="", flush=True)
    return (result.returncode == 0 and "=== CAMPAIGN ACCEPTANCE PASS" in output
            and not unexpected_errors("campaign_acceptance", output))


def stage(data: dict, number: int) -> dict:
    return data.get("campaign_quest", {}).get("quests", {}).get(f"{C2}:s{number}", {})


def evidence(data: dict, number: int, action: str) -> bool:
    return f"{C2}:s{number}:{action}" in stage(data, number).get("evidence", {})


def fail(message: str) -> int:
    print("FAIL " + message, flush=True)
    return 1


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-campaign-lifecycle-") as temp:
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
        snapshots: dict[str, dict] = {}
        manifests: dict[str, str] = {}
        for phase in PHASES:
            if not run_phase(godot, project, env, phase):
                return 1
            if not save.is_file():
                return fail("isolated campaign save is missing")
            current = json.loads(save.read_text())
            snapshots[phase] = current
            manifests[phase] = Path(str(save) + ".campaign_expected").read_text()
            if current.get("campaign_quest", {}).get("id") != "campaign_watch_v1":
                return fail("stable campaign ID is absent from the persisted save")
            if not current.get("outpost_quest", {}).get("evidence", {}).get("next_clue_received"):
                return fail("campaign authority requires preserved genuine chapter 1 clue")
            if phase == "depart" and (not current["campaign_quest"].get("chapters", {}).get(C2)
                                        or evidence(current, 1, "herbalist")):
                return fail("travel accepts chapter 2 but cannot invent the first NPC encounter")
            if phase == "runes" and (not evidence(current, 2, "torn_record")
                                       or evidence(current, 3, "rescue")):
                return fail("opened gate and recovered record cannot invent later rescue")
            if phase == "rune_partial" and (not evidence(current, 2, "route_marks")
                                              or evidence(current, 2, "runes")):
                return fail("first rune must retain only an incomplete sequence, without opening the gate")
            if phase == "rescue" and (not evidence(current, 3, "rescue")
                                        or evidence(current, 4, "beacon")):
                return fail("rescued liaison cannot silently repair the remote beacon")
            if phase == "beacon99" and (not evidence(current, 4, "beacon")
                                          or stage(current, 4).get("receipt", {}).get("paid")):
                return fail("full inventory must preserve beacon completion and unpaid whole reward")
            if phase == "claim" and not stage(current, 4).get("receipt", {}).get("paid"):
                return fail("explicit claim did not persist its one-time paid receipt")
            if phase == "paid" and current != snapshots["death"]:
                return fail("read-only paid cold reader changed persisted world or rewards")
        if sys.platform.startswith("linux"):
            original = save.read_bytes()
            for phase in ("fail_flush", "fail_write"):
                if not run_phase(godot, project, env, phase):
                    return 1
                if save.read_bytes() != original:
                    return fail("real filesystem short-write failure replaced the prior good campaign save")
            if not run_phase(godot, project, env, "paid"):
                return 1
        legacy = json.loads(json.dumps(snapshots["chapter1"]))
        legacy["version"] = 13
        legacy.pop("campaign_quest", None)
        legacy.pop("campaign_min_reader", None)
        save.write_text(json.dumps(legacy, ensure_ascii=False))
        Path(str(save) + ".campaign_expected").write_text(manifests["chapter1"])
        old_bytes = save.read_bytes()
        if not run_phase(godot, project, env, "legacy_v13"):
            return 1
        if save.read_bytes() != old_bytes:
            return fail("reading the completed legacy chapter rewrote its old wallet or world")
        damaged = json.loads(json.dumps(snapshots["claim"]))
        stage(damaged, 2)["evidence"].pop(f"{C2}:s2:route_marks")
        save.write_text(json.dumps(damaged, ensure_ascii=False))
        Path(str(save) + ".campaign_expected").write_text(manifests["claim"])
        if not run_phase(godot, project, env, "invalid_proof"):
            return 1
        # 真实首章完成档承接合法旧委托的UI拓扑夹具；不执行旧奖励支付，预算生命周期另有专测。
        for mode in ("pending", "paused"):
            compat = json.loads(json.dumps(snapshots["chapter1"]))
            target = compat["outpost_quest"].get("target", {})
            target = {key: target[key] for key in ("region_id", "species", "pos", "key", "need", "kill_start") if key in target}
            if not target:
                return fail("real chapter 1 target is required for old-contract UI migration fixture")
            key = target["region_id"] + "|" + target["species"]
            compat["camp_quest"] = {
                "id": "camp_ecology_v1", "version": 1, "active": mode == "pending", "paid": False,
                "last_summary": False, "stage": "return", "investigated": True,
                "choice": "ransack", "outcome": "ransack", "target": target,
                "kills": [], "ransacks": [key], "surveys": [key],
                "history": ["旧营地调查待交付的迁移UI夹具，依据真实首章生态现场"],
                "gold": 39, "xp": 44, "bonus": "onigiri", "paid_gold": 0, "paid_xp": 0, "next_clue": ""}
            compat["version"] = 13
            compat.pop("campaign_min_reader", None)
            save.write_text(json.dumps(compat, ensure_ascii=False))
            Path(str(save) + ".campaign_expected").write_text(manifests["chapter1"])
            prior = save.read_bytes()
            if not run_phase(godot, project, env, "legacy_menu_" + mode):
                return 1
            if save.read_bytes() != prior:
                return fail("old-contract menu review changed persisted rewards")
        future = json.loads(json.dumps(snapshots["death"]))
        future["version"] += 1
        future["campaign_min_reader"] = future["version"]
        future["campaign_quest"]["unknown_future_receipt"] = {"paid": True, "id": "future-chapter-proof"}
        save.write_text(json.dumps(future, ensure_ascii=False))
        prior = save.read_bytes()
        if not run_phase(godot, project, env, "future_reader"):
            return 1
        if save.read_bytes() != prior:
            return fail("older reader overwrote unknown future campaign bytes")
        for phase in ("chapter1_pending", "chapter1_resume_tail"):
            if not run_phase(godot, project, env, phase):
                return 1
        print("=== CAMPAIGN LIFECYCLE PASS ===", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""真实可见拾取/驻站按钮：完成后重开、重建场景、全新Godot进程读档。"""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from run_headless import unexpected_errors


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-pickup-affordances-") as temp:
        root = Path(temp)
        env = os.environ.copy()
        for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            path = root / key.lower()
            path.mkdir()
            env[key] = str(path)
        env["HOTW_TEST_SAVE"] = str(root / "save.json")
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        env.pop("HOTW_OPTIONAL_SNAPSHOT_DIR", None)
        for phase in ("write", "read"):
            env["HOTW_PICKUP_PHASE"] = phase
            result = subprocess.run([godot, "--headless", "--path", str(project),
                "res://tests/pickup_affordance_test.tscn", "--quit-after", "24000"],
                env=env, capture_output=True, text=True, timeout=240)
            output = result.stdout + result.stderr
            print(f"[pickup affordance {phase}]\n{output}", flush=True)
            if result.returncode or "=== PICKUP AFFORDANCE PASS" not in output or unexpected_errors("pickup_affordance", output):
                return 1
            if not Path(env["HOTW_TEST_SAVE"]).is_file():
                print("FAIL missing independently readable GameState save")
                return 1
    print("=== PICKUP AFFORDANCE LIFECYCLE PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

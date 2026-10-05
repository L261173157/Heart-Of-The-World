#!/usr/bin/env python3
"""Five isolated real processes; real rescue/payment, synchronous save lock, IO failure, retry and cold reload."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

def main():
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-dynamic-save-failure-") as temp:
        root = Path(temp)
        env = os.environ.copy()
        for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            path = root / key.lower()
            path.mkdir()
            env[key] = str(path)
        env["HOTW_TEST_SAVE"] = str(root / "save.json")
        total = 0
        phases = ("init", "accept|random_wounded", "progress|random_wounded", "complete|random_wounded", "read_save_failure")
        for phase in phases:
            result = subprocess.run([godot, "--headless", "--path", str(project), "res://tests/campaign_dynamic_save_failure_test.tscn", "--quit-after", "30000", "--", phase], env=env, text=True, capture_output=True, timeout=180)
            output = result.stdout + result.stderr
            print(f"[dynamic write failure: {phase}]\n{output}", end="", flush=True)
            marker = f"CAMPAIGN_DYNAMIC_COLD PASS phase={phase} "
            if result.returncode or marker not in output or "SCRIPT ERROR" in output or "ERROR:" in output:
                return 1
            if phase.startswith("complete") and "CAMPAIGN_DYNAMIC_SAVE_FAILURE_CHECKS PASS" not in output:
                return 1
            total += int(next(line for line in output.splitlines() if line.startswith(marker)).split("checks=")[1].split()[0])
        print(f"=== CAMPAIGN DYNAMIC SAVE FAILURE PASS ({len(phases)} independent processes, {total} checks) ===", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

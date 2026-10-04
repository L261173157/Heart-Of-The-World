#!/usr/bin/env python3
"""前哨实名目标与旧巢边事件凭据的真实独立进程保存往返。"""
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
    with tempfile.TemporaryDirectory(prefix="hotw-outpost-targets-cold-") as temporary:
        root = Path(temporary)
        env = os.environ.copy()
        for key, name in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                          ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            directory = root / name
            directory.mkdir()
            env[key] = str(directory)
        env["HOTW_TEST_SAVE"] = str(root / "save.json")
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        for phase in ("cold-write", "cold-read", "compact-cold-write", "compact-cold-read"):
            result = subprocess.run([godot, "--headless", "--path", str(project),
                                     "res://tests/outpost_live_targets_test.tscn", "--quit-after", "18000",
                                     "--", f"--{phase}"], env=env, capture_output=True,
                                    text=True, timeout=120)
            output = result.stdout + result.stderr
            print(f"[outpost live targets: {phase}]", flush=True)
            print(output, end="", flush=True)
            if result.returncode != 0 or "=== OUTPOST LIVE TARGETS PASS" not in output or unexpected_errors("outpost_live_targets", output):
                return 1
    print("=== OUTPOST LIVE TARGETS LIFECYCLE PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

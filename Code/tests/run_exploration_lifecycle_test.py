#!/usr/bin/env python3
"""细探索真实场景写档→独立Godot进程冷启动；所有用户数据都在临时目录。"""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from run_headless import unexpected_errors

project = Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
with tempfile.TemporaryDirectory(prefix="hotw-exploration-") as sandbox:
    home = Path(sandbox)
    env = os.environ.copy()
    for key, folder in [("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                        ("XDG_CACHE_HOME", "cache"), ("XDG_DATA_HOME", "data")]:
        (home / folder).mkdir()
        env[key] = str(home / folder)
    env["HOTW_TEST_SAVE"] = str(project / "tests/fixtures/test_save.json")
    for phase, marker in [("write", "=== EXPLORATION MAP PASSED"),
                          ("read", "=== EXPLORATION COLD READ PASSED")]:
        env["HOTW_EXPLORATION_STAGE"] = phase
        run = subprocess.run([godot, "--headless", "--path", str(project),
                              "res://tests/exploration_map_test.tscn", "--quit-after", "10000"],
                             env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, timeout=240)
        print(run.stdout)
        if run.returncode or marker not in run.stdout or unexpected_errors("exploration_map", run.stdout):
            raise SystemExit(f"exploration {phase} failed")
print("=== EXPLORATION LIFECYCLE PASSED ===")

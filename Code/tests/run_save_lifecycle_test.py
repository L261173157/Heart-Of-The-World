#!/usr/bin/env python3
"""独立进程存档回归：python3 Code/tests/run_save_lifecycle_test.py "$GODOT"。

仅标准库。每轮隔离 HOME/XDG/存档；Linux 使用 RLIMIT_FSIZE 验证真实短写与
flush 失败（不以无法打开 /dev/full 的情况冒充磁盘写入失败）。其它平台仍跑冷启动。
"""
from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def limit_file_size() -> None:
    import resource
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-save-lifecycle-") as temp:
        sandbox = Path(temp)
        env = os.environ.copy()
        for name, directory in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                                ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            target = sandbox / directory
            target.mkdir()
            env[name] = str(target)
        env["HOTW_TEST_SAVE"] = str(sandbox / "save.json")
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        phases = ["seed", "resume", "verify"]
        if sys.platform.startswith("linux"):
            phases += ["fail_flush", "fail_write"]
        for phase in phases:
            command = [godot, "--headless", "--path", str(project),
                       "res://tests/save_lifecycle_test.tscn", "--quit-after", "300", "--", phase]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30,
                                    preexec_fn=limit_file_size if phase.startswith("fail_") else None)
            output = result.stdout + result.stderr
            print(output, end="")
            if result.returncode or "SCRIPT ERROR" in output or f"SAVE_LIFECYCLE {phase} PASS" not in output:
                return 1
        print("=== 独立进程存档生命周期全部通过 ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

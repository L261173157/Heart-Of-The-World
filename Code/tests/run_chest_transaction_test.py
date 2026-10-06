#!/usr/bin/env python3
"""城塞开箱原子保存：真实流式开箱与独立冷读；隔离 HOME/存档，严格检查每个进程日志。"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_headless import unexpected_errors

MARKER = "=== CHEST TRANSACTION LIFECYCLE PASS ==="


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", nargs="?", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--log-dir", type=Path)
    args = parser.parse_args()
    godot = shutil.which(args.godot)
    if not godot:
        parser.error("Godot executable could not be resolved")
    project = Path(__file__).resolve().parents[1]
    out = (args.log_dir or Path(tempfile.mkdtemp(prefix="hotw-chest-transactions-"))).resolve()
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"fixture": "generated isolated stock; real streamed chests and simulation death API, not combat acceptance",
                "phases": []}
    for relative in ["scripts/main/game_world.gd", "autoload/game_state.gd", "autoload/event_bus.gd",
                     "tests/chest_transaction_test.gd", "tests/chest_transaction_reject_key_state.gd"]:
        manifest.setdefault("source_sha256", {})[relative] = hashlib.sha256((project / relative).read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="hotw-chest-runtime-") as runtime:
        env = os.environ.copy()
        for key in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
            path = Path(runtime) / key.lower()
            path.mkdir()
            env[key] = str(path)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"

        def run(label: str, save: Path, phase: str, *options: str) -> bool:
            env["HOTW_TEST_SAVE"] = str(save)
            before = save.read_bytes() if save.exists() else b""
            command = [godot, "--headless", "--path", str(project),
                       "res://tests/chest_transaction_test.tscn", "--quit-after", "30000", "--", phase, *options]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
            output = result.stdout + result.stderr
            (out / (label + ".log")).write_text(output, encoding="utf-8")
            print(output, end="", flush=True)
            after = save.read_bytes() if save.exists() else b""
            if after:
                (out / (label + ".json")).write_bytes(after)
            errors = unexpected_errors("chest_transaction", output)
            passed = result.returncode == 0 and f"=== CHEST TRANSACTION {phase} PASS" in output and not errors
            if phase == "cold":
                passed = passed and before == after
            manifest["phases"].append({"name": label, "returncode": result.returncode, "passed": passed,
                                       "unexpected_errors": errors,
                                       "input_sha256": hashlib.sha256(before).hexdigest(),
                                       "output_sha256": hashlib.sha256(after).hexdigest()})
            (out / "provenance.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
            return passed

        for terrain in ["hill", "lava"]:
            for stock in ["normal", "full"]:
                name = terrain + "-" + stock
                save = out / (name + "-save.json")
                # 只清理本驱动专属的准确文件，不读取任何真实用户档。
                save.unlink(missing_ok=True)
                Path(str(save) + ".expected").unlink(missing_ok=True)
                outer = "nested" if terrain == "lava" else "direct"
                if not run(name + "-write", save, "write", terrain, stock, outer):
                    return 1
                if not run(name + "-cold", save, "cold"):
                    return 1
        if not run("reject-key", out / "reject-key-save.json", "reject_key"):
            return 1
    print(MARKER, flush=True)
    print("Chest transaction artifacts: " + str(out), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

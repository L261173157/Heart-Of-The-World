#!/usr/bin/env python3
"""真正 GameState 原子写盘→88个全新引擎进程逐阶段/分支读取；不共享账本内存。"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
from run_headless import unexpected_errors


def run(godot: str, project: Path, env: dict[str, str], scene: str, marker: str, log: Path, timeout: int = 240) -> bool:
    result = subprocess.run([godot, "--headless", "--path", str(project), f"res://tests/{scene}.tscn", "--quit-after", "24000"],
                            env=env, capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    log.write_text(output)
    bad = unexpected_errors("campaign_optional", output)
    if result.returncode != 0 or marker not in output or bad:
        print(f"FAIL {scene}: exit={result.returncode}, marker={marker in output}; {log}", flush=True)
        print(output[-10000:], flush=True)
        return False
    return True


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-campaign-optional-") as temp:
        root = Path(temp)
        env = os.environ.copy()
        env.pop("HOTW_OPTIONAL_ONLY", None)
        for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            directory = root / key.lower()
            directory.mkdir()
            env[key] = str(directory)
        snapshots = root / "snapshots"
        snapshots.mkdir()
        logs = Path(os.environ.get("HOTW_OPTIONAL_LOG_DIR", root / "logs"))
        logs.mkdir(parents=True, exist_ok=True)
        env["HOTW_OPTIONAL_SNAPSHOT_DIR"] = str(snapshots)
        env["HOTW_TEST_SAVE"] = str(root / "unused-start.json")
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        if not run(godot, project, env, "campaign_optional_runtime_test", "=== CAMPAIGN OPTIONAL RUNTIME PASS", logs / "producer.log"):
            return 1
        if os.environ.get("HOTW_OPTIONAL_LOG_DIR"):
            shutil.copytree(snapshots, logs / "snapshots", dirs_exist_ok=True)
        manifests = sorted(snapshots.glob("*.expected.json"))
        by_stage = {}
        service_files = []
        route_files = []
        depleted_files = []
        for manifest in manifests:
            expected = json.loads(manifest.read_text())
            sid, branch = expected["stage_id"], expected["branch"]
            if expected["suffix"] == "stage":
                by_stage.setdefault(sid, set()).add(branch)
            elif expected["suffix"] == "service":
                service_files.append(manifest)
            elif expected["suffix"] == "route_resume":
                route_files.append(manifest)
            elif expected["suffix"] == "depleted":
                depleted_files.append(manifest)
        side_count = sum(key.startswith("side_") for key in by_stage)
        region_count = sum(key.startswith("region_") for key in by_stage)
        if side_count != 16 or region_count != 18 or any(value != {0, 1} for value in by_stage.values()) or len(service_files) != 6 or len(route_files) != 12 or len(depleted_files) != 1:
            print(f"FAIL snapshot coverage: side={side_count}, regional={region_count}, service={len(service_files)}, routes={len(route_files)}, depleted={len(depleted_files)}", flush=True)
            return 1
        env.pop("HOTW_OPTIONAL_SNAPSHOT_DIR")
        for index, manifest in enumerate(manifests, 1):
            save = manifest.with_name(manifest.name.removesuffix(".expected.json") + ".json")
            before = save.read_bytes()
            env["HOTW_TEST_SAVE"] = str(save)
            env["HOTW_OPTIONAL_EXPECTED"] = str(manifest)
            if not run(godot, project, env, "campaign_optional_cold_test", "=== CAMPAIGN OPTIONAL COLD PASS", logs / (save.stem + ".log"), 90):
                shutil.copyfile(save, logs / "failed-save.json")
                shutil.copyfile(manifest, logs / "failed-expected.json")
                return 1
            if save.read_bytes() != before:
                print(f"FAIL read-only cold verification altered original save: {save.name}", flush=True)
                return 1
            print(f"optional cold {index}/{len(manifests)} PASS {save.stem}", flush=True)
        for branch in (0, 1):
            save = snapshots / f"region_lava_s3__{branch}__stage.json"
            original = save.read_bytes()
            env["HOTW_TEST_SAVE"] = str(save)
            if not run(godot, project, env, "campaign_optional_host_regression_test", "=== CAMPAIGN OPTIONAL HOST REGRESSION PASS", logs / f"host_branch_{branch}.log", 90):
                return 1
            if save.read_bytes() != original:
                print(f"FAIL full-host cold regression altered original save: {save.name}", flush=True)
                return 1
            print(f"optional full-host cold branch {branch} PASS", flush=True)
        print(f"=== CAMPAIGN OPTIONAL LIFECYCLE PASS ({len(manifests)} snapshot cold starts + 2 full-host cold starts; 16 side + 18 regional stages, both branches, 6 service receipts, 12 interrupted routes, depleted-target closure) ===", flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Normal initial ecology seven-seed outcomes, then real independent cold starts."""
from pathlib import Path
import os
import shutil
import sys
import tempfile
from run_campaign_optional_lifecycle_test import run


def main():
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-optional-outcomes-") as temporary:
        root = Path(temporary)
        env = os.environ.copy()
        env.pop("HOTW_OPTIONAL_ONLY", None)
        env.pop("HOTW_OUTCOME_SEED", None)
        for key in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
            directory = root / key.lower()
            directory.mkdir()
            env[key] = str(directory)
        snapshots = root / "snapshots"
        snapshots.mkdir()
        logs = Path(os.environ.get("HOTW_OUTCOMES_LOG_DIR", root / "logs"))
        logs.mkdir(parents=True, exist_ok=True)
        env.update(HOTW_TEST_SAVE=str(root / "unused.json"), HOTW_OPTIONAL_SNAPSHOT_DIR=str(snapshots), GODOT_SILENCE_ROOT_WARNING="1")
        if not run(godot, project, env, "campaign_optional_outcomes_test", "=== CAMPAIGN OPTIONAL OUTCOMES PASS", logs / "producer.log", 360):
            return 1
        if os.environ.get("HOTW_OUTCOMES_LOG_DIR"):
            shutil.copytree(snapshots, logs / "snapshots", dirs_exist_ok=True)
        manifests = sorted(snapshots.glob("*.expected.json"))
        forest = [path for path in manifests if path.name.startswith("region_forest")]
        if len(forest) != 28:
            print(f"FAIL normal forest snapshot coverage: {len(forest)} instead of 28")
            return 1
        env.pop("HOTW_OPTIONAL_SNAPSHOT_DIR")
        for i, manifest in enumerate(manifests, 1):
            save = manifest.with_name(manifest.name.removesuffix(".expected.json") + ".json")
            original = save.read_bytes()
            env.update(HOTW_TEST_SAVE=str(save), HOTW_OPTIONAL_EXPECTED=str(manifest))
            if not run(godot, project, env, "campaign_optional_cold_test", "=== CAMPAIGN OPTIONAL COLD PASS", logs / (save.stem + ".log"), 90):
                return 1
            if save.read_bytes() != original:
                print(f"FAIL read-only cold check changed original: {save.name}")
                return 1
            print(f"outcomes cold {i}/{len(manifests)} PASS {save.stem}", flush=True)
        print(f"=== CAMPAIGN OPTIONAL OUTCOMES LIFECYCLE PASS ({len(manifests)} independent cold starts; 7 normal existing-camp seeds, bound routes and shared service) ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""78 real process boundaries. Fixture ecology/prerequisites are explicit; payments and scene actions are production code."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
TEMPLATES = ("random_wounded", "random_parcel", "random_sign", "random_rocks", "random_medicine", "random_message", "random_nest", "random_migration", "random_camp", "random_runes")
WORLDS = ("world_relief", "world_watchnet", "world_migration", "world_decline")
PHASES = ["init"] + [f"{operation}|{template}" for template in TEMPLATES for operation in ("accept", "progress", "complete")] + [f"{operation}|random_rocks|{ordinal}" for ordinal in (1,2) for operation in ("accept", "progress", "complete")] + [f"world_{operation}|{world}:s{stage}" for world in WORLDS for stage in range(1,4) for operation in ("accept", "progress", "complete")] + ["service_full", "service_claim", "verify"]
PHASES.insert(PHASES.index("complete|random_rocks"), "rock_cross_partial")
PHASES.insert(PHASES.index("world_accept|world_decline:s1"), "decline_start")
def main():
    godot = sys.argv[1] if len(sys.argv)>1 else os.environ.get("GODOT", "godot")
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="hotw-dynamic-cold-") as directory:
        env=os.environ.copy()
        root=Path(directory)
        for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            path=root/key.lower(); path.mkdir(); env[key]=str(path)
        env["HOTW_TEST_SAVE"]=str(root/"save.json")
        total_checks=0
        for phase in PHASES:
            result=subprocess.run([godot,"--headless","--path",str(project),"res://tests/campaign_dynamic_cold_test.tscn","--quit-after","30000","--",phase],env=env,text=True,capture_output=True,timeout=180)
            output=result.stdout+result.stderr
            print(f"[dynamic cold: {phase}]\n{output}",end="",flush=True)
            marker=f"CAMPAIGN_DYNAMIC_COLD PASS phase={phase} "
            if result.returncode or marker not in output or "SCRIPT ERROR" in output or "ERROR:" in output:
                return 1
            line=next(line for line in output.splitlines() if line.startswith(marker))
            total_checks+=int(line.split("checks=")[1].split()[0])
            data=json.loads((root/"save.json").read_text())
            if "campaign_quest" not in data or "ecology" not in data:
                print("FAIL real save dropped campaign or ecology",flush=True); return 1
        print(f"=== CAMPAIGN DYNAMIC LIFECYCLE PASS ({len(PHASES)} independent processes, {total_checks} checks) ===",flush=True)
        return 0
if __name__=="__main__": raise SystemExit(main())

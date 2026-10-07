#!/usr/bin/env python3
"""字节冻结的旧版实玩档冷读 + 明确标注的部分选择边界夹具，不写真实用户档。"""
from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors

PROJECT = Path(__file__).resolve().parents[1]
FIXTURES = PROJECT / "tests/fixtures/campaign_legacy_endings_v1"
STAGE = "watch_c6_lava:s4"
ACTION = STAGE + ":ending"
MARKER = "=== CAMPAIGN REUNION COMPATIBILITY PASS"
OLD_READER_MARKER = "=== ACTUAL V18 READER WRITE GUARD PASS ==="
# 运行原版项目的真实autoload，不复制/模拟旧读者实现，也不修改该检出。
OLD_READER_PROBE = r'''extends SceneTree
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node = root.get_node("GameState")
	var path := OS.get_environment("HOTW_TEST_SAVE")
	var original := FileAccess.get_file_as_bytes(path)
	var raw: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	var stage := "watch_c6_lava:s4"
	var action := stage + ":ending"
	var constants: Dictionary = game.get_script().get_script_constant_map()
	var q: Dictionary = game.get("campaign_quest")
	var checks := {
		"actual_v18_client": int(constants.get("SAVE_VERSION", 0)) == 18,
		"new_v19_save": int(raw.get("version", 0)) == 19 and int(raw.get("campaign_min_reader", 0)) == 19,
		"earned_conclude_on_disk": raw.campaign_quest.quests[stage].evidence[action].get("kind", "") == "conclude" and raw.campaign_quest.quests[stage].receipt.paid,
		"old_reader_does_not_understand_conclude": not q.quests[stage].evidence.has(action),
		"paid_tombstone_retained": q.quests[stage].receipt.paid,
		"read_only": bool(game.call("equipment_read_only")),
	}
	game.set("gold", int(game.get("gold")) + 1)
	game.set("save_enabled", true)
	checks["manual_refused"] = not bool(game.call("save_now"))
	checks["autosave_refused"] = not bool(game.call("save_now", false))
	game.call("_queue_save")
	game.call("_process", 3.0)
	checks["debounce_dispatched"] = float(game.get("_save_timer")) == 0.0
	checks["original_bytes_unchanged"] = FileAccess.get_file_as_bytes(path) == original
	checks["no_temporary_save"] = not FileAccess.file_exists(path + ".tmp")
	game.set("save_enabled", false)
	var ok := true
	for value: Variant in checks.values(): ok = ok and value == true
	print("ACTUAL_V18_READER ", JSON.stringify(checks))
	print("=== ACTUAL V18 READER WRITE GUARD %s ===" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
'''



def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def materialize(name: str, override: Path | None, target: Path, manifest: dict) -> dict:
    result = {}
    for kind, suffix in (("save", ""), ("expected", ".campaign_expected")):
        info = manifest["fixtures"][name][kind]
        data = Path(str(override) + suffix).read_bytes() if override else gzip.decompress((FIXTURES / info["file"]).read_bytes())
        if not override and (digest(data) != info["sha256"] or len(data) != info["bytes"]):
            raise ValueError("Frozen historical fixture differs: " + info["file"])
        destination = Path(str(target) + suffix)
        destination.write_bytes(data)
        result[kind] = {"path": str(destination), "sha256": digest(data), "bytes": len(data)}
    raw = json.loads(target.read_bytes())
    expected = json.loads(Path(str(target) + ".campaign_expected").read_bytes())
    if raw["campaign_quest"] != expected["campaign"]:
        raise ValueError("Historical sidecar and save disagree: " + name)
    stage = raw["campaign_quest"]["quests"][STAGE]
    if name != "finale":
        proof = stage["evidence"][ACTION]
        if proof.get("kind") != "choice" or proof.get("choice") != name or stage.get("choice") != name or not stage["receipt"]["paid"]:
            raise ValueError("Input is not a genuinely historical selected, completed ending: " + name)
    elif stage["evidence"] or stage["receipt"]["paid"]:
        raise ValueError("Finale input must be an unselected, unpaid checkpoint")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", nargs="?", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--log-dir", type=Path)
    parser.add_argument("--old-project", type=Path, help="Optional unmodified v18 Godot project for an actual old-client write-refusal probe")
    for name in ("distributed", "centralized", "finale"):
        parser.add_argument("--from-" + name, type=Path, help="Override old save with matching .campaign_expected sidecar")
    args = parser.parse_args()
    root = (args.log_dir or Path(tempfile.mkdtemp(prefix="hotw-reunion-compatibility-"))).resolve()
    root.mkdir(parents=True, exist_ok=True)
    source_manifest = json.loads((FIXTURES / "manifest.json").read_bytes())
    report = {"schema": 1, "status": "running", "fixture_label": "Generated isolated test fixtures; not user saves", "sources": {}, "phases": []}
    report_path = root / "manifest.json"
    backups: dict[str, str] = {}

    def write_report() -> None:
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("Reunion compatibility logs: " + str(root), flush=True)
    write_report()
    with tempfile.TemporaryDirectory(prefix="hotw-reunion-runtime-") as temporary:
        env = os.environ.copy()
        for key, leaf in (("HOME", "home"), ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            directory = Path(temporary) / leaf
            directory.mkdir()
            env[key] = str(directory)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        save = root / "save.json"
        env["HOTW_TEST_SAVE"] = str(save)
        expected = Path(str(save) + ".campaign_expected")

        def run(label: str, phase: str) -> bool:
            log = root / (label + ".log")
            command = [args.godot, "--headless", "--path", str(PROJECT), "res://tests/campaign_reunion_compatibility_test.tscn", "--quit-after", "120000", "--", phase]
            original = save.read_bytes()
            before = digest(original)
            entry = {"label": label, "phase": phase, "command": command, "input_sha256": before, "status": "running", "log": str(log)}
            report["phases"].append(entry)
            write_report()
            with log.open("w", encoding="utf-8") as stream:
                try:
                    result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
                    code = result.returncode
                except subprocess.TimeoutExpired:
                    stream.write("\nTIMEOUT 240s\n")
                    code = 124
            output = log.read_text(encoding="utf-8", errors="replace")
            errors = unexpected_errors("campaign_reunion_compatibility", output)
            unchanged = phase != "read" or digest(save.read_bytes()) == before
            saved = json.loads(save.read_bytes())
            schema_ok = saved.get("version") == 19 and saved.get("campaign_min_reader") == 19 and saved.get("equipment_schema") == 1
            current_backups = {str(path): digest(path.read_bytes()) for path in root.glob("save.json.pre-equipment-*.bak")}
            backups_retained = all(current_backups.get(path) == sha for path, sha in backups.items())
            migration_exact = json.loads(original).get("version", 0) >= 19 or before in current_backups.values()
            backups.update(current_backups)
            ok = code == 0 and MARKER in output and not errors and unchanged and schema_ok and backups_retained and migration_exact
            entry.update(status="passed" if ok else "failed", exit=code, marker_found=MARKER in output, errors=errors, output_sha256=digest(save.read_bytes()), read_only_unchanged=unchanged, schema_v19=schema_ok, exact_migration_backup=migration_exact, prior_backups_retained=backups_retained, backups=current_backups)
            write_report()
            print(f"[{label}] exit={code} {'PASS' if ok else 'FAIL'}", flush=True)
            if not ok:
                print(output, flush=True)
            return ok

        def old_reader_probe() -> bool:
            project = args.old_project.resolve()
            if not (project / "project.godot").is_file():
                raise ValueError("--old-project must name the v18 Code project directory")
            # 保存完整新档；让旧客户端直接冷加载，不能只单测消毒函数后推断写保护。
            original = save.read_bytes()
            probe = root / "actual_v18_reader_probe.gd"
            probe.write_text(OLD_READER_PROBE, encoding="utf-8")
            log = root / "actual-v18-reader.log"
            command = [args.godot, "--headless", "--path", str(project), "--script", str(probe), "--quit-after", "300"]
            entry = {"label": "actual-v18-reader", "command": command, "log": str(log), "input_sha256": digest(original)}
            for field, git_args in (("head", ["rev-parse", "HEAD"]), ("tree", ["rev-parse", "HEAD^{tree}"]), ("worktree_status", ["status", "--porcelain"])):
                result = subprocess.run(["git", "-C", str(project), *git_args], capture_output=True, text=True, check=True)
                entry[field] = result.stdout.strip()
            if entry["worktree_status"]:
                raise ValueError("Actual old-reader probe requires an unmodified baseline checkout")
            with log.open("w", encoding="utf-8") as stream:
                try:
                    result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=60)
                    code = result.returncode
                except subprocess.TimeoutExpired:
                    stream.write("\nTIMEOUT 60s\n")
                    code = 124
            output = log.read_text(encoding="utf-8", errors="replace")
            errors = unexpected_errors("campaign_reunion_compatibility", output)
            unchanged = save.read_bytes() == original
            ok = code == 0 and OLD_READER_MARKER in output and not errors and unchanged
            entry.update(status="passed" if ok else "failed", exit=code, errors=errors, output_sha256=digest(save.read_bytes()), exact_bytes_unchanged=unchanged)
            report["old_reader"] = entry
            write_report()
            print(f"[actual-v18-reader] exit={code} {'PASS' if ok else 'FAIL'}", flush=True)
            if not ok:
                print(output, flush=True)
            return ok

        def select(name: str) -> None:
            shutil.copyfile(root / (name + ".json"), save)
            shutil.copyfile(root / (name + ".json.campaign_expected"), expected)

        try:
            for name in ("distributed", "centralized", "finale"):
                report["sources"][name] = materialize(name, getattr(args, "from_" + name), root / (name + ".json"), source_manifest)
            write_report()
            for name in ("distributed", "centralized"):
                select(name)
                if not run(name + "-preserve", "preserve") or not run(name + "-cold-read", "read"):
                    raise RuntimeError("Historical completed ending failed: " + name)
            for name in ("distributed", "centralized"):
                select("finale")
                raw = json.loads(save.read_bytes())
                sidecar = json.loads(expected.read_bytes())
                historical = json.loads((root / (name + ".json")).read_bytes())["campaign_quest"]["quests"][STAGE]
                for campaign in (raw["campaign_quest"], sidecar["campaign"]):
                    campaign["quests"][STAGE]["choice"] = name
                    campaign["quests"][STAGE]["evidence"][ACTION] = copy.deepcopy(historical["evidence"][ACTION])
                save.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
                expected.write_text(json.dumps(sidecar, ensure_ascii=False), encoding="utf-8")
                report["sources"]["synthetic-partial-" + name] = {"label": "Synthetic compatibility boundary, not claimed earned gameplay", "base": "finale", "transplanted_evidence": ACTION, "evidence_source": name, "unchanged_wallet_and_other_progress": True, "input_sha256": digest(save.read_bytes())}
                write_report()
                if not run(name + "-partial-settle", "partial") or not run(name + "-partial-cold-read", "read"):
                    raise RuntimeError("Legacy partial continuation failed: " + name)
            select("finale")
            if not run("new-conclude", "new") or not run("new-conclude-cold-read", "read"):
                raise RuntimeError("Fresh unbranched conclusion failed")
            if args.old_project and not old_reader_probe():
                raise RuntimeError("Actual v18 client did not safely refuse the new save")
            report["status"] = "passed"
            write_report()
            print("=== CAMPAIGN REUNION COMPATIBILITY LIFECYCLE PASS (10 fresh processes) ===", flush=True)
            return 0
        except (OSError, ValueError, KeyError, RuntimeError) as error:
            report.update(status="failed", error=str(error))
            write_report()
            print("FAIL: " + str(error), flush=True)
            return 1


if __name__ == "__main__":
    sys.exit(main())

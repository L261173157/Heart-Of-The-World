#!/usr/bin/env python3
"""从真实 C5 测试存档串联全部任务族，并保留可重放的失败现场。

默认用十三个独立进程真实完成 C1 至 C5；--from-save 只复用同源测试夹具。
所有保留的存档都是生成的隔离测试夹具，不是用户存档。
不编写完成证据、余额、演员或世界状态；结局分支恢复同一真实未决定存档。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_headless import unexpected_errors

FIXTURE_LABEL = "Generated isolated test fixture; not a user save"


def file_info(path: Path) -> dict:
    if not path.is_file():
        return {"exists": False}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"exists": True, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def probe(command: list[str], **kwargs) -> dict:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20, **kwargs)
        return {"exit": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"unavailable": str(error)}


class PhaseEvidence:
    def __init__(self, godot: str, project: Path, root: Path, env: dict[str, str], phase: str):
        self.godot, self.project, self.root, self.env = godot, project, root, env
        self.save = root / "save.json"
        self.expected = Path(str(self.save) + ".campaign_expected")
        self.directory = Path(tempfile.mkdtemp(prefix="evidence-", dir=root))
        self.path = self.directory / "manifest.json"
        engine = shutil.which(godot)
        sources = [project / "project.godot"]
        for child in ("autoload", "scripts", "tests", "data"):
            sources.extend(path for path in (project / child).rglob("*")
                           if path.is_file() and path.suffix in {".gd", ".tscn", ".py", ".tres"})
        self.manifest = {
            "schema": 1, "fixture_label": FIXTURE_LABEL, "requested_phase": phase,
            "status": "running", "engine": {"requested": godot, "resolved": engine,
                "version": probe([godot, "--headless", "--version"], env=env),
                "binary": file_info(Path(engine)) if engine else {"exists": False}},
            "source": {"project": str(project),
                "revision": probe(["git", "rev-parse", "HEAD"], cwd=project),
                "worktree": probe(["git", "status", "--porcelain"], cwd=project),
                "files": {str(path.relative_to(project)): file_info(path) for path in sorted(sources)}},
            "isolated_environment": {key: env[key] for key in
                ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "HOTW_TEST_SAVE")},
            "phases": [], "retained_fixtures": {},
        }
        (self.directory / "README.txt").write_text(
            FIXTURE_LABEL + "\n"
            "所有存档均为生成的隔离测试夹具，绝非用户存档。\n"
            "manifest.json 记录原始命令、引擎、源码与每阶段输入/输出 SHA256。\n"
            "失败或未完成阶段的 *-input.json 及同名 .campaign_expected 是执行前原字节。\n"
            "硬超时可能只留下 running 状态；其输入夹具与实时日志仍可用。\n"
            "重放时将输入两文件复制到新的隔离目录/save.json 及 sidecar，\n"
            "设置新的 HOME/XDG_*、HOTW_TEST_SAVE，再执行 manifest 中该阶段的 command。\n"
            "不得用这些测试夹具替换真实用户存档。\n", encoding="utf-8")
        self.write()
        print("Cross-family evidence: " + str(self.path), flush=True)

    def write(self) -> None:
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.path)

    def snapshot(self, prefix: Path | None = None) -> dict:
        result = {"fixture_label": FIXTURE_LABEL}
        for key, source in (("save", self.save), ("expected", self.expected)):
            info = file_info(source)
            if prefix is not None and info["exists"]:
                target = prefix if key == "save" else Path(str(prefix) + ".campaign_expected")
                shutil.copyfile(source, target)
                info["artifact"] = str(target.relative_to(self.root))
            result[key] = info
        return result

    def retain(self, name: str) -> None:
        self.manifest["retained_fixtures"][name] = self.snapshot(self.root / (name + ".json"))
        self.write()

    def finish(self, status: str, reason: str = "") -> None:
        self.manifest.update(status=status, reason=reason, working_fixture=self.snapshot())
        self.write()

    def run(self, phase: str, scene: str = "campaign_cross_family_test", frames: int = 220000,
            timeout: int = 520, marker: str = "=== CAMPAIGN CROSS FAMILY PASS",
            error_case: str = "campaign_cross_family", label: str | None = None,
            unchanged_save: bool = False) -> bool:
        label = label or phase
        stem = self.directory / f"{len(self.manifest['phases']) + 1:02d}-{label}"
        before = Path(str(stem) + "-input.json")
        log = Path(str(stem) + ".log")
        command = [self.godot, "--headless", "--path", str(self.project),
                   "res://tests/" + scene + ".tscn", "--quit-after", str(frames), "--", phase]
        entry = {"phase": phase, "label": label, "status": "running", "command": command,
                 "timeout_seconds": timeout, "required_marker": marker, "error_case": error_case,
                 "log": str(log.relative_to(self.root)), "input": self.snapshot(before)}
        self.manifest["phases"].append(entry)
        # 先落盘原始字节和清单；外层超时强杀整个进程组后也不会丢失输入。
        self.write()
        timed_out, launch_error = False, ""
        with log.open("w", encoding="utf-8") as stream:
            try:
                result = subprocess.run(command, env=self.env, stdout=stream, stderr=subprocess.STDOUT,
                                        text=True, timeout=timeout)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code, timed_out = 124, True
                stream.write(f"\nTIMEOUT: {timeout}s\n")
            except OSError as error:
                code, launch_error = 1, str(error)
                stream.write("\nFAIL: could not launch phase: " + launch_error + "\n")
        output = log.read_text(encoding="utf-8", errors="replace")
        print(f"[{label}] exit={code}\n{output}", flush=True)
        errors = unexpected_errors(error_case, output)
        after = self.snapshot()
        unchanged = not unchanged_save or entry["input"]["save"].get("sha256") == after["save"].get("sha256")
        ok = code == 0 and marker in output and not errors and unchanged
        entry.update(status="passed" if ok else "failed", exit=code, timed_out=timed_out,
                     launch_error=launch_error, marker_found=marker in output,
                     unexpected_errors=errors, output=after, log_info=file_info(log),
                     read_only_save_unchanged=unchanged if unchanged_save else None)
        if ok:
            # 成功阶段仅留哈希与日志，避免每个大型世界检查点再存两份。
            for key in ("save", "expected"):
                artifact = entry["input"][key].pop("artifact", None)
                if artifact:
                    (self.root / artifact).unlink()
        else:
            entry["output"] = self.snapshot(Path(str(stem) + "-failed-output.json"))
            self.manifest["status"] = "failed"
            if not unchanged:
                print("FAIL: read-only final verification rewrote saved state", flush=True)
        self.write()
        return ok


def run_campaign(args, project: Path, root: Path, runtime: Path) -> int:
    env = os.environ.copy()
    for key, child in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                       ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        path = runtime / child
        path.mkdir()
        env[key] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    save = root / "save.json"
    env["HOTW_TEST_SAVE"] = str(save)
    expected = Path(str(save) + ".campaign_expected")
    evidence = PhaseEvidence(args.godot, project, root, env, args.phase)

    def fail(message: str = "phase failed") -> int:
        evidence.finish("failed", message)
        return 1

    try:
        if args.phase in ("all", "prepare"):
            if args.from_save:
                shutil.copyfile(args.from_save, save)
                shutil.copyfile(Path(str(args.from_save) + ".campaign_expected"), expected)
            else:
                save.unlink(missing_ok=True)
                expected.unlink(missing_ok=True)
                for phase in ("chapter1", "depart", "rune_partial", "runes", "rescue", "beacon99", "claim"):
                    if not evidence.run(phase, "campaign_acceptance_test", 160000, 300,
                                        "=== CAMPAIGN ACCEPTANCE PASS", "campaign_acceptance", "source-" + phase):
                        return fail()
                for phase in ("c3_prepare", "c3_outer_partial", "c3_outer", "c4", "c5_partial", "c5_finish"):
                    if not evidence.run(phase, "campaign_story_acceptance_test", 200000, 420,
                                        "=== CAMPAIGN STORY ACCEPTANCE PASS", "campaign_story", "source-" + phase):
                        return fail()
            source = json.loads(save.read_bytes())
            evidence.manifest["genuine_c5_source"] = evidence.snapshot()
            evidence.write()
            print("Genuine source sha256=" + file_info(save)["sha256"] + " save_version=" + str(source["version"]), flush=True)
        phases = ["prepare", "world", "resume", "finale"] if args.phase == "all" else [args.phase]
        for phase in phases:
            if not evidence.run(phase):
                return fail()
        if args.phase == "all":
            undecided = (save.read_bytes(), expected.read_bytes())
            evidence.retain("finale")
            endings = {}
            for ending in ("distributed", "centralized"):
                save.write_bytes(undecided[0])
                expected.write_bytes(undecided[1])
                if not evidence.run(ending):
                    return fail()
                endings[ending] = json.loads(save.read_bytes())
                evidence.retain(ending)
                if not evidence.run("read", label=ending + "-read", unchanged_save=True):
                    return fail()
            distributed, centralized = endings["distributed"], endings["centralized"]
            for key in ("outpost_quest", "camp_quest"):
                if distributed[key] != centralized[key]:
                    print("FAIL: alternate endings altered legacy state " + key)
                    return fail("alternate endings altered legacy state " + key)
            # 空普通委托可省略存档字段，按载入时的空结构比较。
            empty_quests = {"active": [], "completed": {}, "receipts": {}, "last_receipt": ""}
            if distributed.get("quests", empty_quests) != centralized.get("quests", empty_quests):
                print("FAIL: alternate endings altered ordinary quest state")
                return fail("alternate endings altered ordinary quest state")
            d, c = distributed["campaign_quest"], centralized["campaign_quest"]
            other = lambda q: {key: value for key, value in q["quests"].items() if not key.startswith("watch_")}
            if other(d) != other(c) or d["service_receipts"] != c["service_receipts"]:
                print("FAIL: alternate endings altered another family or service tombstone")
                return fail("alternate endings altered another family or service tombstone")
            print("Cross-ending comparison: identical non-main proofs, rewards, service tombstones and old contracts", flush=True)
            print("=== CAMPAIGN CROSS FAMILY LIFECYCLE PASS (" + str(8 if args.from_save else 21) + " fresh processes) ===", flush=True)
        evidence.finish("passed")
        return 0
    except Exception as error:
        evidence.finish("failed", str(error))
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot")
    parser.add_argument("--from-save", type=Path, help="同源生成的 C5 隔离测试夹具，绝非用户存档")
    parser.add_argument("--log-dir", type=Path)
    parser.add_argument("--phase", default="all")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    root = (args.log_dir or Path(tempfile.mkdtemp(prefix="hotw-campaign-cross-family-"))).resolve()
    root.mkdir(parents=True, exist_ok=True)
    print("Cross-family logs: " + str(root), flush=True)
    # HOME/缓存不进入上传目录；保存的测试证据始终位于显式回归日志目录。
    with tempfile.TemporaryDirectory(prefix="hotw-campaign-cross-family-runtime-") as runtime:
        return run_campaign(args, project, root, Path(runtime))


if __name__ == "__main__":
    sys.exit(main())

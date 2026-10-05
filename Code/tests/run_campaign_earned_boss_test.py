#!/usr/bin/env python3
"""Cold-repeat normal-budget combat from an externally verified genuine C5 save.

This is an acceptance harness, not a fabricated start-to-finish gameplay fixture.
It requires the actual C1-C5 receipt/save artifact. No production files are edited.
"""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from run_headless import unexpected_errors
from run_campaign_cross_family_test import FIXTURE_LABEL, file_info, probe

PROJECT = Path(__file__).resolve().parents[1]
MARKER = "=== CAMPAIGN EARNED BOSS PASS"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class EarnedEvidence:
    """只记录真实测试进程的原始字节；不构造游戏进度。"""

    def __init__(self, root: Path, godot: str, version: str, env: dict[str, str], label: str):
        self.root, self.env = root, env
        self.directory = Path(tempfile.mkdtemp(prefix="evidence-", dir=root))
        self.path = self.directory / "manifest.json"
        sources = [PROJECT / "project.godot"]
        for child in ("autoload", "scripts", "tests", "data"):
            sources.extend(path for path in (PROJECT / child).rglob("*")
                           if path.is_file() and path.suffix in {".gd", ".tscn", ".py", ".tres"})
        self.manifest = {
            "schema": 1, "fixture_label": FIXTURE_LABEL, "suite": label, "status": "running",
            "engine": {"path": godot, "version": version, "binary": file_info(Path(godot))},
            "source": {"project": str(PROJECT),
                "revision": probe(["git", "rev-parse", "HEAD"], cwd=PROJECT),
                "worktree": probe(["git", "status", "--porcelain"], cwd=PROJECT),
                "files": {str(path.relative_to(PROJECT)): file_info(path) for path in sorted(sources)}},
            "isolated_environment": {key: env.get(key) for key in
                ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "HOTW_TEST_SAVE")},
            "phases": [],
        }
        (self.directory / "README.txt").write_text(
            FIXTURE_LABEL + "\n所有存档都是生成的隔离测试夹具，绝非用户存档。\n"
            "失败或未完成阶段的 *-input.json / .campaign_expected 是执行前原字节。\n"
            "清单记录实际命令、超时、完成标记、引擎/源码版本与输入/输出 SHA256。\n"
            "原本缺失的 sidecar 记为 exists=false；重放也必须保持缺失。\n"
            "硬超时可能留下 running 清单，但原输入和实时日志已先落盘。\n"
            "重放时复制输入到新的隔离测试目录，设置 HOME/XDG_* 和 HOTW_TEST_SAVE，\n"
            "再运行该阶段的 command；不得用这些夹具替换用户存档。\n",
            encoding="utf-8")
        self.write()
        print(label + " evidence: " + str(self.path), flush=True)

    def write(self) -> None:
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.path)

    def snapshot(self, checkpoint: Path, prefix: Path | None = None) -> dict:
        result = {"fixture_label": FIXTURE_LABEL, "path": str(checkpoint)}
        for key, source in (("save", checkpoint), ("expected", Path(str(checkpoint) + ".campaign_expected"))):
            info = file_info(source)
            if prefix is not None and info["exists"]:
                target = prefix if key == "save" else Path(str(prefix) + ".campaign_expected")
                shutil.copyfile(source, target)
                info["artifact"] = str(target.relative_to(self.root))
            result[key] = info
        return result

    def discard_copy(self, snapshot: dict) -> None:
        for key in ("save", "expected"):
            artifact = snapshot[key].pop("artifact", None)
            if artifact:
                (self.root / artifact).unlink()

    def finish(self, passed: bool, reason: str = "") -> None:
        self.manifest.update(status="passed" if passed else "failed", reason=reason)
        self.write()

    def run(self, name: str, checkpoint: Path, command: list[str], timeout: int,
            marker: str, error_case: str | None, log: Path,
            driver: bool = False, prefixes: tuple[str, ...] = ()) -> tuple[bool, str, dict]:
        self.env["HOTW_TEST_SAVE"] = str(checkpoint)
        stem = self.directory / f"{len(self.manifest['phases']) + 1:02d}-{name}"
        row = {"name": name, "status": "running", "command": command, "timeout_seconds": timeout,
               "required_marker": marker, "error_case": error_case, "log": str(log.relative_to(self.root)),
               "input": self.snapshot(checkpoint, Path(str(stem) + "-input.json"))}
        self.manifest["phases"].append(row)
        # 输入/sidecar 先落盘，外层强杀整个进程组仍能重放完全相同的字节。
        self.write()
        started = time.monotonic()
        timed_out, launch_error, interrupted = False, "", None
        with log.open("w", encoding="utf-8") as stream:
            try:
                with subprocess.Popen(command, env=self.env, stdout=stream, stderr=subprocess.STDOUT,
                                      text=True) as process:
                    try:
                        code = process.wait(timeout=timeout)
                    except subprocess.TimeoutExpired:
                        timed_out = True
                        # Python 驱动收到 TERM 后先清理当前 Godot；仍属于外层进程组，
                        # 所以注册入口的硬超时也会终止整个进程链。
                        if driver:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill()
                        else:
                            process.kill()
                        process.wait()
                        code = 124
                        stream.write(f"\nTIMEOUT: {timeout}s\n")
                    except BaseException as error:
                        process.kill()
                        process.wait()
                        code, interrupted = 143, error
                        stream.write("\nINTERRUPTED: driver stopped while phase was running\n")
            except OSError as error:
                code, launch_error = 1, str(error)
                stream.write("\nFAIL: could not launch phase: " + launch_error + "\n")
        text = log.read_text(encoding="utf-8", errors="replace")
        errors = unexpected_errors(error_case, text) if error_case is not None else []
        parsed, parse_error = {}, ""
        try:
            for line in text.splitlines():
                for prefix in prefixes:
                    if line.startswith(prefix):
                        parsed[prefix.strip()] = json.loads(line[len(prefix):])
        except ValueError as error:
            parse_error = str(error)
        passed = code == 0 and marker in text and not errors and not parse_error and interrupted is None
        row.update(status="passed" if passed else "failed", passed=passed, returncode=code,
                   wall_seconds=round(time.monotonic() - started, 3), timed_out=timed_out,
                   launch_error=launch_error, parse_error=parse_error, marker_found=marker in text,
                   unexpected_errors=errors, output=self.snapshot(checkpoint), log_info=file_info(log), **parsed)
        if passed:
            self.discard_copy(row["input"])
        else:
            row["output"] = self.snapshot(checkpoint, Path(str(stem) + "-failed-output.json"))
            self.manifest["status"] = "failed"
        self.write()
        if interrupted is not None:
            raise interrupted
        return passed, text, row


def stop_driver(signum, frame) -> None:
    # 上层 1500s 驱动超时触发清理，不留后台 Godot 继续改写失败现场。
    raise SystemExit(128 + signum)


@contextlib.contextmanager
def isolated_runtime(env: dict[str, str]):
    """HOME 与字体/图形缓存不进入上传目录。"""
    with tempfile.TemporaryDirectory(prefix="hotw-earned-runtime-") as temp:
        for key, folder in (("HOME", "home"), ("XDG_CACHE_HOME", "cache"),
                            ("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data")):
            path = Path(temp) / folder
            path.mkdir()
            env[key] = str(path)
        yield

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", type=Path)
    parser.add_argument("genuine_c5_save", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--skip-aged", action="store_true")
    args = parser.parse_args()
    godot = args.godot.resolve()
    source = args.genuine_c5_save.resolve()
    output = args.output.resolve()
    if not source.is_file() or not godot.is_file():
        parser.error("Godot binary and genuine C5 save must exist")
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    with isolated_runtime(env):
        return run_acceptance(args, godot, source, output, env, parser)


def run_acceptance(args, godot, source, output, env, parser) -> int:
    version = subprocess.check_output([str(godot), "--version"], text=True, env=env).strip()
    if not version.startswith("4.7.stable"):
        parser.error("This acceptance requires Godot 4.7 stable, not PATH fallback")
    manifest = {"fixture_label": FIXTURE_LABEL, "engine": version, "source": str(source), "source_sha256": digest(source),
                "harness_sha256": digest(PROJECT / "tests/campaign_earned_boss_test.gd"),
                "results": [], "limitations": [
                    "The source main ledger is genuine; its capacity-fixture inventory is discarded",
                    "Only five verified paid chapter bonus foods are reconstructed; 280 gold buys upgrades",
                    "Ecology and unrelated actors are frozen during isolated live original-Boss combat",
                    "Optional aging advances 1199 normal WorldSim bridge ticks, not human play",
                    "Bot reads AI state and collision geometry; this is not novice difficulty or iPhone QA",
                    "Touch commands include standard Godot mouse-emulation events for ordinary menu tabs",
                    "MoreBtn closes More; MoreClose clipped-row regression is tested separately"]}

    evidence = EarnedEvidence(output, str(godot), version, env, "campaign_earned_boss")
    # 保留来源 sidecar 作为证据，不把原本未输入战斗进程的文件注入其检查点。
    evidence.manifest["genuine_c5_source"] = evidence.snapshot(source, evidence.directory / "source-input.json")
    evidence.write()

    def run(name: str, checkpoint: Path, phase: str, seed: int = 0) -> bool:
        command = [str(godot), "--headless", "--path", str(PROJECT),
                   "res://tests/campaign_earned_boss_test.tscn", "--", phase, str(seed)]
        passed, log, entry = evidence.run(name, checkpoint, command, 900, MARKER,
            "campaign_earned_boss", output / f"{name}.log", prefixes=(
                "EARNED_PREFIGHT ", "EARNED_ECOLOGY_AGING ", "EARNED_COMBAT_RESULT ", "EARNED_STORY_COMPLETE "))
        row = {"name": name, "phase": phase, "rng_seed_offset": seed,
               "input_sha256": entry["input"]["save"].get("sha256"),
               "output_sha256": entry["output"]["save"].get("sha256"),
               "wall_seconds": entry["wall_seconds"], "returncode": entry["returncode"],
               "unexpected_errors": entry["unexpected_errors"], "passed": passed}
        for key in ("EARNED_PREFIGHT", "EARNED_ECOLOGY_AGING", "EARNED_COMBAT_RESULT", "EARNED_STORY_COMPLETE"):
            if key in entry:
                row[key] = entry[key]
        manifest["results"].append(row)
        (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        print(f"{name}: {'PASS' if row['passed'] else 'FAIL'} ({row['wall_seconds']}s wall)", flush=True)
        if not row["passed"]:
            print(log, end="", flush=True)
            evidence.finish(False, name)
        return bool(row["passed"])

    prepared = output / "prepared.json"
    shutil.copy2(source, prepared)
    if not run("prepare", prepared, "prepare"):
        return 1
    reckless = output / "reckless.json"
    shutil.copy2(prepared, reckless)
    if not run("reckless", reckless, "reckless", 2):
        return 1
    first_win = None
    for index in range(max(2, args.repeats)):
        checkpoint = output / f"young-{index+1}.json"
        shutil.copy2(prepared, checkpoint)
        if not run(f"young-{index+1}", checkpoint, "mobile", 11+index):
            return 1
        if first_win is None:
            first_win = checkpoint
    if not args.skip_aged:
        aged = output / "aged.json"
        shutil.copy2(prepared, aged)
        if not run("age", aged, "age", 5):
            return 1
        for index in range(max(2, args.repeats)):
            checkpoint = output / f"aged-{index+1}.json"
            shutil.copy2(aged, checkpoint)
            if not run(f"aged-{index+1}", checkpoint, "mobile", 21+index):
                return 1
    complete = output / "normal-complete.json"
    shutil.copy2(first_win, complete)
    if not run("normal-complete", complete, "finish", 31):
        return 1
    evidence.discard_copy(evidence.manifest["genuine_c5_source"])
    evidence.finish(True)
    print("=== CAMPAIGN EARNED BOSS COLD REPEATS PASS ===")
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop_driver)
    raise SystemExit(main())

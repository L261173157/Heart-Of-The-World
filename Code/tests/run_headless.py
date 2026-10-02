#!/usr/bin/env python3
"""隔离真实存档的 Godot 无头回归入口；退出码、完成标记与运行错误三重守闸。"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
CASES = {
    "smoke": (["--quit"], None),
    "sim": (["-s", "tests/sim_test.gd"], "=== 全部测试通过 ==="),
    "frames": (["-s", "tests/frames_test.gd"], "失败 0）==="),
    "balance": (["-s", "tests/balance_test.gd"], "=== 平衡校验全部通过（带/反推/经济） ==="),
    "combat": (["res://tests/combat_test.tscn", "--quit-after", "100000"], "=== 战斗验证全部通过 ==="),
    "save": (["res://tests/save_test.tscn", "--quit-after", "5000"], "=== 存档验证全部通过 ==="),
    "save_lifecycle": ([str(PROJECT / "tests/run_save_lifecycle_test.py")], "=== 独立进程存档生命周期全部通过 ==="),
    "ui_flow": (["res://tests/ui_flow_test.tscn", "--quit-after", "8000"], "=== UI 流程冒烟全部通过 ==="),
    "projectile": (["res://tests/projectile_pool_test.tscn", "--quit-after", "5000"], "=== 弹幕池生命周期验证全部通过 ==="),
    "world": (["res://tests/world_persistence_test.tscn", "--quit-after", "10000"], "=== 世界持久化回归全部通过 ==="),
    "ui_visual": (["res://tests/ui_visual_test.tscn", "--quit-after", "8000"], "=== UI VISUAL REGRESSION PASSED"),
    "menu_layout": (["res://tests/menu_layout_test.tscn", "--quit-after", "8000"], "=== MENU LAYOUT REGRESSION PASSED"),
    "actor_alignment": (["res://tests/actor_alignment_test.tscn", "--quit-after", "10000"], "=== ACTOR ALIGNMENT PASS"),
    "animation": (["res://tests/animation_polish_test.tscn", "--quit-after", "8000"], "=== ANIMATION POLISH PASS"),
    "gameplay_combat": (["res://tests/gameplay_combat_test.tscn", "--quit-after", "100000"], "=== GAMEPLAY COMBAT PASS"),
    "gameplay_ecology": (["res://tests/gameplay_ecology_test.tscn", "--quit-after", "10000"], "=== 玩法生态回归全部通过"),
    "gameplay_world": (["res://tests/gameplay_world_test.tscn", "--quit-after", "10000"], "=== 玩法世界回归全部通过"),
    "gameplay_equipment": (["res://tests/gameplay_equipment_test.tscn", "--quit-after", "10000"], "=== GAMEPLAY EQUIPMENT PASSED"),
    "gameplay_navigation": (["res://tests/gameplay_navigation_test.tscn", "--quit-after", "10000"], "=== GAMEPLAY NAVIGATION PASSED"),
    "boss_age_balance": (["res://tests/boss_age_balance_test.tscn", "--quit-after", "100000"], "=== BOSS AGE BALANCE PASS"),
    "ecology_feedback": (["res://tests/ecology_feedback_test.tscn", "--quit-after", "10000"], "=== ECOLOGY FEEDBACK PASSED"),
    "gameplay_choices_ui": (["res://tests/gameplay_choices_ui_test.tscn", "--quit-after", "10000"], "=== GAMEPLAY CHOICES UI PASSED"),
    "gameplay_tasks": (["res://tests/gameplay_tasks_test.tscn", "--quit-after", "10000"], "=== GAMEPLAY TASKS PASSED"),
    "mobile_controls": (["res://tests/mobile_controls_test.tscn", "--quit-after", "10000"], "=== MOBILE CONTROLS PASSED"),
    "combat_feedback": (["res://tests/combat_feedback_test.tscn", "--quit-after", "10000"], "=== COMBAT FEEDBACK PASS"),
    "town_interaction": (["res://tests/town_interaction_test.tscn", "--quit-after", "10000"], "=== TOWN INTERACTION PASS"),
    "quest_clarity": (["res://tests/quest_clarity_test.tscn", "--quit-after", "10000"], "=== QUEST CLARITY PASSED"),
    "quest_lifecycle": ([str(PROJECT / "tests/run_quest_lifecycle_test.py")], "=== QUEST LIFECYCLE PASSED ==="),
    "directional_attack": (["res://tests/directional_attack_test.tscn", "--quit-after", "10000"], "=== DIRECTIONAL ATTACK PASS"),
    "weapon_effects": (["res://tests/weapon_effects_test.tscn", "--quit-after", "10000"], "=== WEAPON EFFECTS PASS"),
    "terrain_coherence": (["-s", "tests/terrain_coherence_test.gd"], "=== TERRAIN COHERENCE PASS"),
    "exploration_lifecycle": ([str(PROJECT / "tests/run_exploration_lifecycle_test.py")], "=== EXPLORATION LIFECYCLE PASSED ==="),
    "exploration_map": (["res://tests/exploration_map_test.tscn", "--quit-after", "10000"], "=== EXPLORATION MAP PASSED"),
    "knockback_response": (["res://tests/knockback_response_test.tscn", "--quit-after", "10000"], "=== KNOCKBACK RESPONSE PASS"),
    "pacing": (["res://tests/pacing_test.tscn", "--quit-after", "100000"], "=== 节奏验证全部通过 ==="),
}

# 已在修改前的 4.7 基线逐项记录：仅允许退出清理诊断，不放过物理/解析/运行错误。
EXIT_DIAGNOSTICS = (
    re.compile(r"ERROR: \d+ resources still in use at exit \(run with --verbose for details\)\."),
    re.compile(r"ERROR: \d+ RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit\."),
)

# Godot 4.7 的 ThemeDB 在首次资源导入之前读取项目默认字体。干净检出没有
# fontdata 时会先报这四条、随后成功导入字体。只允许引导轮的精确已知诊断；
# 紧接的第二轮严格导入及所有游戏测试仍拒绝它们，不能把真实缺字库当作通过。
_FONT_CACHE = "res://.godot/imported/NotoSansSC-Regular.ttf-4b8abad24b3b7f136d93d4ff5bc17cfc.fontdata"
BOOTSTRAP_DIAGNOSTICS = {
    f"ERROR: Cannot open file '{_FONT_CACHE}'.",
    f"ERROR: Failed loading resource: {_FONT_CACHE}.",
    "ERROR: Failed loading resource: res://assets/fonts/NotoSansSC-Regular.ttf.",
    "ERROR: Error loading custom project font 'res://assets/fonts/NotoSansSC-Regular.ttf'",
}


def unexpected_errors(case: str, output: str) -> list[str]:
    bad = []
    for line in output.splitlines():
        # Steam 版 Godot 在 Steam 客户端未运行（沙盒 HOME 也连不上 IPC）时打印
        # [S_API] 运行时消息，属发行版噪音而非脚本/物理/解析错误；官方版与 CI 无此输出。
        if line.startswith("[S_API"):
            continue
        if "SCRIPT ERROR:" in line or re.search(r"\bFAIL\b", line):
            bad.append(line)
        elif line.startswith("ERROR:"):
            if case == "bootstrap_import" and line in BOOTSTRAP_DIAGNOSTICS:
                continue
            if any(pattern.fullmatch(line) for pattern in EXIT_DIAGNOSTICS):
                continue
            # save_test 故意输入半截 JSON，验证旧进度保持不变；只豁免此精确诊断。
            if case == "save" and line == "ERROR: Parse JSON failed. Error at line 0: Unexpected character":
                continue
            bad.append(line)
    return bad


def run_case(name: str, args: list[str], marker: str | None, env: dict[str, str],
             godot: str, logs: Path, timeout: int) -> bool:
    command = ([sys.executable, args[0], godot] if name in {"save_lifecycle", "quest_lifecycle", "exploration_lifecycle"}
               else [godot, "--headless", "--path", str(PROJECT), *args])
    print(f"[{name}] 开始", flush=True)
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True,
                          start_new_session=os.name == "posix") as process:
        try:
            output, _ = process.communicate(timeout=timeout)
            code = process.returncode
        except subprocess.TimeoutExpired:
            # 冷启动回归会再起一个 Godot；只杀父进程会遗留子进程与管道，
            # communicate 继续等管道关闭，实际绕过时间上限。POSIX 整组终止。
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            output, _ = process.communicate()
            output += f"\nTIMEOUT: {timeout}s\n"
            code = 124
    (logs / f"{name}.log").write_text(output, encoding="utf-8")
    errors = unexpected_errors(name, output)
    complete = marker is None or marker in output
    passed = code == 0 and complete and not errors
    print(f"[{name}] {'PASS' if passed else 'FAIL'} exit={code} completed={complete} "
          f"unexpected_errors={len(errors)} log={logs / (name + '.log')}", flush=True)
    if name == "bootstrap_import":
        count = sum(line in BOOTSTRAP_DIAGNOSTICS for line in output.splitlines())
        if count:
            print(f"[bootstrap_import] 初次字体就绪前诊断 {count} 条；下一轮仍须严格通过", flush=True)
    if not passed:
        print("\n".join(errors[:20]), flush=True)
        print("\n".join(output.splitlines()[-50:]), flush=True)
    return passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--only", help="逗号分隔的测试名；默认全部")
    parser.add_argument("--log-dir", type=Path, default=Path(tempfile.mkdtemp(prefix="hotw-test-logs-")))
    parser.add_argument("--timeout", type=int, default=900, help="每项检查的秒数上限")
    opts = parser.parse_args()
    names = opts.only.split(",") if opts.only else list(CASES)
    unknown = set(names) - CASES.keys()
    if unknown:
        parser.error("未知测试：" + ", ".join(sorted(unknown)))
    godot = shutil.which(opts.godot)
    if not godot:
        parser.error("未找到 Godot：" + opts.godot)
    logs = opts.log_dir.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    with tempfile.TemporaryDirectory(prefix="hotw-test-state-") as temp:
        base = Path(temp)
        env = os.environ.copy()
        # Godot 在 Linux 以 XDG 路径为准；HOME 与启动档也单独配置，供子进程继承。
        for key, relative in {"HOME": "home", "XDG_CONFIG_HOME": "config",
                              "XDG_CACHE_HOME": "cache", "XDG_DATA_HOME": "data"}.items():
            path = base / relative
            path.mkdir()
            env[key] = str(path)
        env.pop("HOTW_TEST_SAVE", None)
        version = subprocess.run([godot, "--headless", "--version"], env=env,
                                 capture_output=True, text=True, check=True).stdout.strip()
        print("Godot:", version, flush=True)
        # 冷检出先完成资源引导，再以严格模式重新启动核验；游戏测试没有豁免。
        if not run_case("bootstrap_import", ["--editor", "--import"], None, env, godot, logs, opts.timeout):
            return 1
        if not run_case("import", ["--editor", "--import"], None, env, godot, logs, opts.timeout):
            return 1
        for name in names:
            # 启动夹具也复制到沙盒：即使某测试意外启用保存，也不会覆盖仓库夹具。
            startup = base / f"{name}-startup.json"
            shutil.copyfile(PROJECT / "tests/fixtures/test_save.json", startup)
            env["HOTW_TEST_SAVE"] = str(startup)
            args, marker = CASES[name]
            results.append(run_case(name, args, marker, env, godot, logs, opts.timeout))
    print(f"完成：{sum(results)}/{len(results)} 通过；日志 {logs}", flush=True)
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())

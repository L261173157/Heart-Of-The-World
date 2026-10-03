#!/usr/bin/env python3
"""保证显式 CI 分组完整覆盖默认回归入口，新增测试不得只在本地运行。"""
from collections import Counter
from pathlib import Path
import re
from run_headless import CASES


def coverage_errors(workflow: str, cases: set[str]) -> list[str]:
    assigned = Counter(
        name.strip()
        for group in re.findall(r"^\s+tests:\s*([^\n]+)$", workflow, re.MULTILINE)
        for name in group.strip(" '\"").split(",")
        if name.strip()
    )
    errors = []
    if missing := cases - assigned.keys():
        errors.append("CI missing: " + ", ".join(sorted(missing)))
    if unknown := assigned.keys() - cases:
        errors.append("CI unknown: " + ", ".join(sorted(unknown)))
    if repeated := {name for name, count in assigned.items() if count != 1}:
        errors.append("CI duplicated: " + ", ".join(sorted(repeated)))
    return errors


def main() -> int:
    workflow = Path(__file__).resolve().parents[2] / ".github/workflows/godot-tests.yml"
    errors = coverage_errors(workflow.read_text(encoding="utf-8"), set(CASES))
    if errors:
        print("\n".join(errors))
        return 1
    print(f"CI coverage PASS: all {len(CASES)} regression suites assigned exactly once")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

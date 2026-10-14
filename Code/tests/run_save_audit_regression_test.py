#!/usr/bin/env python3
"""审计存档回归；隔离存档，各阶段真实独立进程，保留全部失败证据。"""
from __future__ import annotations
import argparse, json, os, pathlib, re, subprocess, tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('godot', nargs='?', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--log-dir', type=pathlib.Path)
    parser.add_argument('--baseline', action='store_true')
    args = parser.parse_args()
    project = pathlib.Path(__file__).resolve().parents[1]
    out = args.log_dir or pathlib.Path(tempfile.mkdtemp(prefix='hotw-save-audit-'))
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for name in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        target = out / name.lower(); target.mkdir(exist_ok=True); env[name] = str(target)
    env['GODOT_SILENCE_ROOT_WARNING'] = '1'
    save = out / 'save.json'; env['HOTW_TEST_SAVE'] = str(save)
    errors = []
    def run(phase, label=None):
        label = label or phase
        proc = subprocess.run([args.godot, '--headless', '--path', str(project),
            'res://tests/save_audit_regression_test.tscn', '--quit-after', '1000', '--', phase],
            env=env, capture_output=True, text=True, timeout=90)
        output = proc.stdout + proc.stderr; (out / (label + '.log')).write_text(output)
        marker = 'SAVE_AUDIT quit BUTTON' if phase == 'quit' else f'SAVE_AUDIT {phase} PASS'
        ok = proc.returncode == 0 and 'SCRIPT ERROR' not in output and marker in output
        for line in output.splitlines():
            if line.startswith('ERROR:') and not re.match(r'ERROR: \d+ (resources still in use|RID allocations)', line):
                ok = False
        print(f'{label}: {"PASS" if ok else "FAIL"}')
        if not ok: errors.append(label)
        return ok
    run('seed')
    seed_bytes = save.read_bytes()
    values = [('string', 'false', False), ('array', [], False), ('dict', {}, False), ('null', None, False),
              ('true', True, True), ('false', False, False), ('one', 1, True), ('zero', 0, False), ('negative', -1, False)]
    for label, value, expected in values:
        data = json.loads(seed_bytes); data['tutorial'] = {'welcome': value, 'other': True}
        save.write_text(json.dumps(data, ensure_ascii=False))
        env['HOTW_EXPECT_FLAG'] = '1' if expected else '0'
        run('tutorial', 'tutorial_' + label)
        after = json.loads(save.read_bytes())
        if len(after['equipment_state']['items']) != 1 or after.get('inventory', {}).get('onigiri') != 3:
            errors.append('tutorial_disk_' + label)
    save.write_bytes(seed_bytes)
    run('load_guard')
    save.write_text('[]')
    run('load_invalid_root')
    save.unlink()
    run('generation_new')
    run('generation_current')
    data = json.loads(seed_bytes); data.pop('world_generation', None); data['version'] = data['campaign_min_reader'] = 19
    save.write_text(json.dumps(data)); run('generation_legacy')
    for label, value in [('future', 99), ('fraction', 1.5), ('string', '2'), ('null', None)]:
        data = json.loads(seed_bytes); data['world_generation'] = value
        save.write_text(json.dumps(data)); run('generation_future', 'generation_' + label)
    # 后续新冒险先回到受支持的冷启动输入。
    save.write_bytes(seed_bytes)
    for phase in ['midnight_seed', 'midnight_resume', 'quit']:
        run(phase)
    if abs(json.loads(save.read_bytes())['settings']['volume'] - .15) > .0001:
        errors.append('quit_disk'); print('quit_disk: FAIL')
    for phase in ['quit_failure', 'reset_failure', 'reset_resume', 'zero_seed', 'zero_resume']:
        run(phase)
    for label, value, expected in [('negative', -5, 0), ('missing', None, 30)]:
        data = json.loads(seed_bytes)
        if value is None: data.pop('lifespan_days', None)
        else: data['lifespan_days'] = value
        save.write_text(json.dumps(data)); env['HOTW_EXPECT_LIFE'] = str(expected)
        run('life_bounds', 'life_' + label)
    (out / 'result.json').write_text(json.dumps({'failures': errors, 'baseline': args.baseline}, indent=2))
    print(f'=== SAVE AUDIT LIFECYCLE {"FAIL" if errors else "PASS"} ({len(errors)} failures) ===')
    return 0 if not errors or args.baseline else 1

if __name__ == '__main__': raise SystemExit(main())

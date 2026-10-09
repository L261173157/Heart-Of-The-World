#!/usr/bin/env python3
"""正式场景战斗取证，需真实图形display；无头只能单独验证状态，不能通过视觉门禁。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from run_headless import unexpected_errors

EXPECTED = {
    'hud_idle', 'hud_settled', 'enemy_stagger_light', 'enemy_stagger_heavy', 'enemy_stagger_cleared',
    *[f'hero_{action}_{phase}' for action in ['light', 'heavy', 'bolt'] for phase in ['windup', 'impact', 'recovery']],
    *[f'enemy_{action}_{phase}' for action in ['melee', 'ranged'] for phase in ['windup', 'impact', 'recovery']],
    'enemy_charge_windup', 'enemy_charge_active', 'enemy_charge_recovery',
    *[f'boss_{action}_{phase}' for action in ['stomp', 'sweep', 'eruption'] for phase in ['windup', 'impact', 'recovery']],
    'boss_phase_transition', 'boss_phase_two_ready',
}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('godot', nargs='?', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--log-dir', type=Path, required=True)
    parser.add_argument('--state-only', action='store_true', help='只验取证状态路径，不替代图形门禁')
    args = parser.parse_args()
    if not args.state_only and not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
        print('COMBAT FEEL VISUAL BLOCKED: real graphics display required (use xvfb-run).')
        return 1
    out = args.log_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[1]
    provenance = {'fixture': 'Generated isolated encounter, no user save', 'state_only': args.state_only,
        'renderer': 'headless state checks only' if args.state_only else 'Godot 4.7 Linux OpenGL compatibility',
        'scope': 'No iOS/Metal, thermal, or physical touch-device acceptance',
        'fixed_simulation_fps': 60, 'time_scale': 0.35,
        'timing_note': 'Deterministic simulation-per-render capture; not an actual FPS/performance measurement',
        'runs': [], 'sources': {}}
    for path in sorted(project.rglob('*.gd')):
        provenance['sources'][str(path.relative_to(project))] = hashlib.sha256(path.read_bytes()).hexdigest()
    sizes = [(1280, 720), (1560, 720), (1024, 640)]
    try:
        with tempfile.TemporaryDirectory(prefix='hotw-combat-capture-') as temp:
            env = os.environ.copy()
            for key in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
                path = Path(temp) / key.lower()
                path.mkdir()
                env[key] = str(path)
            env['HOTW_TEST_SAVE'] = str(Path(temp) / 'isolated-save.json')
            for width, height in sizes:
                tag = f'{width}x{height}'
                folder = out / tag
                folder.mkdir(exist_ok=True)
                extra = {'HOTW_COMBAT_VISUAL_DIR': str(folder), 'HOTW_COMBAT_VISUAL_SIZE': tag,
                    'HOTW_COMBAT_VISUAL_HEADLESS': '1' if args.state_only else '0'}
                command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--fixed-fps', '60']
                command += ['--headless'] if args.state_only else ['--rendering-method', 'gl_compatibility']
                command += ['res://tests/combat_feel_visual.tscn', '--quit-after', '18000']
                with (folder / 'engine.log').open('w') as log:
                    result = subprocess.run(command, env=env | extra, text=True, stdout=log, stderr=subprocess.STDOUT, timeout=240)
                output = (folder / 'engine.log').read_text()
                errors = unexpected_errors('combat_feel_visual', output)
                mode = 'STATE' if args.state_only else 'VISUAL'
                passed = result.returncode == 0 and f'=== COMBAT FEEL {mode} PASS' in output and not errors
                if not args.state_only:
                    passed = passed and 'OpenGL API' in output
                run = {'size': [width, height], 'returncode': result.returncode, 'passed': passed,
                    'unexpected_errors': errors, 'files': []}
                provenance['runs'].append(run)
                if not passed:
                    print(output)
                    raise RuntimeError(f'{tag}: capture did not complete cleanly')
                states = json.loads((folder / 'states.json').read_text())
                names = {entry['name'] for entry in states['captures']}
                if names != EXPECTED or states['failures'] or states['headless_state_only'] != args.state_only:
                    raise RuntimeError(f'{tag}: incomplete or invalid state evidence: missing={EXPECTED - names}')
                if not args.state_only:
                    for name in sorted(EXPECTED):
                        path = folder / (name + '.png')
                        data = path.read_bytes()
                        if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (width, height):
                            raise RuntimeError(f'{path}: invalid native PNG size')
                        run['files'].append({'file': str(path.relative_to(out)), 'bytes': len(data),
                            'sha256': hashlib.sha256(data).hexdigest()})
                print(f'{tag}: PASS ({len(names)} captured stages)', flush=True)
        print(f'=== COMBAT FEEL {"STATE PATH" if args.state_only else "RENDERED VISUAL"} PASS ===')
        return 0
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f'COMBAT FEEL CAPTURE FAILED: {exc}')
        return 1
    finally:
        (out / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    raise SystemExit(main())

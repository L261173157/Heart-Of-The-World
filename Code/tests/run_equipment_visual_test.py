#!/usr/bin/env python3
"""真实 OpenGL 装备视觉回归；需现有 DISPLAY 或通过 xvfb-run 启动。

使用引擎固定尺寸 SubViewport，检查原生PNG尺寸、真实粒子像素、终态与错误日志。
产物只含生成的游戏测试场景；不读取/上传用户存档或HOME。
"""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, re, struct, subprocess, tempfile
from run_headless import unexpected_errors

def png_size(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'Invalid native PNG: {path.name}')
    return struct.unpack('>II', data[16:24])

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('godot', nargs='?', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--log-dir', type=pathlib.Path, required=True)
    args = parser.parse_args()
    out = args.log_dir.resolve(); out.mkdir(parents=True, exist_ok=True)
    project = pathlib.Path(__file__).resolve().parents[1]
    if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        print('EQUIPMENT RENDER BLOCKED: a real graphics display is required')
        return 1
    runtime = pathlib.Path(tempfile.mkdtemp(prefix='hotw-equipment-render-'))
    env = os.environ.copy()
    for key in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        path = runtime/key.lower(); path.mkdir(); env[key] = str(path)
    env['HOTW_TEST_SAVE'] = str(runtime/'isolated-generated-save.json')
    manifest = {'fixture': 'Generated isolated engine scenes, not a player save', 'renderer':'Godot4.7 OpenGL compatibility', 'files':[], 'phases':[], 'sources':{}}
    for path in sorted(project.rglob('*.gd')):
        manifest['sources'][str(path.relative_to(project))]=hashlib.sha256(path.read_bytes()).hexdigest()
    expected: dict[pathlib.Path, tuple[int,int]] = {}
    def run(name: str, scene: str, marker: str, extra: dict[str,str]) -> str:
        command=[args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', f'res://tests/{scene}', '--quit-after', '12000']
        try:
            result=subprocess.run(command, env=env|extra, capture_output=True, text=True, timeout=120)
            output=result.stdout+result.stderr
            (out/(name+'.log')).write_text(output)
            errors=unexpected_errors(name, output)
            passed=result.returncode==0 and marker in output and not errors and 'OpenGL API' in output
            manifest['phases'].append({'name':name,'returncode':result.returncode,'passed':passed,'unexpected_errors':errors})
            (out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
            print(f'{name}: {"PASS" if passed else "FAILED"}', flush=True)
            if not passed:
                print(output); raise RuntimeError(name+' did not complete cleanly')
            return output
        except subprocess.TimeoutExpired as exc:
            (out/(name+'.log')).write_text(str(exc.stdout or '')+'\n'+str(exc.stderr or '')+'\nVISUAL TIMEOUT\n')
            raise
    try:
        combat = out/'combat'; combat.mkdir(exist_ok=True)
        for tag, size, reduced in [('16x9',(1280,720),False),('19_5x9',(1560,720),False),('16x10',(1024,640),False),('16x9',(1280,720),True)]:
            suffix='_reduced' if reduced else ''
            diagnostic=tag=='16x9' and not reduced
            extra={'HOTW_EQUIPMENT_SHOT_DIR':str(combat),'HOTW_EQUIPMENT_SHOT_TAG':tag,'HOTW_EQUIPMENT_SHOT_SIZE':f'{size[0]}x{size[1]}','HOTW_EQUIPMENT_REDUCED':'1' if reduced else '0','HOTW_EQUIPMENT_PARTICLE_DIAGNOSTIC':'1' if diagnostic else '0'}
            output=run('combat-'+tag+suffix,'equipment_combat_visual.tscn','=== EQUIPMENT VISUAL PASS ===',extra)
            for kind in ['hit','block','orange']:
                expected[combat/f'equipment_{tag}_{kind}{suffix}.png']=size
            if diagnostic:
                proof=re.search(r'EQUIPMENT_PARTICLE_PIXELS (\d+)',output)
                if not proof or int(proof.group(1))<=0: raise RuntimeError('Actual rendered particle pixels were not proven')
                manifest['particle_pixels']=int(proof.group(1))
                expected[combat/f'equipment_{tag}_orange_particles.png']=size
        bag = out/'bag'; bag.mkdir(exist_ok=True)
        run('bag','equipment_bag_visual.tscn','=== EQUIPMENT BAG VISUAL PASS ===',{'HOTW_EQUIPMENT_BAG_SHOT_DIR':str(bag)})
        for size in [(1280,720),(1560,720),(1024,640)]:
            for state in ['loadout','gear','confirm']:
                expected[bag/f'{size[0]}x{size[1]}-{state}.png']=size
        for state in ['craft','caps','white','preset','pending']:
            expected[bag/f'1280x720-{state}.png']=(1280,720)
        for path, size in expected.items():
            actual=png_size(path)
            if actual!=size:raise ValueError(f'{path.name}: {actual} != {size}')
            manifest['files'].append({'file':str(path.relative_to(out)),'size':actual,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        (out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
        print(f'=== EQUIPMENT RENDERED VISUAL PASS ({len(expected)} native PNGs, {manifest["particle_pixels"]} particle pixels) ===')
        return 0
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print(f'EQUIPMENT RENDER FAILED: {exc}')
        return 1
if __name__=='__main__':raise SystemExit(main())

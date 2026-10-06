#!/usr/bin/env python3
"""Graphical Godot quest/pickup evidence, native viewport PNGs, strict logs and provenance.

Requires a real desktop DISPLAY (or caller-provided Xvfb). This is Linux/OpenGL
rendered evidence, not iPhone/Metal or unassisted traversal/playability evidence.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import struct
import subprocess
import tempfile
from run_headless import unexpected_errors

PROJECT = Path(__file__).resolve().parents[1]
MARKER = '=== QUEST PICKUP FEEDBACK VISUAL PASS'
REQUIRED = ['00-actionable-outpost-hud', 'task-list-outpost', 'task-details-outpost',
            'world-aid_bag', 'after-aid_bag', 'world-repair_tools', 'after-repair_tools',
            'read-clue-retained', 'completion-toast', 'overflow-receipt',
            'campaign-actionable-hud', 'task-list-campaign', 'task-details-campaign', 'campaign-empty-container', 'shared-supply-before', 'shared-claimed-world-region_plains-station', 'shared-claimed-world-region_plains-work_outer', 'shared-claimed-menu-region_plains-station', 'shared-claimed-menu-region_plains-work_outer']

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def sources() -> dict[str, str]:
    files = set()
    for root in ['scripts', 'autoload', 'scenes']:
        for ext in ['*.gd', '*.tscn']:
            files.update((PROJECT/root).rglob(ext))
    files.update(PROJECT/'tests'/name for name in ['quest_pickup_feedback_visual.gd', 'quest_pickup_feedback_visual.tscn', 'run_quest_pickup_visual_test.py'])
    files.update((PROJECT/'assets/fonts').glob('*.ttf'))
    files.add(PROJECT/'project.godot')
    return {str(path.relative_to(PROJECT)): sha(path) for path in sorted(files)}

def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'Not a native PNG: {path}')
    return struct.unpack('>II', data[16:24])

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('godot', nargs='?', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--log-dir', type=Path, required=True)
    parser.add_argument('--sizes', default='1280x720,1560x720,1024x640')
    parser.add_argument('--timeout', type=int, default=600)
    opts = parser.parse_args()
    binary = shutil.which(opts.godot)
    if not binary: parser.error("Godot executable not found: " + opts.godot)
    opts.godot = binary
    out = opts.log_dir.resolve(); out.mkdir(parents=True, exist_ok=True)
    if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        print('QUEST PICKUP RENDER BLOCKED: actual graphics display required')
        return 1
    manifest = {'fixture':'Generated isolated state; first chapter uses actual node interactions, touch confirmation, and actual nest attacks. Camera teleports and frozen enemy/eco AI. Declared ordinary ransack quest verifies real auto-settlement. Overflow uses prefilled98 + actual3 transaction. Campaign supplemental uses explicitly seeded prerequisites.',
                'limitations':['Not iPhone or Metal evidence', 'Not unassisted route traversal or pacing evidence'],
                'engine_path':opts.godot,'engine_sha256':sha(Path(opts.godot)),
                'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=PROJECT,text=True).strip(),
                'sources':sources(), 'phases':[], 'files':[]}
    def write_manifest() -> None:
        (out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    def run(name: str, args: list[str], env: dict[str,str], marker: str|None) -> str:
        command=[opts.godot,'--path',str(PROJECT),'--log-file',str(out/(name+'-engine.log')),*args]
        with subprocess.Popen(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True) as process:
            try:
                output,_=process.communicate(timeout=opts.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL); output,_=process.communicate()
                output+='\nTIMEOUT\n'
        (out/(name+'.log')).write_text(output,encoding='utf-8')
        errors=unexpected_errors(name,output)
        passed=process.returncode==0 and (marker is None or marker in output) and not errors
        if marker: passed=passed and 'OpenGL API' in output
        manifest['phases'].append({'name':name,'command':command,'returncode':process.returncode,'passed':passed,'unexpected_errors':errors,'log_sha256':sha(out/(name+'.log'))})
        write_manifest()
        print(f'{name}: {"PASS" if passed else "FAILED"}',flush=True)
        if not passed:
            print(output,flush=True)
            raise RuntimeError(name+' did not complete cleanly')
        return output
    try:
        with tempfile.TemporaryDirectory(prefix='hotw-quest-feedback-') as temporary:
            runtime=Path(temporary); env=os.environ.copy()
            for key in ['HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
                directory=runtime/key.lower(); directory.mkdir(); env[key]=str(directory)
            env['HOTW_TEST_SAVE']=str(runtime/'isolated-generated-save.json')
            run('bootstrap_import',['--headless','--editor','--import'],env,None)
            run('import',['--headless','--editor','--import'],env,None)
            for size in opts.sizes.split(','):
                dims=tuple(int(value) for value in size.split('x'))
                output=run('render-'+size,['--audio-driver','Dummy','--max-fps','60','--rendering-method','gl_compatibility','--resolution','1280x720','res://tests/quest_pickup_feedback_visual.tscn','--quit-after','20000','--','--out='+str(out),'--size='+size],env,MARKER)
                captures=re.findall(r'QUEST_PICKUP_RENDERED_CAPTURE (.+\.png) pixels=',output)
                for required in REQUIRED:
                    if str(out/f'{required}-{size}.png') not in captures:
                        raise RuntimeError('Missing capture marker: '+required+'-'+size)
                manifest['phases'][-1]['capture_exports']=len(captures)
                for capture in dict.fromkeys(captures):
                    path=Path(capture)
                    actual=png_size(path)
                    if actual!=dims: raise RuntimeError(f'{path.name}: {actual} != {dims}')
                    manifest['files'].append({'file':path.name,'size':actual,'sha256':sha(path)})
                write_manifest()
        after=sources()
        drift=[name for name in manifest['sources'] if after.get(name)!=manifest['sources'][name]]
        manifest['source_drift']=drift
        if drift: raise RuntimeError('Source changed during capture; rerun final evidence: '+', '.join(drift))
        manifest['passed']=True; write_manifest()
        print(f'=== QUEST PICKUP RENDERED VISUAL PASS ({len(manifest["files"])} native PNGs) ===',flush=True)
        return 0
    except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as exc:
        manifest['passed']=False; manifest['error']=str(exc); write_manifest()
        print('QUEST PICKUP RENDER FAILED: '+str(exc),flush=True)
        return 1
if __name__=='__main__': raise SystemExit(main())

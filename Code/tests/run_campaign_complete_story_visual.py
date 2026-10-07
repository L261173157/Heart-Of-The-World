#!/usr/bin/env python3
"""Actual Linux/OpenGL story screenshots from provenance-verified earned checkpoints.

Needs a caller-provided DISPLAY. Camera placement teleports are for composition;
this never claims iOS/Metal capture or human traversal. No real player save used.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import tempfile
from run_headless import unexpected_errors
from run_campaign_complete_story_test import PROJECT, sha, sources

CHECKPOINTS={'opening':None,'forest':'shared-depart','swamp':'shared-c3_prepare',
    'snow':'near-bypass-live-c5_partial','reunion':'near-bypass-live-reunion'}
REQUIRED={'opening':['01-zhou-zhao','02-first-invitation','03-first-reading-question','03-first-reading-back','03-first-reading-rules','04-first-clue','read-clue-retained'],
    'forest':['05-bai-yu-world','05-bai-yu-dialogue','06-forest-reading-question','06-forest-reading-back','earned-bai-yu','earned-old-pact','08-a-wei-world'],
    'swamp':['09-swamp-map-dialogue','10-swamp-near-preview','10-swamp-outer-preview','11-shen-du-world'],
    'snow':['12-han-duo-world','13-causality-dialogue','14-causality-rules'],
    'reunion':['15-reunion-all-four','16-reunion-leader-dialogue','17-epilogue-index','18-epilogue-page-0','18-epilogue-page-1','18-epilogue-page-2','18-epilogue-page-3','19-shi-an-still-outpost','20-repaired-final-beacon-dialogue']}

def png_size(path: Path) -> tuple[int,int]:
    data=path.read_bytes()
    if data[:8]!=b'\x89PNG\r\n\x1a\n' or data[12:16]!=b'IHDR': raise ValueError('Invalid native PNG: '+str(path))
    return struct.unpack('>II',data[16:24])

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('godot',nargs='?',default=os.environ.get('GODOT','godot'))
    parser.add_argument('--story-dir',type=Path,required=True)
    parser.add_argument('--log-dir',type=Path,required=True)
    parser.add_argument('--sizes',default='1280x720,1560x720,1024x640')
    parser.add_argument('--timeout',type=int,default=300)
    opts=parser.parse_args()
    binary=shutil.which(opts.godot)
    if not binary: parser.error('Godot not found: '+opts.godot)
    out=opts.log_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        print('COMPLETE STORY RENDER BLOCKED: actual graphics display required');return 1
    earned=opts.story_dir.resolve(); proof=json.loads((earned/'provenance.json').read_text())
    if not proof.get('passed'): raise RuntimeError('Require completed clean actual story run before screenshots')
    current=sources()
    if proof.get('sources')!=current: raise RuntimeError('Earned checkpoint source hashes do not match current source; rerun story first')
    manifest={'started_utc':datetime.now(timezone.utc).isoformat(),'engine_path':binary,'engine_sha256':sha(Path(binary)),
        'earned_provenance_sha256':sha(earned/'provenance.json'),'sources':current,'phases':[],'files':[],
        'limitations':['Actual Linux/OpenGL native SubViewport PNGs, not iPhone/Metal','Camera teleports and frozen AI for framing',
            'Except fresh opening, all prerequisites read earned checkpoints from the verified complete-story run; no synthesized quest completion']}
    def persist() -> None:
        (out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    try:
        with tempfile.TemporaryDirectory(prefix='hotw-complete-story-visual-') as tmp:
            runtime=Path(tmp);env=os.environ.copy()
            for key in ('HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME'):
                target=runtime/key.lower();target.mkdir();env[key]=str(target)
            for size in opts.sizes.split(','):
                dims=tuple(int(value) for value in size.split('x'))
                for phase,checkpoint in CHECKPOINTS.items():
                    save=runtime/'render-save.json'
                    if checkpoint:
                        source=earned/'checkpoints'/(checkpoint+'.json')
                        item=next(p for p in proof['phases'] if p['tag']==checkpoint)
                        recorded=next(v for v in item['snapshots'] if v['path']=='checkpoints/'+checkpoint+'.json')
                        if sha(source)!=recorded['sha256']: raise RuntimeError('Checkpoint bytes differ from actual story output')
                        shutil.copyfile(source,save)
                    elif save.exists(): save.unlink()
                    env['HOTW_TEST_SAVE']=str(save)
                    name=phase+'-'+size
                    command=[binary,'--path',str(PROJECT),'--audio-driver','Dummy','--max-fps','60','--rendering-method','gl_compatibility',
                        '--resolution','1280x720','res://tests/campaign_complete_story_visual.tscn','--quit-after','20000','--',
                        '--out='+str(out),'--size='+size,'--phase='+phase]
                    with subprocess.Popen(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True) as process:
                        try: output,_=process.communicate(timeout=opts.timeout)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid,signal.SIGKILL);output,_=process.communicate();output+='\nTIMEOUT\n'
                    log=out/(name+'.log');log.write_text(output,encoding='utf-8')
                    errors=unexpected_errors('complete_story_visual',output)
                    passed=process.returncode==0 and '=== CAMPAIGN COMPLETE STORY VISUAL PASS' in output and 'OpenGL API' in output and not errors
                    captures=re.findall(r'COMPLETE_STORY_CAPTURE (.+\.png) pixels=',output)
                    manifest['phases'].append({'name':name,'command':command,'source_save_sha256':sha(source) if checkpoint else None,
                        'returncode':process.returncode,'passed':passed,'errors':errors,'log_sha256':sha(log)})
                    persist();print(f'{name}: {"PASS" if passed else "FAILED"}',flush=True)
                    if not passed: print(output,flush=True);raise RuntimeError('Rendering failed: '+name)
                    for label in REQUIRED[phase]:
                        if str(out/(label+'-'+size+'.png')) not in captures:raise RuntimeError('Missing actual capture: '+label+'-'+size)
                    for name in dict.fromkeys(captures):
                        path=Path(name);actual=png_size(path)
                        if actual!=dims:raise RuntimeError(f'Wrong native size {actual}, expected {dims}')
                        manifest['files'].append({'file':path.name,'size':actual,'sha256':sha(path)})
                    persist()
        after=sources();manifest['sources_after']=after
        manifest['source_drift']=[key for key in sorted(after.keys()|current.keys()) if after.get(key)!=current.get(key)]
        if manifest['source_drift']:raise RuntimeError('Source changed while rendering; rerun final evidence')
        manifest['passed']=True;manifest['finished_utc']=datetime.now(timezone.utc).isoformat();persist()
        print(f'=== CAMPAIGN COMPLETE STORY RENDERED VISUAL PASS ({len(manifest["files"])} native PNGs) ===',flush=True);return 0
    except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as exc:
        manifest['passed']=False;manifest['error']=str(exc);persist();print('COMPLETE STORY RENDER FAILED: '+str(exc),flush=True);return 1
if __name__=='__main__':raise SystemExit(main())

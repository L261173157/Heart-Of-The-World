#!/usr/bin/env python3
"""New game → six chapters → one reunion, real scene/UI/physics and cold saves.

Runs three earned branches: near+bypass+live, outer+absent+empty, near+defeated+live.
All branch restores are exact bytes from this run. AI/eco freeze, strong combat
builds, shortened original Boss lifespan and inventory99 are declared fixtures.
No quest completion/evidence/reward receipt is synthesized by this runner.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
from run_headless import unexpected_errors

PROJECT = Path(__file__).resolve().parents[1]
MARKER = '=== CAMPAIGN COMPLETE STORY PASS'
BRANCHES = [('near','bypass','live'), ('outer','absent','absent'), ('near','defeated','live')]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def sources() -> dict[str,str]:
    paths = {PROJECT/'project.godot'}
    for directory in ('scripts','autoload','scenes','tests'):
        for ext in ('*.gd','*.tscn','*.py','*.json'):
            paths.update((PROJECT/directory).rglob(ext))
    paths.update((PROJECT/'assets/fonts').glob('*.ttf'))
    return {str(path.relative_to(PROJECT)):sha(path) for path in sorted(paths)}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('godot',nargs='?',default=os.environ.get('GODOT','godot'))
    parser.add_argument('--log-dir',type=Path,default=Path(tempfile.mkdtemp(prefix='hotw-complete-story-')))
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args()
    binary=shutil.which(args.godot)
    if not binary: parser.error('Godot not found: '+args.godot)
    out=args.log_dir.resolve(); out.mkdir(parents=True,exist_ok=True)
    checkpoints=out/'checkpoints'; checkpoints.mkdir(exist_ok=True)
    manifest={'started_utc':datetime.now(timezone.utc).isoformat(),'engine_path':binary,'engine_sha256':sha(Path(binary)),
        'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=PROJECT,text=True).strip(),
        'sources':sources(),'phases':[],'branches':[],
        'limitations':['Automated original-speed collision walking, not unassisted human play or pacing',
            'World ecology and non-target AI frozen for deterministic story/path contracts',
            'Original Boss combat uses declared strong player build; absent branches shorten original Boss lifespan then use real ecology tick',
            'Original swamp helper uses negative-fixture teleports to prove teleport cannot satisfy route evidence',
            'Full inventory boundary explicitly supplies 99 onigiri; no quest evidence/receipt injected']}
    def persist() -> None:
        (out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    def run(env: dict[str,str], phase: str, tag: str) -> dict:
        save=Path(env['HOTW_TEST_SAVE'])
        before=save.read_bytes() if save.exists() else b''
        command=[binary,'--headless','--path',str(PROJECT),'--audio-driver','Dummy',
            'res://tests/campaign_complete_story_test.tscn','--quit-after','240000','--',phase]
        with subprocess.Popen(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True) as process:
            try: output,_=process.communicate(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL); output,_=process.communicate(); output+='\nTIMEOUT\n'
        log=out/(tag+'.log'); log.write_text(output,encoding='utf-8')
        errors=unexpected_errors('campaign_complete_story',output)
        passed=process.returncode==0 and MARKER in output and not errors
        moved=re.search(r'COMPLETE_STORY_WALKED_PIXELS ([\d.]+)',output)
        ui=re.search(r'COMPLETE_STORY_UI_READING (\d+) CONTINUE (\d+)',output)
        manifest['phases'].append({'tag':tag,'phase':phase,'command':command,'returncode':process.returncode,'passed':passed,
            'errors':errors,'log_sha256':sha(log),'walked_pixels':float(moved[1]) if moved else 0,
            'reading_checks':int(ui[1]) if ui else 0,'result_checks':int(ui[2]) if ui else 0})
        persist(); print(f'{tag}: {"PASS" if passed else "FAILED"}',flush=True)
        if not passed:
            print(output,flush=True); raise RuntimeError('Story phase failed: '+tag)
        if phase=='read' and save.read_bytes()!=before: raise RuntimeError('Read-only final verification rewrote save bytes')
        for suffix in ('','.campaign_expected'):
            source=Path(str(save)+suffix)
            destination=checkpoints/(tag+'.json'+suffix)
            shutil.copyfile(source,destination)
            manifest['phases'][-1].setdefault('snapshots',[]).append({'path':str(destination.relative_to(out)),'sha256':sha(destination)})
        persist()
        return json.loads(save.read_text())
    try:
        with tempfile.TemporaryDirectory(prefix='hotw-complete-story-runtime-') as temporary:
            root=Path(temporary); env=os.environ.copy()
            for key in ('HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME'):
                target=root/key.lower(); target.mkdir(); env[key]=str(target)
            save=root/'earned-story.json'; env['HOTW_TEST_SAVE']=str(save); env['GODOT_SILENCE_ROOT_WARNING']='1'
            early=None
            for phase in ('chapter1','depart','rune_partial','runes','rescue','beacon99','claim','c3_prepare'):
                state=run(env,phase,'shared-'+phase)
                if phase=='chapter1': early=state['outpost_quest']
            prepared=(save.read_bytes(),Path(str(save)+'.campaign_expected').read_bytes())
            for route,hill,lava in BRANCHES:
                tag=f'{route}-{hill}-{lava}'
                save.write_bytes(prepared[0]); Path(str(save)+'.campaign_expected').write_bytes(prepared[1])
                for phase in (f'c3_{route}_partial',f'c3_{route}',f'c4_{hill}','c5_partial','c5_finish',f'c6_{lava}','reunion','read'):
                    state=run(env,phase,tag+'-'+phase)
                q=state['campaign_quest']
                route_proof=q['quests']['watch_c3_swamp:s3']['evidence']['watch_c3_swamp:s3:reach']
                hill_proof=q['quests']['watch_c4_hill:s3']['evidence']['watch_c4_hill:s3:passage']
                ending=q['quests']['watch_c6_lava:s4']
                if route_proof.get('route')!=route or not route_proof.get('traversed') or hill_proof.get('outcome')!=hill:
                    raise RuntimeError('Persisted branch does not match the route/encounter actually played')
                if ending.get('choice','') in ('distributed','centralized') or not ending.get('receipt',{}).get('paid'):
                    raise RuntimeError('New reunion cannot persist old binary choice or unpaid final receipt')
                if state['outpost_quest']!=early: raise RuntimeError('Branch changed original chapter one evidence/receipts')
                manifest['branches'].append({'route':route,'hill':hill,'lava':lava,'effective_ending':'reunion',
                    'save':'checkpoints/'+tag+'-reunion.json','choice':ending.get('choice',''),'receipt':ending['receipt']})
                persist()
        after=sources(); manifest['sources_after']=after
        drift=[key for key in sorted(after.keys()|manifest['sources'].keys()) if after.get(key)!=manifest['sources'].get(key)]
        manifest['source_drift']=drift
        if drift: raise RuntimeError('Source changed during story verification; rerun final evidence: '+', '.join(drift))
        manifest['walked_pixels']=sum(phase['walked_pixels'] for phase in manifest['phases'])
        manifest['passed']=True; manifest['finished_utc']=datetime.now(timezone.utc).isoformat(); persist()
        print('=== CAMPAIGN COMPLETE STORY LIFECYCLE PASS ===',flush=True)
        return 0
    except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as exc:
        manifest['passed']=False; manifest['error']=str(exc); persist()
        print('COMPLETE STORY FAILED: '+str(exc),flush=True); return 1
if __name__=='__main__': raise SystemExit(main())

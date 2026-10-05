#!/usr/bin/env python3
"""Start from a genuine C5 save and interleave every family in one actual GameWorld.

Without --from-save, earn C1 through C5 in thirteen independent real-story processes.
The optional --from-save may reuse those same genuine preserved C5 bytes.
The runner never writes completion evidence, balances, actors or world state.
All post-finale branches restore the same genuinely earned undecided save.
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
from run_campaign_lifecycle_test import run_phase as run_c2
from run_campaign_story_lifecycle_test import run_story

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('godot')
    parser.add_argument('--from-save', type=Path)
    parser.add_argument('--log-dir', type=Path)
    parser.add_argument('--phase', default='all')
    args=parser.parse_args()
    project=Path(__file__).resolve().parents[1]
    root=(args.log_dir or Path(tempfile.mkdtemp(prefix='hotw-campaign-cross-family-'))).resolve(); root.mkdir(parents=True, exist_ok=True)
    print('Cross-family logs: '+str(root),flush=True)
    env=os.environ.copy()
    for key, child in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        p=root/child;p.mkdir(exist_ok=True);env[key]=str(p)
    env['GODOT_SILENCE_ROOT_WARNING']='1'
    save=root/'save.json';env['HOTW_TEST_SAVE']=str(save)
    expected=Path(str(save)+'.campaign_expected')
    if args.phase in ('all','prepare'):
        if args.from_save:
            shutil.copyfile(args.from_save,save)
            shutil.copyfile(Path(str(args.from_save)+'.campaign_expected'),expected)
        else:
            save.unlink(missing_ok=True);expected.unlink(missing_ok=True)
            for phase in ['chapter1','depart','rune_partial','runes','rescue','beacon99','claim']:
                if not run_c2(args.godot,project,env,phase): return 1
            for phase in ['c3_prepare','c3_outer_partial','c3_outer','c4','c5_partial','c5_finish']:
                if not run_story(args.godot,project,env,phase): return 1
        source=json.loads(save.read_bytes())
        print('Genuine source sha256='+hashlib.sha256(save.read_bytes()).hexdigest()+' save_version='+str(source['version']),flush=True)
    phases=['prepare','world','resume','finale'] if args.phase=='all' else [args.phase]
    def run(phase: str) -> bool:
        result=subprocess.run([args.godot,'--headless','--path',str(project),'res://tests/campaign_cross_family_test.tscn','--quit-after','220000','--',phase],env=env,capture_output=True,text=True,timeout=520)
        output=result.stdout+result.stderr;(root/(phase+'.log')).write_text(output)
        print(f'[{phase}] exit={result.returncode}\n{output}',flush=True)
        ok=result.returncode==0 and '=== CAMPAIGN CROSS FAMILY PASS' in output and not unexpected_errors('campaign_cross_family',output)
        if ok and phase!='read':
            shutil.copyfile(save,root/(phase+'.json'))
            shutil.copyfile(expected,root/(phase+'.json.campaign_expected'))
        return ok
    for phase in phases:
        if not run(phase): return 1
    if args.phase=='all':
        undecided=(save.read_bytes(),expected.read_bytes())
        endings={}
        for ending in ['distributed','centralized']:
            save.write_bytes(undecided[0]);expected.write_bytes(undecided[1])
            if not run(ending): return 1
            before=save.read_bytes()
            endings[ending]=json.loads(before)
            if not run('read'): return 1
            if save.read_bytes()!=before:
                print('FAIL: read-only final verification rewrote saved state');return 1
            shutil.copyfile(root/'read.log',root/(ending+'-read.log'))
        distributed=endings['distributed'];centralized=endings['centralized']
        for key in ['outpost_quest','camp_quest']:
            if distributed[key]!=centralized[key]:
                print('FAIL: alternate endings altered legacy state '+key);return 1
        # GameState omits the ordinary-quest field when active/completed are empty.
        # Match its load-time empty shape rather than requiring an omitted save key.
        empty_quests={'active':[], 'completed':{}, 'receipts':{}, 'last_receipt':''}
        if distributed.get('quests',empty_quests)!=centralized.get('quests',empty_quests):
            print('FAIL: alternate endings altered ordinary quest state');return 1
        d=distributed['campaign_quest'];c=centralized['campaign_quest']
        other=lambda q:{k:v for k,v in q['quests'].items() if not k.startswith('watch_')}
        if other(d)!=other(c) or d['service_receipts']!=c['service_receipts']:
            print('FAIL: alternate endings altered another family or service tombstone');return 1
        print('Cross-ending comparison: identical non-main proofs, rewards, service tombstones and old contracts',flush=True)
        print('=== CAMPAIGN CROSS FAMILY LIFECYCLE PASS ('+str(8 if args.from_save else 21)+' fresh processes) ===',flush=True)
    return 0

if __name__=='__main__': sys.exit(main())

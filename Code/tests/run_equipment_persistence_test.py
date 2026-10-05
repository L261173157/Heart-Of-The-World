#!/usr/bin/env python3
"""独立进程装备存档测试。日志与准确生成夹具持久保存；不读取真实用户存档。"""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, signal, subprocess, sys, tempfile

def limited():
    import resource
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('godot', nargs='?', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--log-dir', type=pathlib.Path)
    args = parser.parse_args()
    project = pathlib.Path(__file__).resolve().parents[1]
    out = args.log_dir or pathlib.Path(tempfile.mkdtemp(prefix='hotw-equipment-persistence-'))
    out.mkdir(parents=True, exist_ok=True)
    runtime = pathlib.Path(tempfile.mkdtemp(prefix='hotw-equipment-runtime-'))
    env = os.environ.copy()
    for var in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        target = runtime / var.lower(); target.mkdir(); env[var] = str(target)
    save = out / 'save.json'; env['HOTW_TEST_SAVE'] = str(save)
    old = {'version':17,'campaign_min_reader':17,'world_seed':20260908,'level':3,'strength':7,'gold':800,
           'inventory':{'onigiri':99},'passives':{'gold':1},'equipment_locks':{'weapon':False},
           'equips':{'weapon':{'slot':'weapon','name':'旧火刃','rarity':3,'affixes':{'atk':.31},'element':'fire'},
                     'helmet':{'slot':'helmet','name':'旧头','rarity':1,'affixes':{'hp':.07}},
                     'armor':{'slot':'armor','name':'旧甲','rarity':2,'affixes':{'hp':.11}},
                     'boots':{'slot':'boots','name':'旧靴','rarity':1,'affixes':{'move':.08}}},
           'pending_equipment':{'slot':'offhand','name':'旧候选盾','rarity':2,'affixes':{'hp':.04}},'equipment_offer_id':7}
    # Historical v17 only had four slots: pending fixture must use one of those slots.
    old['pending_equipment']['slot'] = 'weapon'
    raw = json.dumps(old, ensure_ascii=False, separators=(',',':')).encode()
    save.write_bytes(raw); pathlib.Path(str(save)+'.legacy').write_bytes(raw)
    manifest = {'fixture':'generated isolated test data, not a user save', 'source_files':{},'phases':[]}
    for f in sorted(project.rglob('*.gd')):
        manifest['source_files'][str(f.relative_to(project))]=hashlib.sha256(f.read_bytes()).hexdigest()
    def run(phase):
        if phase=='future':
            data=json.loads(save.read_text()); data['version']=999;data['campaign_min_reader']=999;data['unknown_future']={'keep':'exact'};save.write_text(json.dumps(data))
        if phase=='future_schema':
            data=json.loads(save.read_text()); data['version']=18;data['campaign_min_reader']=18;data['equipment_schema']=[];save.write_text(json.dumps(data))
        before=save.read_bytes(); (out/f'{phase}.input.json').write_bytes(before)
        cmd=[args.godot,'--headless','--path',str(project),'res://tests/equipment_persistence_test.tscn','--quit-after','300','--',phase]
        proc=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=60,preexec_fn=limited if phase=='failure' else None)
        output=proc.stdout+proc.stderr;(out/f'{phase}.log').write_text(output);print(output,end='')
        (out/f'{phase}.output.json').write_bytes(save.read_bytes())
        manifest['phases'].append({'phase':phase,'returncode':proc.returncode,'input_sha256':hashlib.sha256(before).hexdigest(),'output_sha256':hashlib.sha256(save.read_bytes()).hexdigest()})
        (out/'provenance.json').write_text(json.dumps(manifest,indent=2))
        return proc.returncode==0 and 'SCRIPT ERROR' not in output and f'EQUIPMENT_PERSISTENCE {phase} PASS' in output
    phases=['migrate','resume','verify'] + (['failure','retry'] if sys.platform.startswith('linux') else []) + ['future','future_schema']
    for phase in phases:
        if not run(phase):return 1
    print(f'=== EQUIPMENT PERSISTENCE LIFECYCLE PASS ({len(phases)} processes) ===')
    return 0
if __name__=='__main__':raise SystemExit(main())

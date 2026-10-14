#!/usr/bin/env python3
"""在隔离目录用假导出器验证装机脚本门禁；绝不调用 Apple 工具或安装。"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def check(script: str, mode: str, expect_build: bool) -> None:
    with tempfile.TemporaryDirectory(prefix='hotw-ios-export-test-') as temp:
        root = Path(temp)
        repo, home, bins = root / 'repo', root / 'home', root / 'bin'
        repo.mkdir(); bins.mkdir()
        (repo / 'Code').mkdir()
        shutil.copy2(REPO / script, repo / script)
        shutil.copy2(REPO / 'Code/export_presets.cfg', repo / 'Code/export_presets.cfg')
        if (REPO / 'scripts').exists():
            shutil.copytree(REPO / 'scripts', repo / 'scripts')
        # 上轮遗留工程不能作为本轮成功依据。
        old = repo / 'build-output/ios/HeartOfTheWorld.xcodeproj'
        old.mkdir(parents=True)
        (old / 'project.pbxproj').write_text('OLD PROJECT')
        profile = home / 'Library/Developer/Xcode/UserData/Provisioning Profiles/63710279-2591-46dc-bbaa-53532db90472.mobileprovision'
        profile.parent.mkdir(parents=True); profile.write_text('TEST ONLY')
        godot = home / 'Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'
        godot.parent.mkdir(parents=True)
        godot.write_text('''#!/usr/bin/env python3
import os, pathlib, plistlib, sys
out = pathlib.Path(sys.argv[-1]).parent
out.mkdir(parents=True, exist_ok=True)
mode = os.environ['HOTW_MOCK_EXPORT']
if mode != 'failed':
    project = out / 'HeartOfTheWorld.xcodeproj'
    project.mkdir(exist_ok=True)
    (project / 'project.pbxproj').write_text('HeartOfTheWorld.pck' + chr(10) + ' PRODUCT_BUNDLE_IDENTIFIER = com.linxin.heartoftheworld;' + chr(10) + ' MARKETING_VERSION = 0.1.0;' + chr(10) + ' CURRENT_PROJECT_VERSION = 0.1.0;')
    if mode != 'missing_pack':
        (out / 'HeartOfTheWorld.pck').write_bytes(b'GDPC' + bytes(128))
    app = out / 'HeartOfTheWorld'; app.mkdir(exist_ok=True)
    (app / 'HeartOfTheWorld-Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'wrong.bundle' if mode == 'wrong_identity' else '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleShortVersionString':'$(MARKETING_VERSION)', 'CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}))
    lib = out / 'HeartOfTheWorld.xcframework/ios-arm64_x86_64-simulator'
    lib.mkdir(parents=True); (lib / 'libgodot.a').write_text('mock')
sys.exit(42 if mode in ('failed','partial_failure') else 0)
''')
        godot.chmod(0o755)
        # 构建入口只记标记后失败，防止后续签名/装机执行。
        for name, body in {'xcodebuild':'echo "$@" > "$HOTW_MOCK_BUILD"\nexit 77', 'ar':'echo arm64', 'pgrep':'exit 0'}.items():
            path = bins / name; path.write_text('#!/bin/sh\n'+body+'\n'); path.chmod(0o755)
        marker = root / 'build-called'
        env = dict(os.environ, HOME=str(home), PATH=str(bins)+os.pathsep+os.environ['PATH'], HOTW_MOCK_EXPORT=mode, HOTW_MOCK_BUILD=str(marker))
        result = subprocess.run(['bash', str(repo / script)], env=env, text=True, capture_output=True, timeout=20)
        called = marker.exists()
        require(called == expect_build, f'{script} {mode}: build={called}, expected={expect_build}\n{result.stdout}\n{result.stderr}')
        require((old / 'project.pbxproj').read_text() == 'OLD PROJECT', '不应覆盖上轮产物')
        if called:
            args = marker.read_text()
            require('/build-output/ios/' not in args, args)
        print(f'PASS {script} {mode}: build={called}')

if __name__ == '__main__':
    for script in ('ios-run.sh','ios-sim.sh'):
        for mode in ('failed','partial_failure','missing_pack','wrong_identity','success'):
            check(script, mode, mode == 'success')
    print('=== IOS EXPORT SAFETY PASS ===')

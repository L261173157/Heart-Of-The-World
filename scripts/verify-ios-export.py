#!/usr/bin/env python3
"""核验本轮 Godot 项目导出的必需产物，保存可追溯指纹；不构建/签名。"""
import configparser
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def verify(repo: Path, output: Path) -> None:
    config = configparser.ConfigParser(interpolation=None)
    config.read(repo / 'Code/export_presets.cfg', encoding='utf-8')
    preset = config['preset.0.options']
    require(preset.get('application/export_project_only') == 'true', 'iOS 必须仅导出工程，签名由后续脚本执行')
    expected = {key: json.loads(preset[setting]) for key, setting in (
        ('CFBundleIdentifier', 'application/bundle_identifier'),
        ('CFBundleShortVersionString', 'application/short_version'),
        ('CFBundleVersion', 'application/version'),
    )}
    project = output / 'HeartOfTheWorld.xcodeproj/project.pbxproj'
    pack = output / 'HeartOfTheWorld.pck'
    info = output / 'HeartOfTheWorld/HeartOfTheWorld-Info.plist'
    require(project.is_file() and project.stat().st_size > 0, '缺少本轮 Xcode 工程')
    require(pack.is_file() and pack.stat().st_size > 64, '缺少或不完整的本轮 PCK')
    with pack.open('rb') as handle:
        require(handle.read(4) == b'GDPC', '本轮 PCK 文件头无效')
    project_text = project.read_text(encoding='utf-8')
    require('HeartOfTheWorld.pck' in project_text, '工程没有引用本轮 PCK')
    with info.open('rb') as handle:
        actual = plistlib.load(handle)
    for key, value in expected.items():
        actual_value = actual.get(key)
        if isinstance(actual_value, str) and re.fullmatch(r'\$\([A-Z_]+\)', actual_value):
            # Godot 4.7 的 Info.plist 通过 Xcode 构建变量引用身份。
            variable = actual_value[2:-1]
            matches = re.findall(r'(?m)^\s*' + re.escape(variable) + r'\s*=\s*([^;]+);', project_text)
            require(matches and all(item.strip().strip(chr(34)) == value for item in matches), f'工程构建身份不一致：{variable}')
        else:
            require(actual_value == value, f'导出身份不一致：{key}')
    revision = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    with pack.open('rb') as handle:
        digest = hashlib.file_digest(handle, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(handle.read()).hexdigest()
    manifest = dict(expected, git_revision=revision.stdout.strip() if revision.returncode == 0 else 'unavailable', pck_sha256=digest, pck_bytes=pack.stat().st_size)
    (output / 'export-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]))
    except (AssertionError, OSError, ValueError, KeyError, configparser.Error) as error:
        print(f'✗ 本轮导出校验失败：{error}', file=sys.stderr)
        sys.exit(3)

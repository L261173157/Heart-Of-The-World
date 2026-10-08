#!/usr/bin/env python3
"""隔离的地图开关/暂停图形回归；真实 OpenGL 截图不代表 iPhone/Metal 性能。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import tempfile
import zlib
from run_headless import unexpected_errors

PROJECT = Path(__file__).resolve().parents[1]

def sources() -> dict[str, str]:
    paths = [path for path in PROJECT.rglob('*') if path.is_file()
             and '.godot' not in path.parts and path.suffix in {'.gd', '.tscn'}]
    paths += [PROJECT / 'project.godot', Path(__file__).resolve()]
    return {str(path.relative_to(PROJECT)):hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)}


def valid_png(data: bytes) -> bool:
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return False
    offset, compressed, header, ended = 8, bytearray(), None, False
    try:
        while offset < len(data):
            size = struct.unpack('>I', data[offset:offset+4])[0]
            kind = data[offset+4:offset+8]
            chunk = data[offset+8:offset+8+size]
            checksum = struct.unpack('>I', data[offset+8+size:offset+12+size])[0]
            if len(chunk) != size or zlib.crc32(kind + chunk) != checksum:
                return False
            if header is None:
                if kind != b'IHDR' or size != 13:
                    return False
                header = struct.unpack('>IIBBBBB', chunk)
            if kind == b'IDAT':
                compressed.extend(chunk)
            if kind == b'IEND':
                ended = size == 0 and offset + 12 == len(data)
                break
            offset += size + 12
        if not ended or not header or not compressed:
            return False
        width, height, bits, color, compression, filtering, interlace = header
        channels = {0:1, 2:3, 4:2, 6:4}.get(color, 0)
        if (width, height) != (1280, 720) or bits != 8 or not channels or any([compression, filtering, interlace]):
            return False
        raw = zlib.decompress(compressed)
        stride = 1 + width * channels
        return len(raw) == height * stride and all(raw[y*stride] <= 4 for y in range(height))
    except (struct.error, zlib.error):
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('godot')
    parser.add_argument('--log-dir', type=Path, required=True)
    opts = parser.parse_args()
    binary = shutil.which(opts.godot)
    if not binary:
        parser.error('Godot executable not found')
    out = opts.log_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    expected = ['map_open.png', 'map_closed.png', 'map_reopen.png']
    for name in expected:
        (out / name).unlink(missing_ok=True)
    before = sources()
    with tempfile.TemporaryDirectory(prefix='hotw-map-render-') as temp:
        base = Path(temp)
        env = os.environ.copy()
        for key, relative in {'HOME':'home', 'XDG_CONFIG_HOME':'config',
                              'XDG_CACHE_HOME':'cache', 'XDG_DATA_HOME':'data'}.items():
            path = base / relative
            path.mkdir()
            env[key] = str(path)
        startup = base / 'startup.json'
        shutil.copyfile(PROJECT / 'tests/fixtures/test_save.json', startup)
        env['HOTW_TEST_SAVE'] = str(startup)
        env['HOTW_MAP_SHOTS'] = str(out)
        command = [binary, '--path', str(PROJECT), '--rendering-method', 'gl_compatibility',
                   '--audio-driver', 'Dummy', '--resolution', '1280x720',
                   'res://tests/map_performance_test.tscn', '--quit-after', '10000']
        with subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, start_new_session=True) as process:
            try:
                output, _ = process.communicate(timeout=600)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                output, _ = process.communicate()
                output += '\nFAIL timeout\n'
            code = process.returncode
        (out / 'map_visual.log').write_text(output, encoding='utf-8')
    errors = unexpected_errors('map_performance', output)
    passed = code == 0 and '=== MAP PERFORMANCE PASS' in output and not errors and 'OpenGL API' in output
    images = {}
    for name in expected:
        path = out / name
        data = path.read_bytes() if path.exists() else b''
        valid = valid_png(data) and ('MAP SCREENSHOT ' + str(path)) in output
        passed = passed and valid
        images[name] = {'valid':valid, 'sha256':hashlib.sha256(data).hexdigest()}
    after = sources()
    passed = passed and before == after
    (out / 'provenance.json').write_text(json.dumps({'engine_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
        'sources_before':before, 'sources_after':after, 'images':images, 'passed':passed, 'errors':errors,
        'limitation':'Linux/OpenGL only; not iPhone/Metal performance evidence'}, indent=2), encoding='utf-8')
    print('=== MAP VISUAL ' + ('PASS' if passed else 'FAIL') + ' ===')
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())

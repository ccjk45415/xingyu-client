"""Verify a registered Windows base without downloading a patch or publishing."""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import re
import struct
import subprocess
import uuid


def file_version(path):
    api = ctypes.WinDLL('version', use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    api.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    api.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID]
    api.GetFileVersionInfoW.restype = wintypes.BOOL
    api.VerQueryValueW.argtypes = [wintypes.LPCVOID, wintypes.LPCWSTR, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.UINT)]
    api.VerQueryValueW.restype = wintypes.BOOL
    size = api.GetFileVersionInfoSizeW(str(path), None)
    assert size, 'Missing executable version resource'
    buffer = ctypes.create_string_buffer(size)
    assert api.GetFileVersionInfoW(str(path), 0, size, buffer)
    pointer, length = ctypes.c_void_p(), wintypes.UINT()
    assert api.VerQueryValueW(buffer, '\\', ctypes.byref(pointer), ctypes.byref(length))
    assert length.value >= 52
    words = ctypes.cast(pointer, ctypes.POINTER(wintypes.DWORD))
    assert words[0] == 0xFEEF04BD
    ms, ls = words[2], words[3]
    return ms >> 16, ms & 65535, ls >> 16, ls & 65535


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', type=int, required=True)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    for name in ['Xingyu.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat',
                 'data/flutter_assets/NOTICES.Z', 'data/flutter_assets/shorebird.yaml']:
        assert (bundle/name).is_file(), 'Missing runtime file: ' + name
    assert any('sqlite' in p.name.lower() and p.suffix.lower() == '.dll'
               for p in bundle.iterdir()), 'Missing SQLite native asset'
    exe = (bundle/'Xingyu.exe').read_bytes()
    offset = struct.unpack_from('<I', exe, 0x3c)[0]
    assert exe[:2] == b'MZ' and exe[offset:offset+4] == b'PE\0\0'
    assert struct.unpack_from('<H', exe, offset+4)[0] == 0x8664
    assert re.fullmatch(r'\d+\.\d+\.\d+', args.version)
    expected = tuple(int(part) for part in args.version.split('.')) + (args.build,)
    assert file_version(bundle/'Xingyu.exe') == expected, 'Executable version does not match requested base'
    config = bundle/'data/flutter_assets/shorebird.yaml'
    original = config.read_bytes()
    isolated = re.sub(rb'(?m)^app_id:\s*[a-f0-9-]+',
                      b'app_id: ' + str(uuid.uuid4()).encode(), original)
    assert isolated != original, 'Could not isolate updater for native check'
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    try:
        config.write_bytes(isolated)
        result = subprocess.run([str(bundle/'Xingyu.exe'), '--self-check', '--offline'],
                                cwd=bundle, startupinfo=startup, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=60)
    finally:
        config.write_bytes(original)
    assert config.read_bytes() == original
    if result.returncode:
        raise SystemExit('Native diagnostics failed: ' + result.stderr[-1400:])
    native = next(json.loads(line) for line in result.stdout.splitlines()
                  if line.startswith('{') and 'windows_native_engine' in line)
    for key in ['windows_native_engine', 'secure_storage',
                'encrypted_file_and_tamper_rejection', 'app_data_directory',
                'dynamic_templates_sqlite_fts5']:
        assert native.get(key) == 'pass', key
    assert native.get('code_push_engine') == 'available'
    assert native.get('code_push_initialized') is True
    assert native.get('system_notifications_native') is True
    assert native.get('current_patch') == 0 and native.get('next_patch') == 0
    assert native.get('public_health') == 'skipped_offline'
    native.update(version=args.version, build=args.build,
                  isolated_updater_id=True, patch_downloaded=False)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(native, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(native))


if __name__ == '__main__':
    main()

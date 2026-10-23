"""Exercise the actual PowerShell updater in isolated directories, without launching apps."""
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.toolchain' / ('windows-updater-tests-' + uuid.uuid4().hex)
WORK.mkdir()
assert WORK.resolve().is_relative_to((ROOT / '.toolchain').resolve())
SCRIPT = ROOT / 'desktop/assets/windows-update.ps1'
required = ['Xingyu.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll',
            'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat',
            'data/flutter_assets/NOTICES.Z', 'VERSION.json', 'data/zz-locked.bin']
results = []

def fixture(name, extra=None, omit=None):
    folder = WORK / name
    install, work = folder / "中文 [portable] ' client", folder / 'job'
    install.mkdir(parents=True); work.mkdir()
    payload = {p: b'new:' + p.encode() for p in required if p != omit}
    payload['Xingyu.exe'] = b'MZfixture-not-an-executable'
    payload['VERSION.json'] = json.dumps({'product': 'moe.cangku.xingyu.desktop',
        'platform': 'windows-x64', 'versionName': '0.5.0', 'versionCode': 24}).encode()
    if extra: payload.update(extra)
    for name in required:
        p = install / name; p.parent.mkdir(exist_ok=True, parents=True); p.write_bytes(b'old:' + name.encode())
    (install / 'my-personal-file.txt').write_text('must remain', encoding='utf-8')
    archive = work / 'update.zip'
    with zipfile.ZipFile(archive, 'w') as z:
        for path, data in payload.items(): z.writestr('Xingyu-Windows-0.5.0/' + path, data)
    job = work / 'job.json'
    job.write_text(json.dumps({'archive': str(archive), 'install': str(install), 'parentPid': 0,
        'versionName': '0.5.0', 'versionCode': 24,
        'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}), encoding='utf-8')
    return install, work, job, payload

def run(job, mode, expected=0):
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass', '-File', str(SCRIPT), '-Mode', mode, '-Job', str(job), '-NoRestart'],
        capture_output=True, timeout=45)
    assert result.returncode == expected, (mode, result.returncode, result.stdout.decode(errors='replace')[-1600:], result.stderr.decode(errors='replace')[-1600:])

def unchanged(install):
    for name in required: assert (install / name).read_bytes() == b'old:' + name.encode(), name
    assert (install / 'my-personal-file.txt').read_text('utf-8') == 'must remain'

install, work, job, payload = fixture('success')
run(job, 'Prepare'); run(job, 'Apply')
for name, data in payload.items(): assert (install / name).read_bytes() == data
assert (install / 'my-personal-file.txt').read_text('utf-8') == 'must remain'
assert json.loads((work / 'result.json').read_text('utf-8-sig'))['status'] == 'installed'
results.append('unicode_path_update_preserves_unmanaged_files')

for name, extra, omit in [
    ('traversal', {'../../escape.txt': b'bad'}, None),
    ('absolute', {'C:/escape.txt': b'bad'}, None),
    ('duplicate_case', {'FLUTTER_WINDOWS.DLL': b'bad'}, None),
    ('alternate_stream', {'data/file.txt:stream': b'bad'}, None),
    ('reserved_name', {'data/CON.txt': b'bad'}, None),
    ('missing_runtime', {}, 'flutter_windows.dll'),
]:
    install, work, job, _ = fixture(name, extra, omit)
    run(job, 'Prepare', 1); unchanged(install)
    results.append(name + '_rejected_without_replacement')

install, work, job, _ = fixture('archive_tampered')
with (work / 'update.zip').open('ab') as f: f.write(b'tamper')
run(job, 'Prepare', 1); unchanged(install)
results.append('archive_hash_tamper_rejected')

install, work, job, _ = fixture('staged_tampered')
run(job, 'Prepare')
(work / 'stage/data/app.so').write_bytes(b'tamper')
run(job, 'Apply', 1); unchanged(install)
results.append('staged_hash_tamper_rejected')

install, work, job, _ = fixture('rollback')
run(job, 'Prepare')
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.CreateFileW.restype = ctypes.c_void_p
kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
    ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
handle = kernel.CreateFileW(str(install / 'data/zz-locked.bin'), 0x80000000, 0, None, 3, 0, None)
assert handle not in (None, ctypes.c_void_p(-1).value)
try: run(job, 'Apply', 1)
finally:
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle(handle)
unchanged(install)
assert json.loads((work / 'result.json').read_text('utf-8-sig'))['rolled_back'] is True
results.append('partial_update_failure_rolls_back_all_managed_files')
report = {'passed': len(results), 'checks': results, 'application_launched': False,
          'workspace': str(WORK)}
(ROOT / 'evidence/windows-updater-validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))

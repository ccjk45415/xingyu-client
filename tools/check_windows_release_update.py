"""Apply the real release ZIP over an isolated old portable bundle, without launching UI."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
work = ROOT / '.toolchain' / ('windows-release-update-' + uuid.uuid4().hex)
work.mkdir()
assert work.resolve().is_relative_to((ROOT / '.toolchain').resolve())
old = ROOT / 'output/Xingyu-Windows-0.6.0-x64.zip'
new = ROOT / 'output/Xingyu-Windows-0.7.1-x64.zip'
with zipfile.ZipFile(old) as archive:
    for name in archive.namelist():
        assert (work / name).resolve().is_relative_to(work.resolve())
    archive.extractall(work)
install = work / 'Xingyu-Windows-0.6.0'
(install / 'my-personal-file.txt').write_bytes(b'keep me')
job = work / 'job.json'
job.write_text(json.dumps({'archive': str(new), 'install': str(install), 'parentPid': 0,
    'versionName': '0.7.1', 'versionCode': 28, 'sha256': hashlib.sha256(new.read_bytes()).hexdigest()}), encoding='utf-8')
for mode in ['Prepare', 'Apply']:
    subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / 'desktop/assets/windows-update.ps1'),
        '-Mode', mode, '-Job', str(job), '-NoRestart'], check=True, timeout=120)
with zipfile.ZipFile(new) as archive:
    count = 0
    for name in archive.namelist():
        if name.endswith('/'): continue
        relative = name.split('/', 1)[1]
        assert (install / relative).read_bytes() == archive.read(name), relative
        count += 1
assert (install / 'my-personal-file.txt').read_bytes() == b'keep me'
subprocess.run(['python', str(ROOT / 'tools/check_desktop_native.py'), str(install / 'Xingyu.exe')], check=True, timeout=75)
report = {'status': 'pass', 'old_bundle': old.name, 'new_bundle': new.name,
    'verified_installed_files': count, 'unmanaged_files_preserved': True,
    'updated_native_engine_check': 'pass', 'desktop_ui_launched': False}
(ROOT / 'evidence/release-0.13.1-windows-upgrade.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))

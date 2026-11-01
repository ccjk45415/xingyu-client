"""Run the real Windows engine's offline check, using a private updater ID."""
import json
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/2026年10月24日/20261101-动态模板测试'
BUNDLE = ROOT / 'desktop/build/windows/native-x64/runner'


def main():
    config = BUNDLE / 'data/flutter_assets/shorebird.yaml'
    original = config.read_bytes()
    isolated = re.sub(rb'(?m)^app_id:\s*[a-f0-9-]+', b'app_id: ' + str(uuid.uuid4()).encode(), original)
    assert isolated != original
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    try:
        config.write_bytes(isolated)
        result = subprocess.run([str(BUNDLE/'Xingyu.exe'), '--self-check', '--offline'], cwd=ROOT,
                                startupinfo=startup, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=60)
    finally:
        config.write_bytes(original)
    if result.returncode:
        raise SystemExit('Native self-check failed: ' + result.stderr[-1400:])
    report = next(json.loads(line) for line in result.stdout.splitlines() if line.startswith('{'))
    for key in ['windows_native_engine', 'secure_storage', 'encrypted_file_and_tamper_rejection',
                'app_data_directory', 'dynamic_templates_sqlite_fts5']:
        assert report[key] == 'pass', key
    assert report['code_push_initialized'] is True
    assert report['system_notifications_native'] is True
    report['isolated_updater_id'] = True
    (OUT/'windows-native-validation.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()

"""Run the real Windows release engine's isolated DPAPI/filesystem/health diagnostics."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
exe=(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'desktop/build/windows/native-x64/runner/Xingyu.exe').resolve()
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
result=subprocess.run([str(exe),'--self-check'],cwd=ROOT,timeout=60,capture_output=True,text=True,encoding='utf-8',errors='replace',startupinfo=startup)
if result.returncode:raise SystemExit('Native diagnostics failed: '+result.stderr[-1800:])
report=next((json.loads(line) for line in result.stdout.splitlines() if line.startswith('{') and 'windows_native_engine' in line),None)
assert report and all(report.get(key)=='pass' for key in ['windows_native_engine','secure_storage','encrypted_file_and_tamper_rejection','app_data_directory','public_health'])
report['unicode_install_path_tested']=any(ord(c)>127 for c in str(exe))
(ROOT/'evidence/desktop-native-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))

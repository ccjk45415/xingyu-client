"""Exercise the real Dart -> PowerShell -> parent exit -> replacement -> restart chain."""
import hashlib,json,os,subprocess,time,uuid,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.toolchain'/('windows-handoff-test-'+uuid.uuid4().hex)
WORK.mkdir()
assert WORK.resolve().is_relative_to((ROOT/'.toolchain').resolve())
install=WORK/"中文 [portable] ' client";install.mkdir()
jobdir=WORK/'job';jobdir.mkdir()
fixture=WORK/'fixture.cs'
fixture.write_text('using System;using System.IO;class Program { [STAThread] static void Main(){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"restarted.txt"),"new-version-started");}}')
compile_script=WORK/'compile.ps1'
compile_script.write_text("param([string]$Source,[string]$Output)\nAdd-Type -TypeDefinition ([IO.File]::ReadAllText($Source)) -OutputAssembly $Output -OutputType WindowsApplication\n")
subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',str(compile_script),'-Source',str(fixture),'-Output',str(WORK/'fixture.exe')],check=True,capture_output=True,timeout=30)
required=['Xingyu.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/icudtl.dat','data/flutter_assets/NOTICES.Z','VERSION.json']
payload={name:('new:'+name).encode() for name in required}
payload['Xingyu.exe']=(WORK/'fixture.exe').read_bytes()
payload['VERSION.json']=json.dumps({'product':'moe.cangku.xingyu.desktop','platform':'windows-x64','versionName':'0.7.0','versionCode':27}).encode()
for name in required:
 file=install/name;file.parent.mkdir(exist_ok=True,parents=True);file.write_bytes(('old:'+name).encode())
(install/'personal.txt').write_text('preserve')
archive=jobdir/'update.zip'
with zipfile.ZipFile(archive,'w') as z:
 for name,data in payload.items():z.writestr('Xingyu-Windows-0.7.0/'+name,data)
(jobdir/'update.ps1').write_text((ROOT/'desktop/assets/windows-update.ps1').read_text(encoding='utf-8-sig').replace('} catch {\n    if ($NoRestart)', "} catch {\n    [IO.File]::WriteAllText((Join-Path $work 'test-error.txt'), ($_ | Out-String))\n    if ($NoRestart)"), encoding='utf-8-sig')
job={'archive':str(archive),'install':str(install),'parentPid':0,'versionName':'0.7.0','versionCode':27,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(jobdir/'job.json').write_text(json.dumps(job))
subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',str(jobdir/'update.ps1'),'-Mode','Prepare','-Job',str(jobdir/'job.json'),'-NoRestart'],check=True,capture_output=True,timeout=30)
module=(ROOT/'desktop/lib/core/windows_update_handoff.dart').as_uri()
parent=WORK/'parent.dart'
parent.write_text("import 'dart:io'; import 'dart:convert'; import '"+module+"'; Future<void> main(List<String>a)async{ final w=Directory(a[0]); final j=File('${w.path}/job.json'); final config=jsonDecode(await j.readAsString()); config['parentPid']=pid;await j.writeAsString(jsonEncode(config)); try{await startWindowsUpdate(w,timeout:Duration(seconds:3));}catch(_){await File('${w.path}/failed-safely.txt').writeAsString('parent-still-running');exit(12);} if(await File('${w.path}/result.json').exists())exit(13);await File('${w.path}/parent-confirmed.txt').writeAsString('handoff-confirmed');exit(0);}")
dart=Path(os.environ.get('FLUTTER_ROOT','C:/codex-tools/flutter'))/'bin/cache/dart-sdk/bin/dart.exe'
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
r=subprocess.run([str(dart),str(parent),str(jobdir)],capture_output=True,timeout=30,startupinfo=startup)
assert r.returncode==0,(r.returncode,r.stderr.decode(errors='replace'))
for _ in range(150):
 if (install/'restarted.txt').exists():break
 time.sleep(.1)
assert (install/'restarted.txt').exists(), ((jobdir/'test-error.txt').read_text('utf-8') if (jobdir/'test-error.txt').exists() else 'no error recorded', str(WORK))
assert (install/'restarted.txt').read_text()=='new-version-started'
assert json.loads((jobdir/'result.json').read_text('utf-8-sig'))['status']=='installed'
for name,data in payload.items():assert (install/name).read_bytes()==data,name
assert (install/'personal.txt').read_text()=='preserve'
failed=WORK/'no-helper';failed.mkdir();(failed/'job.json').write_text(json.dumps(job))
(failed/'handoff-stale.json').write_text(json.dumps({'status':'started','token':'old','pid':0}))
r=subprocess.run([str(dart),str(parent),str(failed)],capture_output=True,timeout=15,startupinfo=startup)
assert r.returncode==12 and (failed/'failed-safely.txt').read_text()=='parent-still-running'
report={'status':'pass','real_dart_parent_exit':True,'helper_survives_parent':True,'unicode_space_bracket_quote_paths':True,'replacement_hashes_verified':True,'new_executable_restarted_and_wrote_marker':True,'unmanaged_file_preserved':True,'missing_helper_prevents_app_exit':True,'stale_ack_rejected':True,'user_application_or_account_touched':False}
(ROOT/'evidence/windows-update-handoff-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))

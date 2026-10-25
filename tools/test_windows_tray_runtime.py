"""Exercise the shipped tray helper against an isolated, hidden fixture window.

Never opens/closes a real client or touches its data. Requires Windows PowerShell.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
if sys.platform != 'win32':
    raise SystemExit('This runtime fixture requires Windows')
WORK = Path(tempfile.mkdtemp(prefix='tray-runtime-', dir=ROOT / '.toolchain'))
PS = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
HIDDEN = subprocess.STARTUPINFO()
HIDDEN.dwFlags |= subprocess.STARTF_USESHOWWINDOW
HIDDEN.wShowWindow = 0


def launch(script):
    return subprocess.Popen([str(PS), '-NoProfile', '-NonInteractive', '-Sta',
                             '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
                             '-File', str(script)], cwd=WORK, startupinfo=HIDDEN,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def until(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError('Fixture deadline exceeded')


fixture = r'''
using System;
using System.IO;
using System.Windows.Forms;
public static class TrayFixture {
 [STAThread] public static void Main(string[] args) {
  using (var form = new Form()) using (var timer = new Timer()) {
   var handle = form.Handle;
   File.WriteAllText(args[0], System.Diagnostics.Process.GetCurrentProcess().Id + " " + handle.ToInt64());
   timer.Interval = 100;
   timer.Tick += (sender, e) => { if (File.Exists(args[1])) Application.Exit(); };
   timer.Start(); Application.Run();
  }
 }
}
'''
exe = WORK / 'fixture.exe'
compile_script = WORK / 'compile.ps1'
compile_script.write_text("$ErrorActionPreference='Stop'\nAdd-Type -ReferencedAssemblies System.Windows.Forms "
                          "-OutputType WindowsApplication -OutputAssembly 'fixture.exe' -TypeDefinition @'\n"
                          + fixture + "\n'@\n", encoding='utf-8-sig')
compiler = launch(compile_script)
out, err = compiler.communicate(timeout=30)
assert compiler.returncode == 0, err.decode(errors='replace')
source = (ROOT / 'desktop/lib/core/windows_tray.dart').read_text(encoding='utf-8')
helper_script = re.search(r"const windowsTrayScript = r'''(.*?)''';", source, re.S).group(1)
script = WORK / 'tray.ps1'
script.write_text(helper_script, encoding='utf-8-sig')
results = []
for scenario in ('explicit-stop', 'parent-exit', 'invalid-window-owner'):
    for name in ('ready.json', 'stop', 'parent.stop', 'parent.txt', 'command.json'):
        (WORK / name).unlink(missing_ok=True)
    parent = subprocess.Popen([str(exe), str(WORK / 'parent.txt'), str(WORK / 'parent.stop')],
                              cwd=WORK, startupinfo=HIDDEN)
    helper = None
    try:
        until(lambda: (WORK / 'parent.txt').exists())
        parent_pid, window = map(int, (WORK / 'parent.txt').read_text().split())
        token = uuid.uuid4().hex
        (WORK / 'config.json').write_text(json.dumps({
            'pid': parent_pid, 'window': 0 if scenario == 'invalid-window-owner' else window,
            'token': token, 'icon': str(exe)}), encoding='utf-8')
        helper = launch(script)
        if scenario == 'invalid-window-owner':
            helper.communicate(timeout=20)
            assert helper.returncode == 2 and not (WORK / 'ready.json').exists()
        else:
            until(lambda: (WORK / 'ready.json').exists() or helper.poll() is not None)
            assert helper.poll() is None, helper.communicate()[1].decode(errors='replace')
            ready = json.loads((WORK / 'ready.json').read_text(encoding='utf-8-sig'))
            assert ready == {'token': token, 'pid': helper.pid}
            if scenario == 'explicit-stop':
                (WORK / 'stop').write_text(token)
            else:
                (WORK / 'parent.stop').touch()
                parent.wait(timeout=5)
            helper.communicate(timeout=5)
            assert helper.returncode == 0
            if scenario == 'explicit-stop':
                assert parent.poll() is None
        results.append({'scenario': scenario, 'passed': True})
    finally:
        (WORK / 'parent.stop').touch()
        parent.wait(timeout=5)
        if helper is not None and helper.poll() is None:
            (WORK / 'stop').touch()
            helper.communicate(timeout=5)
report = {'fixture_only': True, 'production_script': True, 'results': results}
(ROOT / 'evidence/windows-tray-runtime.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))

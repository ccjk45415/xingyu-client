import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Launch PowerShell with valid standard handles, and wait for an explicit
/// acknowledgement before allowing the application to exit. Windows PowerShell
/// can exit before running -File when created with DETACHED_PROCESS by Dart.
Future<void> startWindowsUpdate(
  Directory work, {
  Duration timeout = const Duration(seconds: 15),
  String? executable,
}) async {
  final token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final ack = File('${work.path}/handoff-$token.json');
  final launcher = File('${work.path}/handoff-$token.ps1');
  await launcher.writeAsString('''
param([string]\$Job, [string]\$Token, [string]\$Ack)
\$ErrorActionPreference = 'Stop'
\$work = Split-Path -Parent ([IO.Path]::GetFullPath(\$Job))
\$script = Join-Path \$work 'update.ps1'
if (-not (Test-Path -LiteralPath \$Job -PathType Leaf) -or -not (Test-Path -LiteralPath \$script -PathType Leaf)) { exit 2 }
\$record = @{status='started'; token=\$Token; pid=\$PID} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((\$Ack + '.tmp'), \$record, (New-Object Text.UTF8Encoding(\$false)))
[IO.File]::Move((\$Ack + '.tmp'), \$Ack)
& \$script -Mode Apply -Job \$Job -NoRestart
\$result = \$LASTEXITCODE
if (\$result -ne 0) {
  Add-Type -AssemblyName System.Windows.Forms
  [Windows.Forms.MessageBox]::Show('Update failed. The previous version has been restored. Please try again.', 'Xingyu') | Out-Null
}
# Start-Process expands brackets in WorkingDirectory as wildcards. These paths
# were validated by the updater; ProcessStartInfo accepts them literally.
\$install = ([IO.File]::ReadAllText(\$Job) | ConvertFrom-Json).install
\$start = New-Object Diagnostics.ProcessStartInfo
\$start.FileName = Join-Path \$install 'Xingyu.exe'
\$start.WorkingDirectory = \$install
\$start.UseShellExecute = \$true
[Diagnostics.Process]::Start(\$start) | Out-Null
exit \$result
''', flush: true);
  final powershell =
      executable ??
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}'
          r'\System32\WindowsPowerShell\v1.0\powershell.exe';
  final process = await Process.start(powershell, [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    launcher.path,
    '-Job',
    '${work.path}/job.json',
    '-Token',
    token,
    '-Ack',
    ack.path,
  ], workingDirectory: work.path);
  // Keep valid, drained pipes until handoff. No helper output contains account
  // data; nevertheless do not persist it or surface raw process errors.
  unawaited(process.stdout.drain<void>().catchError((_) {}));
  unawaited(process.stderr.drain<void>().catchError((_) {}));
  await process.stdin.close();
  int? ended;
  unawaited(process.exitCode.then((value) => ended = value));
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    if (await ack.exists()) {
      final bytes = await ack.readAsBytes();
      if (bytes.length < 1024) {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map &&
            value['status'] == 'started' &&
            value['token'] == token &&
            value['pid'] == process.pid &&
            ended == null) {
          return;
        }
      }
      break;
    }
    if (ended != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  process.kill();
  throw const FileSystemException('更新程序未能接手，客户端已保持运行。请重试或手动安装完整包。');
}

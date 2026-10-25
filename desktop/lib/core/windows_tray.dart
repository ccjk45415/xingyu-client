import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'api.dart' show nonce;
import 'window_placement.dart';

abstract interface class TrayPort {
  Future<void> prepare(void Function(String) onCommand);
  void hide();
  void show();
  Future<void> dispose();
}

/// A per-process tray helper uses Windows Forms' own message loop. No WndProc
/// callback crosses into the Dart isolate, no website session leaves the app,
/// and neither a new plugin nor a bundled executable is needed by this patch.
class WindowsTray implements TrayPort {
  final placement = WindowsPlacement();
  final _user = DynamicLibrary.open('user32.dll');
  late final _show = _user
      .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
        'ShowWindow',
      );
  late final _activate = _user
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetForegroundWindow',
      );
  late final _minimized = _user
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
  int _window = 0, _sequence = 0;
  Process? _helper;
  Directory? _directory;
  Timer? _poll;
  bool _disposed = false;
  Future<void>? _preparing;
  final _token = nonce();

  @override
  Future<void> prepare(void Function(String) onCommand) =>
      _preparing ??= _prepare(onCommand).catchError((Object error) {
        _preparing = null;
        throw error;
      });

  Future<void> _prepare(void Function(String) onCommand) async {
    if (_disposed) throw StateError('Tray is closed');
    _sequence = 0;
    _window = placement.windowHandle;
    if (_window == 0) throw StateError('Main window unavailable');
    final directory = _directory = await Directory.systemTemp.createTemp(
      'xingyu-tray-',
    );
    final script = File('${directory.path}/tray.ps1');
    await script.writeAsString('\uFEFF$windowsTrayScript', flush: true);
    await File('${directory.path}/config.json').writeAsString(
      jsonEncode({
        'pid': pid,
        'window': _window,
        'token': _token,
        'icon': Platform.resolvedExecutable,
      }),
      flush: true,
    );
    final helper = _helper = await Process.start(
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Sta',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ],
      workingDirectory: directory.path,
    );
    unawaited(helper.stdout.drain<void>().catchError((_) {}));
    unawaited(helper.stderr.drain<void>().catchError((_) {}));
    await helper.stdin.close();
    bool ended = false;
    unawaited(
      helper.exitCode.then((_) {
        ended = true;
        if (!_disposed) {
          _preparing = null;
          _poll?.cancel();
          show();
          onCommand('helper-failed');
        }
      }),
    );
    final ready = File('${directory.path}/ready.json');
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 12)) {
      if (_disposed || ended) break;
      if (await ready.exists()) {
        try {
          final value = jsonDecode(await ready.readAsString());
          if (value['token'] == _token && value['pid'] == helper.pid) {
            _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
              if (_disposed) return;
              try {
                final file = File('${directory.path}/command.json');
                if (!file.existsSync() || file.lengthSync() > 1024) return;
                final value = jsonDecode(file.readAsStringSync());
                if (value['token'] != _token ||
                    value['sequence'] is! int ||
                    value['sequence'] <= _sequence) {
                  return;
                }
                _sequence = value['sequence'] as int;
                final command = value['command'];
                if (command == 'show') show();
                if (['show', 'quit', 'checkin'].contains(command)) {
                  onCommand(command as String);
                }
              } catch (_) {
                /* A partially written command is read on the next tick. */
              }
            });
            return;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    helper.kill();
    throw StateError('托盘暂时无法启动，窗口已保持打开，请重试或选择退出程序');
  }

  @override
  void hide() {
    if (_window != 0) _show(_window, 0);
  }

  @override
  void show() {
    if (_window == 0) return;
    _show(_window, _minimized(_window) != 0 ? 9 : 5);
    _activate(_window);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _poll?.cancel();
    final directory = _directory, helper = _helper;
    if (directory != null && helper != null) {
      try {
        await File('${directory.path}/stop').writeAsString(_token, flush: true);
        await helper.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        helper.kill();
      }
    }
  }
}

// Kept in Dart rather than an asset so existing Windows bases can receive it.
const windowsTrayScript = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class XingyuTrayWindow {
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
}
'@
$work = $PSScriptRoot
$config = [IO.File]::ReadAllText((Join-Path $work 'config.json')) | ConvertFrom-Json
$parentProcess = [Diagnostics.Process]::GetProcessById([int]$config.pid)
$window = [IntPtr][long]$config.window
[uint32]$windowOwner = 0
[void][XingyuTrayWindow]::GetWindowThreadProcessId($window, [ref]$windowOwner)
if ($windowOwner -ne [uint32]$config.pid -or $parentProcess.HasExited) { exit 2 }
$script:sequence = 0
function Command([string]$name) {
 $script:sequence++
 $value = @{token=$config.token;sequence=$script:sequence;command=$name} | ConvertTo-Json -Compress
 [IO.File]::WriteAllText((Join-Path $work 'command.json'), $value, (New-Object Text.UTF8Encoding($false)))
}
function Restore {
 [void][XingyuTrayWindow]::ShowWindow($window, $(if ([XingyuTrayWindow]::IsIconic($window)) {9} else {5}))
 [void][XingyuTrayWindow]::SetForegroundWindow($window)
 Command 'show'
}
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.Icon]::ExtractAssociatedIcon([string]$config.icon)
if ($null -eq $tray.Icon) { $tray.Icon = [Drawing.SystemIcons]::Application }
$tray.Text = '星屿 · 正在后台运行'
$menu = New-Object Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add('打开星屿')
$open.add_Click({ Restore })
$signin = $menu.Items.Add('立即签到')
$signin.add_Click({ Command 'checkin' })
[void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$quit = $menu.Items.Add('退出星屿')
$quit.add_Click({ Command 'quit' })
$tray.ContextMenuStrip = $menu
$tray.add_MouseClick({ param($sender,$event) if ($event.Button -eq [Windows.Forms.MouseButtons]::Left) { Restore } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.add_Tick({
 if ($parentProcess.HasExited -or (Test-Path -LiteralPath (Join-Path $work 'stop'))) { [Windows.Forms.Application]::Exit() }
})
try {
 $tray.Visible = $true
 $ready = @{token=$config.token;pid=$PID} | ConvertTo-Json -Compress
 [IO.File]::WriteAllText((Join-Path $work 'ready.json'),$ready,(New-Object Text.UTF8Encoding($false)))
 $timer.Start()
 [Windows.Forms.Application]::Run()
} finally {
 $timer.Stop();$timer.Dispose();$tray.Visible=$false;$tray.Dispose();$menu.Dispose();$parentProcess.Dispose()
}
''';

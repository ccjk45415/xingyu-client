import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/error_diagnostics.dart';
import '../core/state.dart';
import '../core/windows_tray.dart';

typedef CloseChoice = ({String action, bool remember});

Future<CloseChoice?> chooseWindowsClose(BuildContext context) =>
    showDialog<CloseChoice>(
      context: context,
      builder: (context) {
        var remember = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('如何关闭星屿？'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('留在系统托盘时，已开启的后台签到和消息提醒会继续运行。'),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    icon: const Icon(Icons.desktop_windows_rounded),
                    label: const Text('最小化到系统托盘'),
                    onPressed: () => Navigator.pop(context, (
                      action: 'tray',
                      remember: remember,
                    )),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('退出程序'),
                    onPressed: () => Navigator.pop(context, (
                      action: 'exit',
                      remember: remember,
                    )),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('记住这次选择', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('可在设置的“阅读与外观”中修改'),
                    value: remember,
                    onChanged: (value) =>
                        setState(() => remember = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
      },
    );

class WindowsCloseHost extends StatefulWidget {
  final AppState app;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final TrayPort Function()? trayFactory;
  final bool? enabled;
  const WindowsCloseHost({
    super.key,
    required this.app,
    required this.navigatorKey,
    required this.child,
    this.trayFactory,
    this.enabled,
  });
  @override
  State<WindowsCloseHost> createState() => _WindowsCloseHostState();
}

class _WindowsCloseHostState extends State<WindowsCloseHost>
    with WidgetsBindingObserver {
  TrayPort? _tray;
  Future<AppExitResponse>? _closing;
  bool _quitting = false;
  bool get enabled => widget.enabled ?? Platform.isWindows;
  @override
  void initState() {
    super.initState();
    if (enabled) WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() =>
      _closing ??= _close().whenComplete(() => _closing = null);

  Future<AppExitResponse> _close() async {
    if (!enabled) return AppExitResponse.exit;
    var action = widget.app.windowsCloseAction;
    var remember = false;
    final context = widget.navigatorKey.currentContext;
    if (action == 'ask') {
      if (context == null) return AppExitResponse.cancel;
      final choice = await chooseWindowsClose(context);
      if (choice == null || !mounted) return AppExitResponse.cancel;
      action = choice.action;
      remember = choice.remember;
    }
    if (action == 'exit') {
      if (remember) await widget.app.setWindowsCloseAction(action);
      await widget.app.persist();
      await _tray?.dispose();
      return AppExitResponse.exit;
    }
    try {
      final tray = _tray ??= widget.trayFactory?.call() ?? WindowsTray();
      await tray.prepare(_command);
      if (!mounted) return AppExitResponse.cancel;
      if (remember) await widget.app.setWindowsCloseAction(action);
      tray.hide();
      widget.app.checkin.setWindowVisible(false);
    } catch (error, stack) {
      unawaited(appDiagnostics.record(error, stack, 'windows-tray'));
      await _tray?.dispose();
      _tray = null;
      if (mounted && context != null && context.mounted) {
        final exit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暂时无法启动系统托盘'),
            content: const Text('窗口已保持打开。请重试，或选择“退出程序”。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('退出程序'),
              ),
            ],
          ),
        );
        if (exit == true) {
          await widget.app.persist();
          return AppExitResponse.exit;
        }
      }
    }
    return AppExitResponse.cancel;
  }

  void _command(String command) {
    if (!mounted) return;
    if (command == 'show' || command == 'helper-failed') {
      widget.app.checkin.setWindowVisible(true);
      unawaited(widget.app.checkin.automatic(force: true));
    } else if (command == 'checkin') {
      unawaited(
        widget.app.checkin.run(source: 'tray').catchError((Object _) {}),
      );
    } else if (command == 'quit') {
      unawaited(_quit());
    }
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    await widget.app.persist();
    await _tray?.dispose();
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tray?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

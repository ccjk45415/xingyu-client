import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state.dart';
import 'core/diagnostics.dart';
import 'core/media.dart';
import 'core/error_diagnostics.dart';

import 'dart:ui';

import 'pages/private.dart';

void main(List<String> args) {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      if (args.contains('--self-check')) {
        unawaited(runSelfCheck());
        return;
      }
      FlutterError.onError = (details) {
        unawaited(
          appDiagnostics.record(
            details.exception,
            details.stack ?? StackTrace.current,
            'flutter',
          ),
        );
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(appDiagnostics.record(error, stack, 'platform'));
        return true;
      };
      unawaited(appDiagnostics.initialize());
      final app = AppState();
      app.onLogout = () {
        MediaCache.clear();
        clearPrivateDrafts();
      };
      runApp(XingyuApp(app: app));
      unawaited(app.initialize());
    },
    (error, stack) {
      unawaited(appDiagnostics.record(error, stack, 'zone'));
    },
  );
}

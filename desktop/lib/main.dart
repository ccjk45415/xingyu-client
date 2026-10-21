import 'dart:async';
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/state.dart';
import 'core/diagnostics.dart';
import 'core/media.dart';
import 'pages/private.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--self-check')) {
    unawaited(runSelfCheck());
    return;
  }
  final app = AppState();
  app.onLogout = () {
    MediaCache.clear();
    clearPrivateDrafts();
  };
  runApp(XingyuApp(app: app));
  unawaited(app.initialize());
}

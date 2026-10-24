import 'package:flutter/services.dart';

import 'api.dart';
import 'platform.dart';

/// Native permission and delivery boundary. No message text is persisted here.
class SystemNotices {
  static const channel = MethodChannel('moe.cangku.xingyu/notifications');
  void Function()? _onOpen;
  set onOpen(void Function()? value) {
    _onOpen = value;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') _onOpen?.call();
    });
  }

  Future<Json> status() async {
    try {
      return object(await channel.invokeMethod('status'));
    } on MissingPluginException {
      return {'supported': false, 'granted': false};
    }
  }

  Future<bool> request() async =>
      await channel.invokeMethod<bool>('request') ?? false;
  Future<void> settings() => channel.invokeMethod('settings');
  Future<void> configure(
    int uid,
    bool enabled,
    Json preferences, [
    Json cursors = const {},
  ]) async {
    try {
      await channel.invokeMethod('configure', {
        'uid': uid,
        'enabled': enabled,
        'origin': serviceOrigin,
        'preferences': preferences,
        'cursors': cursors,
      });
    } on MissingPluginException {
      // An older base can still receive the startup-update Dart patch.
    }
  }

  Future<void> show(Json payload) => channel.invokeMethod('show', payload);
  Future<Json> takeOpen() async {
    try {
      return object(await channel.invokeMethod('takeOpen'));
    } on MissingPluginException {
      return {};
    }
  }

  String get explanation => isAndroid
      ? '系统在后台定期检查，通常间隔至少 15 分钟，省电与网络限制可能延迟。划掉最近任务后仍可调度；强行停止后需重新打开。需要保持登录。'
      : '程序在后台运行时显示系统提醒。完全退出后暂停接收；系统专注模式可能隐藏提醒。';
}

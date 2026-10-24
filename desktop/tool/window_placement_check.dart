// Isolated native integration check. Creates and destroys only its own window.
// Does not open Xingyu, read a user account, or change the user's saved frame.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:xingyu_desktop/core/window_placement.dart';

void main(List<String> args) {
  if (!Platform.isWindows) throw UnsupportedError('Windows only');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final user = DynamicLibrary.open('user32.dll');
  final heap = kernel.lookupFunction<IntPtr Function(), int Function()>(
    'GetProcessHeap',
  )();
  final alloc = kernel
      .lookupFunction<
        Pointer<Void> Function(IntPtr, Uint32, UintPtr),
        Pointer<Void> Function(int, int, int)
      >('HeapAlloc');
  final free = kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>),
        int Function(int, int, Pointer<Void>)
      >('HeapFree');
  final create = user
      .lookupFunction<
        IntPtr Function(
          Uint32,
          Pointer<Uint16>,
          Pointer<Uint16>,
          Uint32,
          Int32,
          Int32,
          Int32,
          Int32,
          IntPtr,
          IntPtr,
          IntPtr,
          Pointer<Void>,
        ),
        int Function(
          int,
          Pointer<Uint16>,
          Pointer<Uint16>,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateWindowExW');
  final show = user
      .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
        'ShowWindow',
      );
  final destroy = user
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DestroyWindow',
      );
  final strings = alloc(heap, 8, 512);
  if (strings == nullptr) throw StateError('Allocation failed');
  var handle = 0;
  void check(bool condition, String step) {
    if (!condition) throw StateError('Window integration: $step');
  }

  final report = <String, Object>{};
  try {
    final className = strings.cast<Uint16>();
    className.asTypedList(7).setAll(0, 'STATIC\x00'.codeUnits);
    final title = (strings.cast<Uint8>() + 64).cast<Uint16>();
    const label = 'Xingyu isolated window test\x00';
    title.asTypedList(label.length).setAll(0, label.codeUnits);
    handle = create(
      0,
      className,
      title,
      0x00cf0000,
      160,
      120,
      920,
      680,
      0,
      0,
      0,
      nullptr,
    );
    check(handle != 0, 'create own test frame');
    show(handle, 1);
    final port = WindowsPlacement(windowClass: 'Static');
    final initial = port.read();
    check(initial != null && !initial.maximized, 'find own process frame');
    final changed = RememberedWindow(
      left: initial!.left + 35,
      top: initial.top + 25,
      right: initial.left + 855,
      bottom: initial.top + 645,
      maximized: false,
    );
    check(port.restore(changed), 'restore normal');
    check(
      jsonEncode(port.read()!.toJson()) == jsonEncode(changed.toJson()),
      'read exact moved/resized workspace coordinates',
    );
    report['normal_move_resize'] = 'pass';
    show(handle, 3);
    final maximized = port.read();
    check(maximized?.maximized == true, 'read maximized');
    show(handle, 2);
    check(port.read() == null, 'ignore minimized');
    check(port.restore(maximized!), 'restore maximized');
    check(port.read()?.maximized == true, 'maximized reapplied');
    report['maximized_and_minimized'] = 'pass';
    check(port.restore(changed), 'restore after maximized');
    check(
      jsonEncode(port.read()!.toJson()) == jsonEncode(changed.toJson()),
      'normal bounds retained after maximization',
    );
    report['normal_bounds_after_maximized'] = 'pass';
    check(
      port.restore(
        const RememberedWindow(
          left: 100000,
          top: 100000,
          right: 100920,
          bottom: 100680,
          maximized: false,
        ),
      ),
      'restore disconnected monitor',
    );
    check(
      port.read()!.left < 100000 && port.read()!.top < 100000,
      'offscreen frame brought back',
    );
    report['offscreen_recovery'] = 'pass';
    report['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (args.length == 1) {
      File(args.single).writeAsStringSync(jsonEncode(report));
    }
    stdout.writeln(jsonEncode(report));
  } finally {
    if (handle != 0) destroy(handle);
    free(heap, 0, strings);
  }
}

import 'dart:ffi';
import 'dart:io';

/// WINDOWPLACEMENT uses workspace coordinates, including negative coordinates
/// on secondary monitors. Keep Get/SetWindowPlacement paired (not SetWindowPos).
class RememberedWindow {
  final int left, top, right, bottom;
  final bool maximized;
  const RememberedWindow({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.maximized,
  });

  static RememberedWindow? decode(Object? value) {
    if (value is! Map || value['schema'] != 1 || value['maximized'] is! bool) {
      return null;
    }
    final coordinates = [
      'left',
      'top',
      'right',
      'bottom',
    ].map((key) => value[key]).toList();
    if (coordinates.any((n) => n is! int || n.abs() > 1000000)) {
      return null;
    }
    final [left, top, right, bottom] = coordinates.cast<int>();
    if (right - left < 100 ||
        bottom - top < 100 ||
        right - left > 50000 ||
        bottom - top > 50000) {
      return null;
    }
    return RememberedWindow(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      maximized: value['maximized'] as bool,
    );
  }

  Map<String, Object> toJson() => {
    'schema': 1,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'maximized': maximized,
  };
}

abstract interface class WindowPlacementPort {
  /// Null while minimized or before the runner's main window is visible.
  RememberedWindow? read();
  bool restore(RememberedWindow value);
}

/// No new native plugin or executable: binds only to Windows' installed DLLs.
/// This lets the Windows release receive this behavior as a Dart-only patch.
class WindowsPlacement implements WindowPlacementPort {
  int get windowHandle => _findWindow();
  final String windowClass;
  int _window = 0;
  WindowsPlacement({this.windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW'});
  final _user = DynamicLibrary.open('user32.dll');
  final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _top = _user
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
        'GetTopWindow',
      );
  late final _next = _user
      .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
        'GetWindow',
      );
  late final _owner = _user
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId');
  late final _visible = _user
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'IsWindowVisible',
      );
  late final _class = _user
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint16>, Int32),
        int Function(int, Pointer<Uint16>, int)
      >('GetClassNameW');
  late final _get = _user
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Int32>),
        int Function(int, Pointer<Int32>)
      >('GetWindowPlacement');
  late final _set = _user
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Int32>),
        int Function(int, Pointer<Int32>)
      >('SetWindowPlacement');
  late final _heap = _kernel.lookupFunction<IntPtr Function(), int Function()>(
    'GetProcessHeap',
  )();
  late final _alloc = _kernel
      .lookupFunction<
        Pointer<Void> Function(IntPtr, Uint32, UintPtr),
        Pointer<Void> Function(int, int, int)
      >('HeapAlloc');
  late final _free = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>),
        int Function(int, int, Pointer<Void>)
      >('HeapFree');

  T _buffer<T>(int bytes, T Function(Pointer<Void>) use) {
    final pointer = _alloc(_heap, 8, bytes); // HEAP_ZERO_MEMORY
    if (pointer == nullptr) throw StateError('Window buffer unavailable');
    try {
      return use(pointer);
    } finally {
      _free(_heap, 0, pointer);
    }
  }

  int _findWindow() => _buffer(256, (memory) {
    final process = memory.cast<Uint32>();
    if (_window != 0 && _visible(_window) != 0) {
      _owner(_window, process);
      if (process.value == pid) return _window;
    }
    final className = (memory.cast<Uint8>() + 8).cast<Uint16>();
    var window = _top(0);
    // Iterate instead of registering an FFI callback on the native UI thread.
    for (var count = 0; window != 0 && count < 10000; count++) {
      _owner(window, process);
      if (process.value == pid && _visible(window) != 0) {
        final length = _class(window, className, 120);
        if (String.fromCharCodes(className.asTypedList(length)) ==
            windowClass) {
          return _window = window;
        }
      }
      window = _next(window, 2); // GW_HWNDNEXT
    }
    return 0;
  });

  @override
  RememberedWindow? read() {
    final window = _findWindow();
    if (window == 0) return null;
    return _buffer(44, (memory) {
      final pointer = memory.cast<Int32>();
      final words = pointer.asTypedList(11)..[0] = 44;
      if (_get(window, pointer) == 0) return null;
      // SW_SHOWNORMAL / SW_SHOWMAXIMIZED only. Never persist minimized state.
      if (words[2] != 1 && words[2] != 3) return null;
      return RememberedWindow.decode({
        'schema': 1,
        'left': words[7],
        'top': words[8],
        'right': words[9],
        'bottom': words[10],
        'maximized': words[2] == 3,
      });
    });
  }

  @override
  bool restore(RememberedWindow value) {
    final window = _findWindow();
    if (window == 0) return false;
    return _buffer(44, (memory) {
      final pointer = memory.cast<Int32>();
      final words = pointer.asTypedList(11);
      words[0] = 44;
      words[2] = value.maximized ? 3 : 1;
      words[3] = words[4] = words[5] = words[6] = -1;
      words[7] = value.left;
      words[8] = value.top;
      words[9] = value.right;
      words[10] = value.bottom;
      // Windows also brings entirely off-screen placements onto a live monitor.
      return _set(window, pointer) != 0;
    });
  }
}

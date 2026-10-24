import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/window_memory.dart';

class FakePlacement implements WindowPlacementPort {
  RememberedWindow? current;
  int restores = 0;
  FakePlacement(this.current);
  @override
  RememberedWindow? read() => current;
  @override
  bool restore(RememberedWindow value) {
    current = value;
    restores++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  const regular = RememberedWindow(
    left: -1500,
    top: 140,
    right: -400,
    bottom: 940,
    maximized: false,
  );
  const maximized = RememberedWindow(
    left: 200,
    top: 100,
    right: 1300,
    bottom: 900,
    maximized: true,
  );
  setUp(() {
    directory = Directory.systemTemp.createTempSync('xingyu-window-memory-');
    file = File('${directory.path}/window.json');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('reopening restores negative monitor coordinates and normal size', () {
    WindowMemory(port: FakePlacement(regular), file: file).capture();
    final next = FakePlacement(maximized);
    WindowMemory(port: next, file: file).restore();
    expect(next.restores, 1);
    expect(next.current!.toJson(), regular.toJson());
  });
  test(
    'maximized remembers restore bounds; minimized exit keeps last state',
    () async {
      final port = FakePlacement(maximized);
      final memory = WindowMemory(port: port, file: file);
      memory.capture();
      port.current =
          null; // Native minimized placements are deliberately ignored.
      await memory.didRequestAppExit();
      final next = FakePlacement(null);
      WindowMemory(port: next, file: file).restore();
      expect(next.current!.toJson(), maximized.toJson());
    },
  );
  test(
    'exit captures the final move even before next polling interval',
    () async {
      final port = FakePlacement(regular);
      final memory = WindowMemory(port: port, file: file);
      memory.capture();
      port.current = maximized;
      await memory.didRequestAppExit();
      expect(jsonDecode(file.readAsStringSync()), maximized.toJson());
      expect(File('${file.path}.tmp').existsSync(), false);
    },
  );
  test('invalid or oversized settings are ignored and replaced safely', () {
    final port = FakePlacement(regular);
    final memory = WindowMemory(port: port, file: file);
    file.writeAsStringSync(jsonEncode({...regular.toJson(), 'right': -2000}));
    memory.restore();
    expect(port.restores, 0);
    file.writeAsStringSync(' ' * 4097);
    memory.restore();
    expect(port.restores, 0);
    memory.capture();
    expect(jsonDecode(file.readAsStringSync()), regular.toJson());
  });
  test(
    'missing settings preserve first-launch placement; idle does not rewrite',
    () {
      final port = FakePlacement(regular);
      final memory = WindowMemory(port: port, file: file);
      memory.restore();
      expect(port.restores, 0);
      memory.capture();
      final sentinel = DateTime(2025);
      file.setLastModifiedSync(sentinel);
      memory.capture();
      expect(file.lastModifiedSync(), sentinel);
    },
  );
  test('rejects wrong schema, nonintegers, huge and empty rectangles', () {
    for (final input in [
      null,
      [],
      {...regular.toJson(), 'schema': 2},
      {...regular.toJson(), 'left': 0.1},
      {...regular.toJson(), 'bottom': 1000001},
      {...regular.toJson(), 'right': regular.left},
      {...regular.toJson(), 'maximized': 'true'},
    ]) {
      expect(RememberedWindow.decode(input), isNull);
    }
  });
}

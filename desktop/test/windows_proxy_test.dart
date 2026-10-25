import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/platform.dart';

void main() {
  final https = Uri.parse('https://cangku.moe/api/v1/auth/me');
  test(
    'manual Windows system proxy selects protocol and validates endpoint',
    () {
      expect(
        windowsProxyDirective(https, '127.0.0.1:7890', ''),
        'PROXY 127.0.0.1:7890',
      );
      expect(
        windowsProxyDirective(
          https,
          'http=localhost:8080;https=[::1]:7890;socks=localhost:1080',
          '',
        ),
        'PROXY [::1]:7890',
      );
      expect(
        windowsProxyDirective(
          Uri.parse('http://file.cangku.moe'),
          'http=localhost:8080;https=localhost:7890',
          '',
        ),
        'PROXY localhost:8080',
      );
      for (final invalid in [
        '',
        'localhost:0',
        'localhost:65536',
        'user:password@localhost:7890',
        'http://localhost:7890',
        'socks=localhost:1080',
      ]) {
        expect(windowsProxyDirective(https, invalid, ''), 'DIRECT');
      }
    },
  );
  test('system proxy bypass rules preserve local and exact host routing', () {
    expect(
      windowsProxyDirective(https, 'localhost:7890', '<local>;*.cangku.moe'),
      'PROXY localhost:7890',
    );
    expect(
      windowsProxyDirective(
        Uri.parse('https://file.cangku.moe'),
        'localhost:7890',
        '*.cangku.moe',
      ),
      'DIRECT',
    );
    expect(
      windowsProxyDirective(
        Uri.parse('http://printer'),
        'localhost:7890',
        '<local>',
      ),
      'DIRECT',
    );
    expect(
      windowsProxyDirective(https, 'localhost:7890', 'CANGKU.MOE'),
      'DIRECT',
    );
    expect(
      windowsProxyDirective(https, 'localhost:7890', 'cangku.moe.evil'),
      'PROXY localhost:7890',
    );
  });
}

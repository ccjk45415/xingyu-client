import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/api.dart';

class _RealNetwork extends HttpOverrides {}

void main() {
  testWidgets(
    'public DLsite source extracts through real proxy DNS without AI calls',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final transport = AiTransport();
          try {
            const link =
                'https://www.dlsite.com/maniax-touch/work/=/product_id/RJ01721474.html';
            final addresses = await InternetAddress.lookup('www.dlsite.com');
            final source = await transport.source(link);
            expect(text(source['url']), contains('dlsite.com'));
            expect(text(source['text']).length, greaterThan(100));
            expect(text(source['url']), contains('RJ01721474'));
            final evidence = File(
              '${Directory(Directory.current.resolveSymbolicLinksSync()).parent.path}/evidence/ai-source-network-live.json',
            );
            await evidence.writeAsString(
              jsonEncode({
                'source_host': 'www.dlsite.com',
                'source_id': 'RJ01721474',
                'proxy_fake_ip_observed': addresses.any(proxyAddress),
                'public_dns_confirmation': addresses.any(proxyAddress),
                'html_extracted': true,
                'text_length': text(source['text']).length,
                'cover_found': text(source['cover']).startsWith('https://'),
                'ai_generations': 0,
                'credentials_sent': false,
                'tls_validation_disabled': false,
              }),
            );
          } finally {
            transport.close();
          }
        }, _RealNetwork()),
      );
    },
    skip: Platform.environment['XINGYU_TEST_SOURCE'] != '1',
  );
}

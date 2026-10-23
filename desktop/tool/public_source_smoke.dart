import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/submission_guidance.dart';
import 'package:xingyu_desktop/core/submission_workbench.dart';
import 'package:xingyu_desktop/core/video_source.dart';

class RealNetwork extends HttpOverrides {}

void main() {
  testWidgets(
    'public Steam metadata/trailers and DLsite formal type plus chobit stream',
    (tester) async {
      final guide = await SubmissionGuidance.load();
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final io = AiTransport();
          try {
            final steam = await io.source(
              'https://store.steampowered.com/app/620/Portal_2/',
            );
            final fields = structuredSourceFields([steam]);
            for (final label in ['开发商', '发行商', '发行日期']) {
              expect(
                fields.any(
                  (f) => f['label'] == label && text(f['value']).isNotEmpty,
                ),
                true,
              );
            }
            expect(
              rows(steam['blocks']).where((b) => b['kind'] == 'video'),
              isNotEmpty,
            );
            expect(guide.guess([steam]), 'game');
            final dlsite = await io.source(
              'https://www.dlsite.com/maniax/work/=/product_id/RJ01731048.html',
            );
            expect(guide.guess([dlsite]), 'game');
            expect(text(dlsite['text']).length, greaterThan(500));
            final video = await io.playableVideo(
              'https://chobit.cc/embed/a0bdo',
            );
            expect(directVideoUrl(video), true);
            final root = Directory(Directory.current.resolveSymbolicLinksSync())
                .parent
                .path;
            await File(
              '$root/evidence/authoring-source-live.json',
            ).writeAsString(
              jsonEncode({
                'steam_metadata_labels': fields.map((f) => f['label']).toList(),
                'steam_type': guide.guess([steam]),
                'steam_videos': rows(steam['blocks'])
                    .where((b) => b['kind'] == 'video')
                    .length,
                'dlsite_type_codes': dlsite['work_type_codes'],
                'dlsite_type': guide.guess([dlsite]),
                'dlsite_text_length': text(dlsite['text']).length,
                'chobit_public_stream_resolved': true,
                'media_host': Uri.parse(video).host,
                'credentials_sent': false,
                'ai_calls': 0,
              }),
            );
          } finally {
            io.close();
          }
        }, RealNetwork()),
      );
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';

import 'ai_test.dart' show Headers;

class PendingRequest implements HttpClientRequest {
  @override
  final Headers headers = Headers();
  bool aborted = false, sent = false;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  void write(Object? value) {
    sent = true;
  }

  @override
  void add(List<int> data) {
    sent = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeferredClient implements HttpClient {
  final opening = Completer<HttpClientRequest>();
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => opening.future;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => opening.future;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final upload in [false, true]) {
    test(
      'account switch while opening ${upload ? 'upload' : 'post'} aborts before transmitting',
      () async {
        SecureVault.setMockInitialValues({});
        final client = DeferredClient(), request = PendingRequest();
        final scoped = SiteApi(client: client);
        final work = upload
            ? scoped.upload(
                'upload/image',
                'image',
                Uint8List.fromList([1, 2, 3]),
              )
            : scoped.post('post/create', {
                'title': 'Synthetic pending post',
                'content': 'not sent',
              });
        final rejected = expectLater(
          work,
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
        );
        await scoped.clear();
        client.opening.complete(request);
        await rejected;
        expect(request.aborted, true);
        expect(request.sent, false);
        expect(request.headers.values, isEmpty);
        scoped.close();
      },
    );
  }
}

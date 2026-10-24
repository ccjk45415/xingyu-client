import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'state.dart';

const clientConfigPublicKey = '+G+zF1gen2I8ziXBE14QxbGyXJKqS8a8R/ibO0g4qSk=';
const defaultClientUi = <String, dynamic>{
  'home': {
    'mobile_height': 124,
    'desktop_height': 140,
    'banner_order': ['announcement', 'discovery'],
    'card_density': 'normal',
  },
  'labels': {'announcement': '公告', 'discovery': '发现', 'checkin': '签到'},
  'features': {'checkin': true, 'cloud_checkin': true, 'pinned': true},
};

bool validClientUi(Json value) {
  bool exact(Json object, Set<String> keys) =>
      object.keys.toSet().difference(keys).isEmpty &&
      object.length == keys.length;
  final home = object(value['home']),
      labels = object(value['labels']),
      features = object(value['features']);
  final order = home['banner_order'];
  return exact(value, {'home', 'labels', 'features'}) &&
      exact(home, {
        'mobile_height',
        'desktop_height',
        'banner_order',
        'card_density',
      }) &&
      home['mobile_height'] is int &&
      number(home['mobile_height']) >= 100 &&
      number(home['mobile_height']) <= 180 &&
      home['desktop_height'] is int &&
      number(home['desktop_height']) >= 100 &&
      number(home['desktop_height']) <= 200 &&
      order is List &&
      order.length == 2 &&
      order.toSet().containsAll({'announcement', 'discovery'}) &&
      ['normal', 'compact'].contains(home['card_density']) &&
      exact(labels, {'announcement', 'discovery', 'checkin'}) &&
      labels.values.every(
        (v) =>
            v is String &&
            v.trim().isNotEmpty &&
            v.runes.length <= 16 &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(v),
      ) &&
      exact(features, {'checkin', 'cloud_checkin', 'pinned'}) &&
      features.values.every((v) => v is bool);
}

Future<Json?> verifyClientConfig(
  dynamic input, {
  String publicKey = clientConfigPublicKey,
  DateTime? now,
}) async {
  try {
    final envelope = object(input);
    if (envelope.length != 2 ||
        envelope['payload'] is! String ||
        envelope['signature'] is! String ||
        text(envelope['payload']).length > 48000) {
      return null;
    }
    final bytes = base64Decode(envelope['payload']),
        signature = base64Decode(envelope['signature']);
    if (bytes.length > 32000 || signature.length != 64) return null;
    if (!await Ed25519().verify(
      bytes,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          base64Decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    )) {
      return null;
    }
    final value = object(jsonDecode(utf8.decode(bytes))),
        current = now ?? DateTime.now();
    final issued = DateTime.tryParse(text(value['issued_at'])),
        expires = DateTime.tryParse(text(value['expires_at']));
    if (value.length != 6 ||
        value['schema'] != 1 ||
        value['product'] != 'moe.cangku.xingyu' ||
        value['revision'] is! int ||
        number(value['revision']) < 1 ||
        issued == null ||
        expires == null ||
        issued.isAfter(current.add(const Duration(minutes: 5))) ||
        !expires.isAfter(current) ||
        !expires.isAfter(issued) ||
        expires.difference(issued) > const Duration(days: 31) ||
        !validClientUi(object(value['config']))) {
      return null;
    }
    return value;
  } catch (_) {
    return null;
  }
}

class ClientConfigStore extends ChangeNotifier {
  final AppState app;
  Json ui = defaultClientUi;
  int revision = 0;
  bool loading = false;
  bool _disposed = false;
  DateTime? updatedAt;
  DateTime _checked = DateTime(2000);
  ClientConfigStore(this.app);
  String label(String key, String fallback) =>
      text(object(ui['labels'])[key], fallback);
  bool enabled(String feature) => object(ui['features'])[feature] != false;
  double bannerHeight(bool mobile) =>
      number(object(ui['home'])[mobile ? 'mobile_height' : 'desktop_height'])
          .toDouble();
  List<String> get bannerOrder =>
      (object(ui['home'])['banner_order'] as List).cast<String>();
  bool get compactCards => object(ui['home'])['card_density'] == 'compact';
  Future<void> initialize() async {
    await accept(app.local['signedClientConfig'], persist: false);
    unawaited(refresh());
  }

  Future<bool> accept(dynamic envelope, {bool persist = true}) async {
    final verified = await verifyClientConfig(envelope);
    if (_disposed ||
        verified == null ||
        number(verified['revision']) <= revision) {
      return false;
    }
    revision = number(verified['revision']);
    ui = object(verified['config']);
    updatedAt = DateTime.parse(verified['issued_at']);
    app.local['signedClientConfig'] = envelope;
    notifyListeners();
    if (persist) await app.persist();
    return true;
  }

  Future<void> refresh({bool force = false}) async {
    if (_disposed ||
        loading ||
        !force &&
            DateTime.now().difference(_checked) < const Duration(minutes: 10)) {
      return;
    }
    loading = true;
    _checked = DateTime.now();
    notifyListeners();
    try {
      await accept(await app.service.request('/client-config'));
    } catch (_) {
      /* Keep the last signature-verified configuration offline. */
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

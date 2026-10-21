# Third-party notices

The MIT license in this repository covers its own application and service code.
Website content, account data, user messages, and third-party packages retain
their respective rights and licenses; no website content or user database is
distributed in this repository.

- Android QR decoding: [ZXing core 3.5.4](https://github.com/zxing/zxing/tree/zxing-3.5.4), Apache License 2.0. Full license: `app/src/main/assets/third_party/LICENSE.zxing.txt`, included in APK assets. The jar is fetched from Maven Central and checked against a pinned SHA-256 by `tools/prepare_qr.py`; it is not committed.
- Windows QR decoding: [zxing2 0.2.4](https://pub.dev/packages/zxing2), BSD-3-Clause (the package's LICENSE), with ZXing-derived files carrying their upstream notices. Registered charset codecs normalize signed bytes in application code for correct UTF-8. No dependency cache files are patched.
- [Flutter](https://github.com/flutter/flutter) and its Windows engine: BSD-style licenses; see `LICENSE.flutter.txt` in the Windows ZIP and `data/flutter_assets/NOTICES.Z` for package notices.
- Other Dart packages and versions are locked in `desktop/pubspec.lock`; their notices are bundled by Flutter in `data/flutter_assets/NOTICES.Z`.
- Microsoft C/C++ redistributable runtime DLLs in the Windows ZIP remain subject to Microsoft's redistribution terms. No Windows SDK, compiler or Flutter SDK is committed.
- Optional JVM source-network live regression: [JSON-java 20240303](https://github.com/stleary/JSON-java/tree/20240303), test dependency only; see its upstream LICENSE. The Maven jar is SHA256-pinned, stored outside source delivery and not bundled into either client. Android uses the platform's org.json.
- Android introduction parsing: [jsoup 1.23.2](https://jsoup.org/), MIT license. Maven artifact is SHA256-pinned by `tools/prepare_html.py`; full license is bundled at `app/src/main/assets/third_party/LICENSE.jsoup.txt`. Only DOM parsing is used, never jsoup's HTTP client.

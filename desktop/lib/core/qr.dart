import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'api.dart';

// ZXing2's byte segments use Int8List. Dart codecs expect unsigned byte values.
// The public charset registry adapter preserves mixed segment order and Unicode.
class _UnsignedEncoding extends Encoding {
  final Encoding delegate;
  _UnsignedEncoding(this.delegate);
  @override
  String get name => delegate.name;
  @override
  Converter<String, List<int>> get encoder => delegate.encoder;
  @override
  Converter<List<int>, String> get decoder => _UnsignedDecoder(delegate);
}

class _UnsignedDecoder extends Converter<List<int>, String> {
  final Encoding encoding;
  _UnsignedDecoder(this.encoding);
  @override
  String convert(List<int> input) => encoding.decode(Uint8List.fromList(input));
}

/// Decode first frame locally in an isolate. No decoded value is ever executed.
String? decodeQr(Uint8List data) {
  for (final charset in CharacterSetECI.all) {
    if (charset.encoding is! _UnsignedEncoding) {
      charset.encoding = _UnsignedEncoding(charset.encoding);
    }
  }
  if (data.length > 10 * 1024 * 1024) throw const FormatException('图片超过10MB');
  final decoder = img.findDecoderForData(data),
      info = img.findDecoderForData(data)?.startDecode(data);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 16000000) {
    throw const FormatException('图片格式不支持或超过1600万像素');
  }
  var image = decoder?.decode(data, frame: 0);
  if (image == null) throw const FormatException('无法读取图片');
  image = img.bakeOrientation(image);
  if (image.width > 2048 || image.height > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
    );
  }
  final white = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  img.fill(white, color: img.ColorRgb8(255, 255, 255));
  image = img.compositeImage(white, image);
  final hints = DecodeHints()
    ..put(DecodeHintType.tryHarder)
    ..put(DecodeHintType.characterSet, 'UTF-8');
  for (var turn = 0; turn < 4; turn++) {
    final pixels = Int32List(image!.width * image.height);
    for (final p in image) {
      pixels[p.y * image.width + p.x] =
          (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    for (var invert = 0; invert < 2; invert++) {
      try {
        final result = QRCodeReader()
            .decode(
              BinaryBitmap(
                HybridBinarizer(invert == 0 ? source : source.invert()),
              ),
              hints: hints,
            )
            .text
            .trim();
        if (result.isNotEmpty && result.length <= 8192) return result;
      } on ReaderException {
        /* Try the next orientation/contrast. */
      }
    }
    image = img.copyRotate(image, angle: 90);
  }
  return null;
}

Future<Uint8List> fetchQrImage(String raw) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  var url = Uri.tryParse(raw);
  try {
    for (var redirects = 0; redirects < 4; redirects++) {
      if (url == null ||
          !['http', 'https'].contains(url.scheme) ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw const FormatException('图片地址无效');
      }
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set('Referer', '$siteOrigin/');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value('location');
        if (location == null) throw const FormatException('图片重定向无效');
        url = url.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          response.contentLength > 10 * 1024 * 1024) {
        throw const FormatException('图片无法加载或超过10MB');
      }
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        size += chunk.length;
        if (size > 10 * 1024 * 1024) throw const FormatException('图片超过10MB');
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    throw const FormatException('图片重定向过多');
  } finally {
    client.close(force: true);
  }
}

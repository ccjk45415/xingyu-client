String imageDimensionSource(String style, String attribute, String name) =>
    RegExp(
      '(?:^|;)\\s*$name\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style)?.group(1)?.trim() ??
    attribute;

double? imageDimension(String raw, double bound) {
  if (bound <= 0) return null;
  final value = raw.trim().toLowerCase();
  if (!RegExp(r'^\d+(?:\.\d+)?(?:px|%)?$').hasMatch(value)) return null;
  final number = double.tryParse(value.replaceAll(RegExp(r'px|%'), ''));
  if (number == null || number <= 0 || !number.isFinite) return null;
  if (value.endsWith('%')) {
    return bound.isFinite ? bound * number.clamp(0, 100) / 100 : null;
  }
  return number.clamp(1, bound.isFinite ? bound : 10000).toDouble();
}

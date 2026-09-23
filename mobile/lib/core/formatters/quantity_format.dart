String compactQuantity(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return value.trim();
  if (parsed == parsed.truncateToDouble()) {
    return parsed.toInt().toString();
  }
  return parsed
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

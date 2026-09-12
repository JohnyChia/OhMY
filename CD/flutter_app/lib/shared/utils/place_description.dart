String? usablePlaceDescription(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[.!]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  if ({
    'desc unavailable',
    'description unavailable',
    'not available',
    'n/a',
    'unavailable',
  }.contains(normalized)) {
    return null;
  }
  return text;
}

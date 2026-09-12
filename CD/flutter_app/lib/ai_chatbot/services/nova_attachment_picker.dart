import 'package:flutter/services.dart';

class NovaPickedDocument {
  const NovaPickedDocument({
    required this.path,
    required this.name,
    required this.mimeType,
  });
  final String path;
  final String name;
  final String mimeType;
}

class NovaAttachmentPicker {
  NovaAttachmentPicker._();
  static const MethodChannel _channel = MethodChannel('ohmy/nova_attachment');

  static Future<NovaPickedDocument?> pickDocument() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickNovaDocument',
    );
    if (result == null) return null;
    return NovaPickedDocument(
      path: result['path']?.toString() ?? '',
      name: result['name']?.toString() ?? 'attachment',
      mimeType: result['mimeType']?.toString() ?? 'application/octet-stream',
    );
  }
}

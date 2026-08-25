import 'package:flutter/services.dart';

class PandoraTextAttachment {
  const PandoraTextAttachment({
    required this.name,
    required this.mimeType,
    required this.text,
  });

  final String name;
  final String mimeType;
  final String text;

  String get promptBlock => 'Attached file: $name ($mimeType)\n---\n$text\n---';
}

abstract final class PandoraNativeIo {
  static const MethodChannel _channel = MethodChannel('pandora/native_io');

  static Future<String?> dictate() async {
    try {
      final value = await _channel.invokeMethod<String>('speechToText');
      final text = value?.trim();
      return text == null || text.isEmpty ? null : text;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<PandoraTextAttachment?> pickTextAttachment() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'pickTextDocument',
      );
      if (value == null) return null;
      final name = value['name'];
      final mimeType = value['mimeType'];
      final text = value['text'];
      if (name is! String || text is! String || text.trim().isEmpty) {
        return null;
      }
      return PandoraTextAttachment(
        name: name.trim(),
        mimeType: mimeType is String && mimeType.trim().isNotEmpty
            ? mimeType.trim()
            : 'text/plain',
        text: text,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

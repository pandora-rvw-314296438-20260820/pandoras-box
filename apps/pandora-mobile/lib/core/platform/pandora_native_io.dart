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

class PandoraImageAttachment {
  const PandoraImageAttachment({
    required this.name,
    required this.mimeType,
    required this.dataBase64,
  });

  final String name;
  final String mimeType;
  final String dataBase64;
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

  static Future<bool> openExternalUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openExternalUrl',
            <String, Object?>{'url': uri.toString()},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openPreviewBundle(
    List<Map<String, Object?>> files,
  ) async {
    if (files.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openPreviewBundle',
            <String, Object?>{'files': files},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> saveBinaryDocument({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final safeName = name.trim();
    final safeMime = mimeType.trim();
    if (safeName.isEmpty || safeMime.isEmpty || bytes.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'saveBinaryDocument',
            <String, Object?>{
              'name': safeName,
              'mimeType': safeMime,
              'data': bytes,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
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

  static Future<PandoraImageAttachment?> pickPhoto() => _pickImage('pickPhoto');

  static Future<PandoraImageAttachment?> takePhoto() => _pickImage('takePhoto');

  static Future<PandoraImageAttachment?> _pickImage(String method) async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(method);
      if (value == null) return null;
      final name = value['name'];
      final mimeType = value['mimeType'];
      final dataBase64 = value['dataBase64'];
      if (name is! String ||
          mimeType is! String ||
          dataBase64 is! String ||
          dataBase64.isEmpty) {
        return null;
      }
      return PandoraImageAttachment(
        name: name.trim(),
        mimeType: mimeType.trim(),
        dataBase64: dataBase64,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

import 'dart:convert';

/// A bounded SSE decoder. Network chunks are not frames (or UTF-8 characters).
/// Comments/heartbeats never become conversation events or artificial progress.
Stream<Map<String, dynamic>> decodePandoraSse(
  Stream<List<int>> bytes, {
  int maxFrameCharacters = 262144,
  int maxResponseBytes = 8 * 1024 * 1024,
}) async* {
  var received = 0;
  final bounded = bytes.map((chunk) {
    received += chunk.length;
    if (received > maxResponseBytes) {
      throw const FormatException('Chat stream exceeded its response limit.');
    }
    return chunk;
  });
  var frame = <String>[];
  var frameSize = 0;
  await for (final line in bounded
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (frame.isEmpty) continue;
      final value = jsonDecode(frame.join('\n'));
      frame = <String>[];
      frameSize = 0;
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid chat event.');
      }
      yield value;
      continue;
    }
    if (line.startsWith(':')) continue;
    if (line.length > maxFrameCharacters) {
      throw const FormatException('Chat stream frame exceeded its limit.');
    }
    if (!line.startsWith('data:')) continue;
    final value = line.substring(line.startsWith('data: ') ? 6 : 5);
    frameSize += value.length;
    if (frameSize > maxFrameCharacters) {
      throw const FormatException('Chat stream frame exceeded its limit.');
    }
    frame.add(value);
  }
  // SSE commits an event only at an empty line. A disconnected partial frame
  // is deliberately not interpreted as an accepted/complete result.
  if (frame.isNotEmpty) {
    throw const FormatException('Chat stream ended during an event.');
  }
}

import 'dart:math';

class IdempotencyKeyFactory {
  IdempotencyKeyFactory({Random? random, DateTime Function()? clock})
    : _random = random ?? Random.secure(),
      _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;
  var _sequence = 0;

  String create(String operation) {
    _sequence = (_sequence + 1) & 0x7fffffff;
    final safeOperation = operation
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final randomHex = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'pandora:${safeOperation.isEmpty ? 'request' : safeOperation}:'
        '${_clock().toUtc().microsecondsSinceEpoch}:$_sequence:$randomHex';
  }
}

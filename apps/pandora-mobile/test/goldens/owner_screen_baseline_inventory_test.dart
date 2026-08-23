import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _baselineDirectory = 'test/goldens/owner_screens';
const _expectedBaselines = <String>{
  'activity_populated_porcelain_390x844.png',
  'approvals_high_risk_1_6x_text_390x844.png',
  'approvals_high_risk_porcelain_390x844.png',
  'command_initial_porcelain_390x844.png',
  'connections_degraded_graphite_390x844.png',
  'connections_healthy_porcelain_390x844.png',
  'home_attention_porcelain_320x800.png',
  'home_attention_porcelain_390x844.png',
  'home_degraded_graphite_390x844.png',
  'home_loading_porcelain_390x844.png',
  'memory_approved_porcelain_390x844.png',
  'project_detail_porcelain_390x844.png',
  'projects_list_porcelain_390x844.png',
  'safety_protected_porcelain_390x844.png',
  'settings_porcelain_390x844.png',
};

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

int _readUint32BigEndian(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void main() {
  test('committed baseline inventory is exact and structurally valid', () {
    final directory = Directory(_baselineDirectory);
    expect(
      directory.existsSync(),
      isTrue,
      reason: 'Reviewed visual baselines must be committed before CI runs.',
    );

    final actualBaselines = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.png'))
        .toSet();
    expect(actualBaselines, equals(_expectedBaselines));

    for (final name in _expectedBaselines) {
      final file = File('$_baselineDirectory/$name');
      final bytes = file.readAsBytesSync();
      expect(
        bytes.length,
        greaterThan(1024),
        reason: '$name must contain a non-empty widget capture.',
      );
      expect(bytes.take(8).toList(), equals(_pngSignature));

      final width = _readUint32BigEndian(bytes, 16);
      final height = _readUint32BigEndian(bytes, 20);
      final expectedWidth = name.contains('320x800') ? 320 : 390;
      final expectedHeight = name.contains('320x800') ? 800 : 844;
      expect(
        (width, height),
        equals((expectedWidth, expectedHeight)),
        reason: '$name must retain its declared logical phone dimensions.',
      );
    }
  });
}

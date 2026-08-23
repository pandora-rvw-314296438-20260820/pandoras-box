import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/widgets/owner_experience.dart';

void main() {
  test('ownerRelativeTime keeps owner-facing timestamps concise', () {
    final now = DateTime.utc(2026, 8, 18, 4);

    expect(ownerRelativeTime(null, now: now), 'Time not verified');
    expect(
      ownerRelativeTime(now.subtract(const Duration(minutes: 30)), now: now),
      '30m ago',
    );
    expect(
      ownerRelativeTime(now.subtract(const Duration(hours: 2)), now: now),
      '2h ago',
    );
    expect(
      ownerRelativeTime(now.add(const Duration(hours: 3)), now: now),
      'In 3h',
    );
  });
}

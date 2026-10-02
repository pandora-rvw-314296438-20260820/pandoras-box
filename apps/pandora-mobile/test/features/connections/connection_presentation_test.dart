import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/connections/connection_presentation.dart';

void main() {
  test('state synthesis returns Partial when some provider truth exists', () {
    expect(
      synthesizeConnectionCardState(
        state: 'Connected',
        rawStatus: 'Authorized',
        canUseNow: false,
        accountVerified: true,
        scopesVerified: false,
        capabilityAvailability: const <bool>[true, false],
      ),
      ConnectionCardState.partial,
    );
  });

  test('verification timestamp formatter has one unambiguous meaning', () {
    final now = DateTime.utc(2026, 10, 2, 14);
    final fourteenHoursAgo = now.subtract(const Duration(hours: 14));

    expect(
      connectionVerificationLabel(
        state: ConnectionCardState.verified,
        checkedAt: null,
        now: now,
      ),
      'Never verified',
    );
    expect(
      connectionVerificationLabel(
        state: ConnectionCardState.verified,
        checkedAt: fourteenHoursAgo,
        now: now,
      ),
      'Verified 14h ago',
    );
    expect(
      connectionVerificationLabel(
        state: ConnectionCardState.error,
        checkedAt: fourteenHoursAgo,
        now: now,
      ),
      'Last check failed 14h ago',
    );
  });

  test('generated GitHub account identifiers are not primary copy', () {
    const raw = 'GitHub Account — pandora-rvw-314296438-20260820';
    expect(connectionProviderDisplayName(raw), 'GitHub');
    expect(connectionDisplayIdentity('GitHub', raw), 'Pandora GitHub account');
    expect(connectionIdentityNeedsTooltip(raw), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';

void main() {
  test('assignment rejection permits a safe editable correction', () {
    final failure = PandoraCoreFailure.fromServer(
      '22023',
      'ASSIGNEE_NOT_AUTHORIZED: internal membership lookup details',
    );

    // The operation form unlocks fields for INVALID_REQUEST; treating this
    // known rejection as an unknown outcome would prevent reassignment.
    expect(failure.code, 'INVALID_REQUEST');
    expect(failure.message,
        'Choose an active client member or clear the assignment.');
    expect(failure.message, isNot(contains('internal membership')));
    expect(failure.requiresStepUp, isFalse);
  });
}

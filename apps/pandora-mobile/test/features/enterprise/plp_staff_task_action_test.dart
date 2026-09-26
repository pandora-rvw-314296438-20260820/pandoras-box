import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_staff_task_action.dart';

void main() {
  test('parses the governed Room 3 staff-task command', () {
    final command = PlpStaffTaskCommand.tryParse(
      'Create a staff task to inspect Room 3',
    );

    expect(command, isNotNull);
    expect(command!.bookingReference, 'Room 3');
    expect(command.title, 'Inspect Room 3');
    expect(command.category, 'housekeeping');
    expect(command.priority, 'normal');
    expect(command.note, contains('authenticated PLP Pandora mobile command'));
  });

  test('does not intercept ordinary Alfred conversation', () {
    expect(
      PlpStaffTaskCommand.tryParse("What's today's occupancy?"),
      isNull,
    );
  });

  test('provider result requires verified readback', () {
    expect(
      () => PlpStaffTaskActionResult.fromMap(<String, Object?>{
        'activityJobId': 'job',
        'taskId': 'task',
        'bookingReference': 'Room 3',
        'title': 'Inspect Room 3',
        'status': 'open',
        'verified': false,
        'providerReadbackVerified': false,
      }),
      throwsA(isA<PlpStaffTaskActionException>()),
    );
  });
}

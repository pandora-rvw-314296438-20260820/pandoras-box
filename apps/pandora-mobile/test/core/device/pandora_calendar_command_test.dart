import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_calendar_command.dart';

void main() {
  final now = DateTime(2026, 9, 16, 12);

  test('lunch context resolves bare 1 as 1 PM on next Friday', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Set lunch with Nocom Friday at 1',
      now: now,
    );
    expect(parsed, isNotNull);
    expect(parsed!.isReady, isTrue);
    final command = parsed.command!;
    expect(command.kind, PandoraCalendarCommandKind.create);
    expect(command.title, 'lunch with Nocom');
    expect(command.start, DateTime(2026, 9, 18, 13));
    expect(command.end, DateTime(2026, 9, 18, 14));
  });

  test('bare non-contextual time fails closed to AM or PM clarification', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Schedule meeting Friday at 1',
      now: now,
    );
    expect(parsed, isNotNull);
    expect(parsed!.isReady, isFalse);
    expect(parsed.clarification, contains('AM'));
    expect(parsed.clarification, contains('PM'));
  });

  test('reminder resolves tomorrow and explicit local time', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Remind me tomorrow at 9 am to call Nocom',
      now: now,
    );
    expect(parsed, isNotNull);
    final command = parsed!.command!;
    expect(command.kind, PandoraCalendarCommandKind.reminder);
    expect(command.start, DateTime(2026, 9, 17, 9));
    expect(command.title, 'call Nocom');
  });

  test('recurring weekly event emits bounded RRULE', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Schedule team sync every Monday at 9 am',
      now: now,
    );
    expect(parsed, isNotNull);
    final command = parsed!.command!;
    expect(command.kind, PandoraCalendarCommandKind.create);
    expect(command.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(command.start, DateTime(2026, 9, 21, 9));
  });

  test('move command preserves old time identity and resolves new time', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Move my 3 PM meeting to 4 PM today',
      now: now,
    );
    expect(parsed, isNotNull);
    final command = parsed!.command!;
    expect(command.kind, PandoraCalendarCommandKind.update);
    expect(command.oldMinuteOfDay, 15 * 60);
    expect(command.start, DateTime(2026, 9, 16, 16));
  });

  test('calendar query is bounded to requested day', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Show my calendar tomorrow',
      now: now,
    );
    expect(parsed, isNotNull);
    final command = parsed!.command!;
    expect(command.kind, PandoraCalendarCommandKind.query);
    expect(command.rangeStart, DateTime(2026, 9, 17));
    expect(command.rangeEnd, DateTime(2026, 9, 18));
  });

  test('cancel requires a bounded target and date window', () {
    final parsed = PandoraCalendarCommand.tryParse(
      'Cancel dentist event tomorrow',
      now: now,
    );
    expect(parsed, isNotNull);
    final command = parsed!.command!;
    expect(command.kind, PandoraCalendarCommandKind.delete);
    expect(command.title, 'dentist');
    expect(command.rangeStart, DateTime(2026, 9, 17));
  });
}

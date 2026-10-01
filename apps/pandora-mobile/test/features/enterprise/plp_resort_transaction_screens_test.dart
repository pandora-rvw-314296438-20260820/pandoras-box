import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_operational_screens.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_transaction_action.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_transaction_screens.dart';

class _FakeTransactionAction extends PlpResortTransactionAction {
  _FakeTransactionAction();

  String? lastAction;
  Map<String, Object?>? lastPayload;

  @override
  Future<PlpResortTransactionResult> execute({
    required String requestId,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    lastAction = action;
    lastPayload = payload;
    return PlpResortTransactionResult(
      requestId: requestId,
      action: action,
      entityKind: 'booking',
      entityId: 'booking-1',
      verified: true,
      providerReadbackVerified: true,
      idempotentReplay: false,
      readback: const <String, Object?>{'status': 'CHECKED_IN'},
    );
  }
}

const _bootstrap = <String, Object?>{
  'user': <String, Object?>{'role': 'operator'},
  'resortCommandCenter': <String, Object?>{
    'rooms': <Object?>[
      <String, Object?>{
        'id': 'room-1',
        'name': 'Sunset Suite',
        'capacity': 4,
        'bedrooms': 2,
        'nightlyRatePhp': 18000,
        'state': 'available',
      },
    ],
  },
};

const _stay = <String, Object?>{
  'id': 'booking-1',
  'bookingReference': 'PLP-1001',
  'fullName': 'Maria Santos',
  'accommodationName': 'Sunset Suite',
  'checkIn': '2026-10-01',
  'checkOut': '2026-10-03',
  'guestCount': 2,
  'nights': 2,
  'status': 'CONFIRMED',
  'paymentStatus': 'PENDING',
  'totalAmountPhp': 36000,
  'balanceAmountPhp': 36000,
};

void main() {
  testWidgets('operator stay record exposes normal lifecycle actions', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortRecordScreen(
          kind: 'stay',
          record: _stay,
          role: 'operator',
          onBack: () {},
          onAction: opened.add,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-record-action-edit_booking')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-record-action-check_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-record-action-update_guest')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-record-action-manual_payment')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-record-action-cancel_booking')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-record-action-check_in')));
    await tester.pump();
    expect(opened, contains('check_in'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer resort record is read-only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortRecordScreen(
          kind: 'stay',
          record: _stay,
          role: 'viewer',
          onBack: () {},
          onAction: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-record-action-check_in')), findsNothing);
    expect(find.byKey(const ValueKey('plp-record-action-edit_booking')), findsNothing);
    expect(find.text('ACTIONS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room rate is owner/admin only while operational state allows operator', (tester) async {
    const room = <String, Object?>{
      'id': 'room-1',
      'name': 'Sunset Suite',
      'state': 'available',
      'capacity': 4,
      'bedrooms': 2,
      'nightlyRatePhp': 18000,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortRecordScreen(
          kind: 'room',
          record: room,
          role: 'operator',
          onBack: () {},
          onAction: (_) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('plp-record-action-room_state')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-record-action-room_rate')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortRecordScreen(
          kind: 'room',
          record: room,
          role: 'admin',
          onBack: () {},
          onAction: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('plp-record-action-room_rate')), findsOneWidget);
  });

  testWidgets('check-in mutation page calls provider action and returns after verified result', (tester) async {
    final fake = _FakeTransactionAction();
    var changed = false;
    var backed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortMutationScreen(
          actionId: 'check_in',
          record: _stay,
          bootstrap: _bootstrap,
          action: fake,
          onChanged: () => changed = true,
          onBack: () => backed = true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('plp-mutation-submit-check_in')),
    );
    await tester.pumpAndSettle();

    expect(fake.lastAction, 'check_in');
    expect(fake.lastPayload?['bookingReference'], 'PLP-1001');
    expect(changed, isTrue);
    expect(backed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new reservation is a real form with room and date controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlpReservationCreateScreen(
          bootstrap: _bootstrap,
          onBack: () {},
          onChanged: () {},
          action: _FakeTransactionAction(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-new-reservation')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-check-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-check-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-reservation-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

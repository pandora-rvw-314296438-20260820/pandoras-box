import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/plp_resort_lifecycle_api.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_lifecycle_screens.dart';

class FakeLifecycleGateway implements PlpResortLifecycleGateway {
  Map<String, Object?> detail = <String, Object?>{
    'bookingReference': 'PLP-QA-1',
    'fullName': 'Maria Santos',
    'email': 'maria@example.com',
    'phone': '+639000000000',
    'accommodationId': 'room-1',
    'accommodationName': 'Sunset Suite',
    'checkIn': '2030-01-10',
    'checkOut': '2030-01-12',
    'guestCount': 2,
    'status': 'CONFIRMED',
    'paymentStatus': 'PENDING',
    'totalAmountPhp': 36000,
    'balanceAmountPhp': 36000,
    'specialRequests': 'Anniversary dinner',
  };

  String? lastAction;
  Map<String, Object?>? lastPatch;
  String? createdGuestName;

  Map<String, Object?> _ok(String action) => <String, Object?>{
        'verified': true,
        'providerReadbackVerified': true,
        'action': action,
      };

  @override
  Future<Map<String, Object?>> reservationDetail(String bookingReference) async =>
      Map<String, Object?>.from(detail);

  @override
  Future<Map<String, Object?>> createReservation({
    required String requestId,
    required String guestName,
    required String guestEmail,
    String? guestPhone,
    required String accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    String? specialRequests,
  }) async {
    createdGuestName = guestName;
    return <String, Object?>{
      ..._ok('create_reservation'),
      'bookingReference': 'PLP-CREATED',
    };
  }

  @override
  Future<Map<String, Object?>> updateReservation({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  }) async {
    lastAction = 'update_reservation';
    lastPatch = patch;
    return _ok(lastAction!);
  }

  @override
  Future<Map<String, Object?>> transitionReservation({
    required String requestId,
    required String bookingReference,
    required String action,
  }) async {
    lastAction = action;
    detail = <String, Object?>{
      ...detail,
      'status': action == 'check_in'
          ? 'CHECKED_IN'
          : action == 'check_out'
              ? 'CHECKED_OUT'
              : 'CANCELLED',
    };
    return <String, Object?>{
      ..._ok(action),
      'status': detail['status'],
    };
  }

  @override
  Future<Map<String, Object?>> updateGuest({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  }) async {
    lastAction = 'update_guest';
    lastPatch = patch;
    return _ok(lastAction!);
  }

  @override
  Future<Map<String, Object?>> recordPayment({
    required String requestId,
    required String bookingReference,
    required num amountPhp,
    required String method,
    String? reference,
  }) async {
    lastAction = 'record_payment';
    return <String, Object?>{
      ..._ok(lastAction!),
      'balanceAmountPhp': 0,
      'paymentStatus': 'PAID',
    };
  }

  @override
  Future<Map<String, Object?>> updateRoom({
    required String requestId,
    required String accommodationId,
    required Map<String, Object?> patch,
  }) async {
    lastAction = 'update_room';
    lastPatch = patch;
    return <String, Object?>{
      ..._ok(lastAction!),
      'nightlyRatePhp': patch['nightlyRatePhp'],
      'capacity': patch['capacity'],
      'bedrooms': patch['bedrooms'],
      'isActive': patch['isActive'],
    };
  }
}

void main() {
  const bootstrap = <String, Object?>{
    'resortCommandCenter': <String, Object?>{
      'rooms': <Object?>[
        <String, Object?>{
          'id': 'room-1',
          'name': 'Sunset Suite',
          'nightlyRatePhp': 18000,
          'capacity': 4,
          'bedrooms': 2,
          'state': 'available',
          'isActive': true,
        },
      ],
    },
  };

  testWidgets('new reservation is a normal form backed by the lifecycle gateway',
      (tester) async {
    final gateway = FakeLifecycleGateway();
    Map<String, Object?>? changed;
    var backed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PlpReservationCreateScreen(
          bootstrap: bootstrap,
          gateway: gateway,
          initialCheckIn: DateTime(2030, 1, 10),
          initialCheckOut: DateTime(2030, 1, 12),
          onBack: () => backed = true,
          onChanged: (result) => changed = result,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('plp-reservation-guest-name')),
      'Acceptance Guest',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plp-reservation-guest-email')),
      'acceptance@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plp-reservation-guest-count')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('plp-reservation-submit')));
    await tester.pumpAndSettle();

    expect(gateway.createdGuestName, 'Acceptance Guest');
    expect(changed?['providerReadbackVerified'], true);
    expect(backed, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner stay detail exposes normal lifecycle actions', (tester) async {
    final gateway = FakeLifecycleGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: PlpStayLifecycleScreen(
          record: const <String, Object?>{
            'bookingReference': 'PLP-QA-1',
            'fullName': 'Maria Santos',
          },
          role: 'owner',
          gateway: gateway,
          onBack: () {},
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-stay-lifecycle')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-stay-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-guest-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-payment-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-stay-check-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-stay-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-stay-check-in')));
    await tester.pumpAndSettle();
    expect(gateway.lastAction, 'check_in');
    expect(find.byKey(const ValueKey('plp-stay-check-out')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer stay detail is read-only', (tester) async {
    final gateway = FakeLifecycleGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: PlpStayLifecycleScreen(
          record: const <String, Object?>{
            'bookingReference': 'PLP-QA-1',
            'fullName': 'Maria Santos',
          },
          role: 'viewer',
          gateway: gateway,
          onBack: () {},
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-stay-edit')), findsNothing);
    expect(find.byKey(const ValueKey('plp-stay-check-in')), findsNothing);
    expect(find.textContaining('read access'), findsOneWidget);
  });

  testWidgets('only owner/admin can edit room configuration', (tester) async {
    final gateway = FakeLifecycleGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: PlpRoomLifecycleScreen(
          room: const <String, Object?>{
            'id': 'room-1',
            'name': 'Sunset Suite',
            'nightlyRatePhp': 18000,
            'capacity': 4,
            'bedrooms': 2,
            'state': 'available',
            'isActive': true,
          },
          role: 'operator',
          gateway: gateway,
          onBack: () {},
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-room-edit')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: PlpRoomLifecycleScreen(
          room: const <String, Object?>{
            'id': 'room-1',
            'name': 'Sunset Suite',
            'nightlyRatePhp': 18000,
            'capacity': 4,
            'bedrooms': 2,
            'state': 'available',
            'isActive': true,
          },
          role: 'admin',
          gateway: gateway,
          onBack: () {},
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-room-edit')), findsOneWidget);
  });
}

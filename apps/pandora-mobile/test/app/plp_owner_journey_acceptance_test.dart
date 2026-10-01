import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_operational_screens.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

const _bootstrap = <String, Object?>{
  'generatedAt': '2026-10-01T00:00:00Z',
  'organization': <String, Object?>{
    'propertyName': 'Pueblo La Perla',
    'propertySlug': 'plp-boracay',
  },
  'user': <String, Object?>{'displayName': 'Owner QA'},
  'sourceHealth': <String, Object?>{
    'state': 'healthy',
    'message': 'Verified fixture',
  },
  'today': <String, Object?>{
    'occupancy_percent': 66.67,
    'occupied_rooms': 2,
    'rooms_total': 3,
    'rooms_available': 1,
    'arrivals_today': 1,
    'departures_today': 1,
    'sales_today_php': 300000,
    'open_staff_tasks': 3,
    'open_ota_conflicts': 1,
  },
  'guestExperience': <String, Object?>{
    'inHouse': <Object?>[
      <String, Object?>{
        'fullName': 'Maria Santos',
        'accommodationName': 'Sunset Suite',
      },
    ],
    'arrivals': <Object?>[
      <String, Object?>{'fullName': 'Arrival Guest'},
    ],
    'departing': <Object?>[
      <String, Object?>{'fullName': 'Departure Guest'},
    ],
    'attention': <Object?>[
      <String, Object?>{
        'id': 'task-attention',
        'title': 'Prepare VIP arrival',
        'priority': 'high',
        'status': 'open',
        'category': 'concierge',
        'fullName': 'Maria Santos',
      },
    ],
  },
  'resortCommandCenter': <String, Object?>{
    'roomPulse': <String, Object?>{
      'total': 3,
      'occupied': 2,
      'available': 1,
      'arriving': 1,
      'departing': 1,
    },
    'operations': <String, Object?>{
      'openWork': 3,
      'priorityWork': 1,
      'channelExceptions': 1,
    },
    'finance': <String, Object?>{
      'bookedValue30dPhp': 500000,
      'outstandingBalancePhp': 100000,
      'paidValue30dPhp': 400000,
    },
    'rooms': <Object?>[
      <String, Object?>{
        'id': 'room-sunset',
        'name': 'Sunset Suite',
        'state': 'departure',
        'capacity': 4,
        'bedrooms': 2,
        'nightlyRatePhp': 18000,
      },
      <String, Object?>{
        'id': 'room-garden',
        'name': 'Garden Villa',
        'state': 'available',
        'capacity': 2,
        'bedrooms': 1,
        'nightlyRatePhp': 12000,
      },
    ],
    'stays': <Object?>[
      <String, Object?>{
        'id': 'stay-maria',
        'bookingReference': 'PLP-1001',
        'fullName': 'Maria Santos',
        'accommodationName': 'Sunset Suite',
        'checkIn': '2026-10-01',
        'checkOut': '2026-10-03',
        'guestCount': 2,
        'nights': 2,
        'status': 'confirmed',
        'paymentStatus': 'paid',
        'totalAmountPhp': 36000,
        'balanceAmountPhp': 0,
        'hasSpecialRequest': true,
        'specialRequest': 'Anniversary setup',
      },
    ],
    'experienceSignals': <Object?>[
      <String, Object?>{
        'bookingReference': 'PLP-1001',
        'fullName': 'Maria Santos',
        'accommodationName': 'Sunset Suite',
        'checkIn': '2026-10-01',
        'checkOut': '2026-10-03',
        'request': 'Anniversary dinner and airport transfer',
      },
    ],
  },
  'resortOperations': <String, Object?>{
    'workItems': <Object?>[
      <String, Object?>{
        'id': 'task-housekeeping',
        'bookingReference': 'PLP-1001',
        'kind': 'task',
        'category': 'housekeeping',
        'priority': 'medium',
        'status': 'in_progress',
        'title': 'Prepare Sunset Suite',
        'note': 'Turnover before arrival.',
        'actor': 'Housekeeping',
        'isTestData': false,
      },
      <String, Object?>{
        'id': 'task-maintenance',
        'bookingReference': 'Sunset Suite',
        'kind': 'task',
        'category': 'maintenance',
        'priority': 'normal',
        'status': 'open',
        'title': 'Inspect balcony light',
        'note': 'Guest reported intermittent light.',
        'actor': 'Engineering',
        'isTestData': false,
      },
      <String, Object?>{
        'id': 'task-transfer',
        'bookingReference': 'PLP-1001',
        'kind': 'task',
        'category': 'arrival',
        'priority': 'high',
        'status': 'open',
        'title': 'Confirm airport transfer',
        'note': 'Pickup confirmation required.',
        'actor': 'Concierge',
        'isTestData': false,
      },
      <String, Object?>{
        'id': 'task-complete',
        'bookingReference': 'PLP-0999',
        'kind': 'task',
        'category': 'housekeeping',
        'priority': 'normal',
        'status': 'done',
        'title': 'Completed checkout inspection',
        'note': 'Completed.',
        'actor': 'Housekeeping',
        'isTestData': false,
      },
    ],
    'channelConflicts': <Object?>[
      <String, Object?>{
        'id': 'conflict-1',
        'channelKey': 'booking.com',
        'conflictType': 'date_overlap',
        'accommodationName': 'Sunset Suite',
        'startDate': '2026-10-01',
        'endDate': '2026-10-03',
        'severity': 'high',
        'status': 'open',
        'isTestData': false,
      },
    ],
  },
  'teamAccess': <String, Object?>{
    'activeMemberCount': 2,
    'staffIdentityCount': 2,
    'members': <Object?>[
      <String, Object?>{
        'id': 'member-owner',
        'displayName': 'Doctora',
        'roleLabel': 'Owner',
        'accessRole': 'owner',
        'active': true,
      },
      <String, Object?>{
        'id': 'member-manager',
        'displayName': 'Resort Manager',
        'roleLabel': 'Manager',
        'accessRole': 'admin',
        'active': true,
      },
    ],
    'recentActivity': <Object?>[],
  },
};

Future<void> _mountOwnerShell(WidgetTester tester) async {
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  await tester.pumpWidget(
    PandoraDependencies(
      auth: const FakeAuth(),
      repository: FakeRepository(),
      diagnostics: DiagnosticsStore(),
      child: testApp(
        child: const PlpEnterpriseShell(bootstrapOverride: _bootstrap),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openDrawer(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('plp-floating-navigation'));
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).last);
  expect(
    scaffold.isDrawerOpen,
    isTrue,
    reason: 'The fixed hamburger must open the actual PLP drawer.',
  );
  final drawer = find.byKey(const ValueKey('plp-navigation-drawer'));
  expect(drawer, findsOneWidget);
  expect(tester.getRect(drawer).left, greaterThanOrEqualTo(-1));
}

Future<void> _openSection(WidgetTester tester, String id) async {
  await _openDrawer(tester);
  final destination = find.byKey(ValueKey<String>('plp-drawer-' + id));
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 420));
  final expected = id == 'home' ? 'today' : id;
  expect(
    find.byKey(ValueKey<String>('plp-resort-' + expected)),
    findsOneWidget,
  );
}

Future<void> _tapVisibleText(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner can traverse every primary resort workspace from fixed navigation', (tester) async {
    await _mountOwnerShell(tester);

    expect(find.byKey(const ValueKey('plp-resort-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-command-dock')), findsOneWidget);

    final menu = find.byKey(const ValueKey('plp-floating-navigation'));
    final anchored = tester.getTopLeft(menu);
    await tester.drag(
      find.byKey(const ValueKey('plp-resort-today')),
      const Offset(0, -520),
    );
    await tester.pump();
    expect(tester.getTopLeft(menu), anchored);

    for (final id in const [
      'home',
      'stays',
      'rooms',
      'guests',
      'operations',
      'revenue',
      'experiences',
      'team',
      'activity',
    ]) {
      await _openSection(tester, id);
      expect(find.byKey(const ValueKey('plp-command-dock')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Rooms drill-down and both UI and Android back return to Rooms', (tester) async {
    await _mountOwnerShell(tester);
    await _openSection(tester, 'rooms');

    await _tapVisibleText(tester, 'Housekeeping');
    expect(
      find.byKey(const ValueKey('plp-module-housekeeping')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plp-command-dock')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-module-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-resort-rooms')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-resort-today')), findsNothing);

    await _tapVisibleText(tester, 'Sunset Suite');
    expect(find.byKey(const ValueKey('plp-record-room')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-resort-rooms')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stays record drill-down returns to the stay list', (tester) async {
    await _mountOwnerShell(tester);
    await _openSection(tester, 'stays');

    await _tapVisibleText(tester, 'Maria Santos');
    expect(find.byKey(const ValueKey('plp-record-stay')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-module-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-resort-stays')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every resort capability opens a real module and Back restores its parent', (tester) async {
    await _mountOwnerShell(tester);

    const matrix = <String, Map<String, String>>{
      'guests': <String, String>{
        'Concierge': 'concierge',
        'VIP': 'vip',
        'Transfers': 'transfers',
      },
      'operations': <String, String>{
        'Property': 'property',
        'Security': 'security',
        'Transport': 'transport',
      },
      'revenue': <String, String>{
        'Rates': 'rates',
        'Channels': 'channels',
        'Forecast': 'forecast',
      },
      'experiences': <String, String>{
        'Concierge': 'concierge',
        'Transfers': 'transfers',
        'Dining': 'dining',
        'Wellness': 'wellness',
        'Activities': 'activities',
        'Events': 'events',
      },
    };

    for (final section in matrix.entries) {
      for (final module in section.value.entries) {
        await _openSection(tester, section.key);
        await _tapVisibleText(tester, module.key);
        expect(
          find.byKey(ValueKey<String>('plp-module-' + module.value)),
          findsOneWidget,
          reason: module.key + ' must open a normal operational page.',
        );
        expect(find.byKey(const ValueKey('plp-command-dock')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('plp-module-back')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey<String>('plp-resort-' + section.key)),
          findsOneWidget,
          reason: 'Back from ' + module.key + ' must restore ' + section.key,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('housekeeping supports normal search, history and New task UI without chat', (tester) async {
    await _mountOwnerShell(tester);
    await _openSection(tester, 'rooms');
    await _tapVisibleText(tester, 'Housekeeping');

    expect(find.text('Prepare Sunset Suite'), findsOneWidget);
    expect(find.text('Completed checkout inspection'), findsNothing);

    await tester.tap(find.text('Show completed'));
    await tester.pump();
    expect(find.text('Completed checkout inspection'), findsOneWidget);

    final search = find.byKey(const ValueKey('plp-module-search'));
    await tester.enterText(search, 'Prepare');
    await tester.pump();
    expect(find.text('Prepare Sunset Suite'), findsOneWidget);
    expect(find.text('Completed checkout inspection'), findsNothing);

    await tester.enterText(search, 'does-not-exist');
    await tester.pump();
    expect(
      find.text('No connected housekeeping work is waiting.'),
      findsOneWidget,
    );

    await tester.enterText(search, '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plp-module-new-task')));
    await tester.pumpAndSettle();
    expect(find.text('New housekeeping task'), findsOneWidget);
    final taskTitle = find.descendant(
      of: find.byKey(const ValueKey('plp-module-task-title')).first,
      matching: find.byType(TextField),
    );
    expect(taskTitle, findsOneWidget);
    expect(find.text('Create task'), findsOneWidget);

    await tester.enterText(
      taskTitle,
      'Inspect room before arrival',
    );
    expect(find.text('Inspect room before arrival'), findsOneWidget);

    // Android may consume the first Back to dismiss the keyboard. Whether
    // one or two Back presses are required, neither may escape Housekeeping.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('plp-module-housekeeping')),
      findsOneWidget,
    );
    if (find.text('New housekeeping task').evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(find.text('New housekeeping task'), findsNothing);
    expect(
      find.byKey(const ValueKey('plp-module-housekeeping')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('operational controls remain usable at 320px phone width', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(320, 700));
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortOperationalScreen(
          moduleId: 'housekeeping',
          bootstrap: _bootstrap,
          onBack: () {},
          onRefresh: () {},
          onOpenRecord: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('plp-module-search')), findsOneWidget);
    expect(find.text('Show completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-module-new-task')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer search reaches System without removing the persistent command layer', (tester) async {
    await _mountOwnerShell(tester);
    await _openDrawer(tester);

    await tester.tap(find.byKey(const ValueKey('plp-drawer-search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('plp-drawer-search-field')),
      'Developer',
    );
    await tester.pump();
    expect(find.text('Developer diagnostics'), findsOneWidget);

    await tester.tap(find.text('Developer diagnostics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    expect(find.byKey(const ValueKey('plp-developer')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-command-dock')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

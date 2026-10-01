import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_editorial_surfaces.dart';

void main() {
  Map<String, Object?> fixture({
    int arrivals = 0,
    int departures = 0,
    int tasks = 0,
    int conflicts = 0,
  }) =>
      <String, Object?>{
        'today': <String, Object?>{
          'occupancy_percent': 50,
          'occupied_rooms': 2,
          'rooms_total': 4,
          'rooms_available': 2,
          'arrivals_today': arrivals,
          'departures_today': departures,
          'sales_today_php': 125000,
          'open_staff_tasks': tasks,
          'open_ota_conflicts': conflicts,
        },
        'sourceHealth': <String, Object?>{
          'state': 'healthy',
          'message': 'Provider snapshot verified',
        },
      };

  testWidgets('Overview remains the stable operating reference', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PlpOverviewScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The resort, in one quiet view.'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('₱125,000'), findsOneWidget);
    expect(find.text('Turn the overview into action.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Operations collapses zero guest movement', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PlpOperationsScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
          onOpenInfrastructure: () {},
          onOpenRoom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No guest movement today.'), findsOneWidget);
    expect(find.text('Arrival readiness'), findsNothing);
    expect(find.text('Departure readiness'), findsNothing);

    final infrastructure =
        find.byKey(const ValueKey('plp-operations-infrastructure'));
    await tester.scrollUntilVisible(
      infrastructure,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(infrastructure, findsOneWidget);
    expect(find.text('Resort infrastructure'), findsOneWidget);
    expect(
      find.text('Pandora has not verified the resort’s network resilience yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

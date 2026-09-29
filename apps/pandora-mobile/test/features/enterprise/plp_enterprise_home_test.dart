import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_enterprise_home.dart';

void main() {
  Map<String, Object?> fixture({
    int arrivals = 1,
    int departures = 1,
    int tasks = 2,
    int conflicts = 1,
  }) =>
      <String, Object?>{
        'organization': <String, Object?>{
          'propertyName': 'PLP Boracay',
          'businessIdentity': 'Luxury Resort',
        },
        'user': <String, Object?>{'displayName': 'Doctora'},
        'today': <String, Object?>{
          'occupancy_percent': 66.67,
          'occupied_rooms': 2,
          'rooms_total': 3,
          'rooms_available': 1,
          'arrivals_today': arrivals,
          'departures_today': departures,
          'sales_today_php': 300000,
          'open_staff_tasks': tasks,
          'open_ota_conflicts': conflicts,
        },
        'sourceHealth': <String, Object?>{
          'state': 'healthy',
          'message': 'Provider snapshot verified',
        },
      };

  Widget mount(Map<String, Object?> bootstrap) => MaterialApp(
        home: Scaffold(
          body: PlpEnterpriseHome(
            bootstrap: bootstrap,
            onRefresh: () {},
            onAskAlfred: () {},
          ),
        ),
      );

  testWidgets('Home is an adaptive owner briefing instead of a duplicate Overview',
      (tester) async {
    await tester.pumpWidget(mount(fixture()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-enterprise-home')), findsOneWidget);
    expect(find.text('OWNER’S HOME'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Welcome, Doctora'), findsOneWidget);
    expect(find.text('A few things need you.'), findsOneWidget);
    expect(
      find.text('66.67% occupancy · 1 room available · ₱300,000 today'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('1 OTA conflict'),
      240,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('1 OTA conflict'), findsOneWidget);
    expect(find.text('2 open staff tasks'), findsOneWidget);
    expect(find.text('MOVEMENT TODAY'), findsOneWidget);

    expect(find.text('TODAY AT PUEBLO LA PERLA'), findsNothing);
    expect(find.text('COMMAND PLP'), findsNothing);
    expect(find.byKey(const ValueKey('plp-metric-sales')), findsNothing);
    expect(find.byKey(const ValueKey('plp-open-alfred')), findsNothing);
    expect(find.byKey(const ValueKey('plp-open-operations-room')), findsNothing);
    expect(find.byKey(const ValueKey('plp-open-vision')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home collapses quiet zero states', (tester) async {
    await tester.pumpWidget(
      mount(
        fixture(
          arrivals: 0,
          departures: 0,
          tasks: 0,
          conflicts: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The resort is quiet today.'), findsOneWidget);
    expect(find.text('No arrivals or departures are scheduled.'), findsOneWidget);
    expect(find.text('MOVEMENT TODAY'), findsNothing);
    expect(find.text('NEEDS YOUR ATTENTION'), findsNothing);
    expect(find.byKey(const ValueKey('plp-source-health')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_enterprise_home.dart';

void main() {
  testWidgets('renders authenticated PLP command-center projection', (tester) async {
    final bootstrap = <String, Object?>{
      'organization': <String, Object?>{
        'propertyName': 'PLP Boracay',
        'businessIdentity': 'Luxury Resort',
      },
      'user': <String, Object?>{
        'displayName': 'Doctora',
      },
      'today': <String, Object?>{
        'occupancy_percent': 66.67,
        'occupied_rooms': 2,
        'rooms_total': 3,
        'rooms_available': 1,
        'arrivals_today': 1,
        'departures_today': 1,
        'sales_today_php': 300000,
        'open_staff_tasks': 2,
        'open_ota_conflicts': 1,
      },
      'sourceHealth': <String, Object?>{
        'state': 'healthy',
        'message': 'Provider snapshot verified',
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlpEnterpriseHome(
            bootstrap: bootstrap,
            onRefresh: () {},
            onAskAlfred: () {},
            onOperations: () {},
            onVision: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-enterprise-home')), findsOneWidget);
    expect(find.text('Welcome, Doctora'), findsOneWidget);
    expect(find.text('66.67%'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plp-metric-sales')),
      320,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('₱300,000'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('1'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plp-open-alfred')),
      320,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byKey(const ValueKey('plp-open-alfred')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-open-operations-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-open-vision')), findsOneWidget);
  });
}

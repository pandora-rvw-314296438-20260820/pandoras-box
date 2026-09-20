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
            onBookings: () {},
            onBusinessPerformance: () {},
            onGuestExperience: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-enterprise-home')), findsOneWidget);
    expect(find.text('PLP Boracay'), findsOneWidget);
    expect(find.text('What can I help with?'), findsOneWidget);
    expect(find.textContaining('Doctora'), findsOneWidget);

    expect(find.byKey(const ValueKey('plp-release-background')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-release-logo')), findsOneWidget);

    expect(
      find.byKey(const ValueKey('plp-home-bookings')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey('plp-home-business-performance')),
      findsOneWidget,
    );

    expect(find.text('Ask Pandora'), findsOneWidget);
    expect(find.text('Sales, occupancy & priorities'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-open-alfred')), findsOneWidget);
  });
}

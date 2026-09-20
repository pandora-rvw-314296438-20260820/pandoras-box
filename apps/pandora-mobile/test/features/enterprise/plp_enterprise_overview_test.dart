import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_enterprise_overview.dart';

void main() {
  testWidgets('renders PLP light owner overview from verified bootstrap data', (tester) async {
    final bootstrap = <String, Object?>{
      'generatedAt': '2026-09-20T10:24:00Z',
      'organization': <String, Object?>{
        'propertyName': 'PLP Boracay',
        'businessIdentity': 'Luxury Resort',
      },
      'user': <String, Object?>{'displayName': 'Doctora'},
      'today': <String, Object?>{
        'occupancy_percent': 66.67,
        'occupied_rooms': 30,
        'rooms_total': 45,
        'rooms_available': 15,
        'arrivals_today': 12,
        'departures_today': 9,
        'sales_today_php': 482650,
        'open_staff_tasks': 2,
        'open_ota_conflicts': 1,
        'unpaid_active_bookings': 3,
        'generated_at': '2026-09-20T10:22:00Z',
      },
      'latestHospitalitySnapshot': <String, Object?>{
        'rooms_not_ready': 1,
      },
      'sourceHealth': <String, Object?>{
        'state': 'healthy',
        'observedAt': '2026-09-20T10:22:00Z',
        'message': 'Provider snapshot verified',
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: PlpEnterpriseOverview(
          bootstrap: bootstrap,
          onOpenNavigation: () {},
          onSearch: () {},
          onOpenOccupancy: () {},
          onOpenRooms: () {},
          onOpenTasks: () {},
          onOpenRevenue: () {},
          onOpenBookings: () {},
          onOpenNeedsAttention: () {},
          onOperations: () {},
          onGuestRequests: () {},
          onTeamTasks: () {},
          onReports: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plp-enterprise-overview-light')), findsOneWidget);
    expect(find.text('PLP Boracay'), findsOneWidget);
    expect(find.textContaining(', Doctora'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-overview-occupancy')), findsOneWidget);
    expect(find.text('66.67%'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-overview-revenue')), findsOneWidget);
    expect(find.text('₱482,650'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Needs attention'),
      360,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('1 OTA conflict'), findsOneWidget);
    expect(find.text('2 open staff tasks'), findsOneWidget);
    expect(find.text('3 unpaid active bookings'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Quick actions'),
      420,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Operations Room'), findsOneWidget);
    expect(find.text('Guest Requests'), findsOneWidget);
    expect(find.text('Team Tasks'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-overview-pandora-insight')), findsOneWidget);
  });
}

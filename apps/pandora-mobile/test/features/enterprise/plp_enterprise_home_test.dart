import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_enterprise_home.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_workspace.dart';

void main() {
  Map<String, Object?> fixture({
    int arrivals = 1,
    int departures = 1,
    int tasks = 2,
    int conflicts = 1,
  }) =>
      <String, Object?>{
        'organization': const <String, Object?>{
          'propertyName': 'Pueblo La Perla',
          'businessIdentity': 'Luxury Resort',
        },
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
        'sourceHealth': const <String, Object?>{
          'state': 'healthy',
          'message': 'Provider snapshot verified',
        },
        'guestExperience': <String, Object?>{
          'inHouse': const <Object?>[
            <String, Object?>{
              'fullName': 'Maria Santos',
              'accommodationName': 'Villa 1',
            },
          ],
          'arrivals': List<Object?>.generate(
            arrivals,
            (i) => <String, Object?>{'fullName': 'Arrival ' + i.toString()},
          ),
          'departing': List<Object?>.generate(
            departures,
            (i) => <String, Object?>{'fullName': 'Departure ' + i.toString()},
          ),
          'attention': tasks == 0
              ? const <Object?>[]
              : const <Object?>[
                  <String, Object?>{
                    'title': 'Prepare VIP arrival',
                    'priority': 'high',
                    'fullName': 'Maria Santos',
                  },
                ],
        },
        'resortCommandCenter': <String, Object?>{
          'roomPulse': <String, Object?>{
            'total': 3,
            'occupied': 2,
            'available': 1,
            'arriving': arrivals,
            'departing': departures,
          },
          'operations': <String, Object?>{
            'openWork': tasks,
            'priorityWork': tasks > 0 ? 1 : 0,
            'channelExceptions': conflicts,
          },
          'finance': const <String, Object?>{
            'bookedValue30dPhp': 500000,
            'outstandingBalancePhp': 100000,
            'paidValue30dPhp': 400000,
          },
          'rooms': const <Object?>[
            <String, Object?>{
              'name': 'Villa 1',
              'state': 'occupied',
              'capacity': 2,
              'bedrooms': 1,
            },
            <String, Object?>{
              'name': 'Villa 2',
              'state': 'available',
              'capacity': 2,
              'bedrooms': 1,
            },
          ],
          'stays': const <Object?>[],
          'experienceSignals': const <Object?>[],
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

  testWidgets(
    'Home is a visual resort command center instead of an editorial briefing',
    (tester) async {
      await tester.pumpWidget(mount(fixture()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('plp-enterprise-home')),
        findsOneWidget,
      );
      expect(find.text('RESORT STATUS'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plp-metric-rail')),
        findsOneWidget,
      );
      expect(find.text('ARRIVALS'), findsNWidgets(2));
      expect(find.text('DEPARTURES'), findsOneWidget);
      expect(find.text('ROOM PULSE'), findsOneWidget);
      expect(find.text('OWNER’S HOME'), findsNothing);
      expect(
        find.text('Your private briefing for what matters now.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home keeps quiet states compact', (tester) async {
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

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('The resort is composed.'), findsNothing);
    expect(
      find.text('No guest or channel exception needs owner attention.'),
      findsOneWidget,
    );
    expect(find.text('A few things need you.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operational rows open local details without redirecting into chat',
      (tester) async {
    var askCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortWorkspaceScreen(
          section: plpResortSectionById('today')!,
          bootstrap: fixture(),
          onOpenNavigation: () {},
          onRefresh: () {},
          onAskPandora: (_) => askCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Prepare VIP arrival'));
    await tester.tap(find.text('Prepare VIP arrival'));
    await tester.pumpAndSettle();

    expect(askCalls, 0);
    expect(find.text('Prepare VIP arrival'), findsWidgets);
    expect(find.text('PRIORITY'), findsOneWidget);
    expect(find.text('High'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity hides internal QA and staging copy and humanizes status',
      (tester) async {
    final data = fixture();
    data['sourceHealth'] = <String, Object?>{
      'state': 'stale',
      'message':
          'Demo/staging PLP data. Customer production tenant is not connected.',
    };
    data['teamAccess'] = <String, Object?>{
      'members': <Object?>[
        <String, Object?>{
          'displayName': 'MCPMaster Staging Owner',
          'roleLabel': 'Owner',
          'accessRole': 'owner',
          'active': true,
        },
        <String, Object?>{
          'displayName': 'Doctora',
          'roleLabel': 'Owner',
          'accessRole': 'owner',
          'active': true,
        },
      ],
      'recentActivity': <Object?>[
        <String, Object?>{
          'title': 'QA transfer',
          'actor': 'Alfred QA',
          'status': 'in_progress',
          'isMock': true,
        },
        <String, Object?>{
          'title': 'Confirm guest transfer',
          'actor': 'Front Desk',
          'status': 'in_progress',
          'category': 'arrival',
          'updatedAt': '2026-10-01T06:30:00+08:00',
        },
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortWorkspaceScreen(
          section: plpResortSectionById('activity')!,
          bootstrap: data,
          onOpenNavigation: () {},
          onRefresh: () {},
          onAskPandora: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo/staging'), findsNothing);
    expect(find.textContaining('Customer production tenant'), findsNothing);
    expect(find.textContaining('Alfred QA'), findsNothing);
    expect(find.textContaining('in_progress'), findsNothing);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.textContaining('In progress'), findsWidgets);
    expect(find.text('Confirm guest transfer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

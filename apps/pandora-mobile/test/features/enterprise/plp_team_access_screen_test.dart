import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_team_access_screen.dart';

void main() {
  Map<String, Object?> fixture() => <String, Object?>{
        'user': <String, Object?>{
          'displayName': 'PLP Owner',
        },
        'teamAccess': <String, Object?>{
          'activeMemberCount': 2,
          'currentUserRole': 'owner',
          'canManageTeam': true,
          'members': <Object?>[
            <String, Object?>{
              'id': 'owner-1',
              'displayName': 'PLP Owner',
              'roleLabel': 'Owner',
              'accessRole': 'owner',
              'accessStatus': 'active',
              'active': true,
              'source': 'membership',
              'isCurrentUser': true,
            },
            <String, Object?>{
              'id': 'admin-1',
              'displayName': 'Joven',
              'roleLabel': 'Administrator',
              'accessRole': 'admin',
              'accessStatus': 'active',
              'active': true,
              'source': 'membership',
              'isCurrentUser': false,
            },
          ],
          'recentActivity': <Object?>[
            <String, Object?>{
              'id': 'task-1',
              'title': 'Confirm airport transfer',
              'actor': 'Alfred QA',
              'category': 'arrival',
              'status': 'open',
              'isMock': true,
            },
          ],
        },
      };

  testWidgets('renders premium PLP people workspace at narrow phone width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PlpTeamAccessScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
          onAddPeople: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plp-team-access-light-page')),
      findsOneWidget,
    );
    expect(find.text('Our People'), findsOneWidget);
    expect(find.text('Team members'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey<String>('plp-team-access-light-page')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();

    expect(find.text('PLP Owner'), findsWidgets);
    expect(find.text('Joven'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('access and activity tabs expose synchronized projections',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PlpTeamAccessScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
          onAddPeople: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-team-tab-access')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Workspace access'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-team-tab-activity')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team activity'), findsOneWidget);
    expect(find.text('Confirm airport transfer'), findsOneWidget);
    expect(find.text('QA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

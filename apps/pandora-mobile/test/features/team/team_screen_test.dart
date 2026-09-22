import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_user_admin_api.dart';
import 'package:pandora_mobile/features/simple/more_screen.dart';
import 'package:pandora_mobile/features/team/team_screen.dart';

class _FakeGateway implements PandoraUserAdminGateway {
  final organizations = const <PandoraOrganizationAccess>[
    PandoraOrganizationAccess(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Banatao Systems',
      role: 'owner',
    ),
  ];

  var members = const <PandoraTeamMember>[
    PandoraTeamMember(
      id: '22222222-2222-4222-8222-222222222222',
      displayName: 'Mark Johnson',
      email: 'owner@example.com',
      role: 'owner',
      status: 'active',
      isCurrentUser: true,
    ),
    PandoraTeamMember(
      id: '44444444-4444-4444-8444-444444444444',
      displayName: 'Front Desk',
      email: 'frontdesk@example.com',
      role: 'operator',
      status: 'active',
    ),
  ];

  PandoraInviteRequest? lastInvite;
  PandoraMemberUpdateRequest? lastUpdate;

  @override
  Future<List<PandoraOrganizationAccess>> loadOrganizations() async =>
      organizations;

  @override
  Future<List<PandoraTeamMember>> loadMembers(String organizationId) async =>
      members;

  @override
  Future<PandoraInviteResult> inviteMember(
    String organizationId,
    PandoraInviteRequest request,
  ) async {
    lastInvite = request;
    members = <PandoraTeamMember>[
      ...members,
      PandoraTeamMember(
        id: '33333333-3333-4333-8333-333333333333',
        displayName: request.displayName,
        email: request.email,
        role: request.role,
        status: 'invited',
      ),
    ];
    return PandoraInviteResult(
      userId: '33333333-3333-4333-8333-333333333333',
      email: request.email,
      displayName: request.displayName,
      role: request.role,
      status: 'invited',
      inviteSent: true,
      existingAccount: false,
    );
  }
  @override
  Future<PandoraMemberUpdateResult> updateMember(
    String organizationId,
    PandoraMemberUpdateRequest request,
  ) async {
    lastUpdate = request;
    members = members
        .map(
          (member) => member.id != request.userId
              ? member
              : PandoraTeamMember(
                  id: member.id,
                  displayName: member.displayName,
                  email: member.email,
                  role: request.role ?? member.role,
                  status: request.status ?? member.status,
                  isCurrentUser: member.isCurrentUser,
                ),
        )
        .toList(growable: false);
    final changed = members.firstWhere((member) => member.id == request.userId);
    return PandoraMemberUpdateResult(
      userId: changed.id,
      role: changed.role,
      status: changed.status,
      changed: true,
    );
  }
}

void main() {
  testWidgets('owner can invite a person and refresh the team list',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: TeamScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Mark Johnson'), findsOneWidget);
    expect(find.text('Add person'), findsOneWidget);

    await tester.tap(find.text('Add person').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'new.person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name (optional)'),
      'New Person',
    );
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(gateway.lastInvite?.email, 'new.person@example.com');
    expect(find.text('New Person'), findsOneWidget);
    expect(find.text('Invited'), findsWidgets);
    expect(find.text('Invitation sent to new.person@example.com.'),
        findsOneWidget);
  });


  testWidgets('opens the invite flow immediately when launched for Add people',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamScreen(
          gateway: gateway,
          openInviteOnLoad: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Email address'),
      findsOneWidget,
    );
    expect(find.text('Send invitation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can change a member role and access status',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: TeamScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Front Desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front Desk'));
    await tester.pumpAndSettle();
    expect(find.text('Manage access'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('team-member-role')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewer').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('team-member-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspended').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('team-member-save')),
    );
    await tester.pumpAndSettle();

    expect(gateway.lastUpdate?.role, 'viewer');
    expect(gateway.lastUpdate?.status, 'suspended');
    expect(find.text('Viewer'), findsWidgets);
    expect(find.text('Suspended'), findsWidgets);
    expect(find.text('Front Desk access was updated.'), findsOneWidget);
  });

  testWidgets('More account navigation opens the real Team screen',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: MoreScreen(teamGateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team'), findsOneWidget);
    await tester.ensureVisible(find.text('Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    expect(
        find.text('Invite people and give each person the access they need.'),
        findsOneWidget);
    expect(find.text('Mark Johnson'), findsOneWidget);
  });
}

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
    ),
  ];

  PandoraInviteRequest? lastInvite;

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

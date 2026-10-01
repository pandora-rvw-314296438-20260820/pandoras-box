import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_user_admin_api.dart';
import 'package:pandora_mobile/features/enterprise/plp_team_management_screen.dart';

class _FakeAdminGateway implements PandoraUserAdminGateway {
  final organization = const PandoraOrganizationAccess(
    id: 'org-plp',
    name: 'PLP Boracay',
    role: 'owner',
    slug: 'plp-boracay',
  );

  final members = <PandoraTeamMember>[
    const PandoraTeamMember(
      id: 'owner-1',
      email: 'owner@example.com',
      displayName: 'Owner',
      role: 'owner',
      status: 'active',
      isCurrentUser: true,
    ),
    const PandoraTeamMember(
      id: 'staff-1',
      email: 'staff@example.com',
      displayName: 'Resort Manager',
      role: 'operator',
      status: 'active',
    ),
  ];

  PandoraInviteRequest? invited;
  PandoraMemberUpdateRequest? updated;

  @override
  Future<List<PandoraOrganizationAccess>> loadOrganizations() async =>
      <PandoraOrganizationAccess>[organization];

  @override
  Future<List<PandoraTeamMember>> loadMembers(String organizationId) async =>
      List<PandoraTeamMember>.from(members);

  @override
  Future<PandoraInviteResult> inviteMember(
    String organizationId,
    PandoraInviteRequest request,
  ) async {
    invited = request;
    members.add(
      PandoraTeamMember(
        id: 'invite-1',
        email: request.email,
        displayName: request.displayName,
        role: request.role,
        status: 'invited',
      ),
    );
    return PandoraInviteResult(
      userId: 'invite-1',
      email: request.email,
      displayName: request.displayName,
      role: request.role,
      status: 'invited',
      inviteSent: true,
      existingAccount: false,
      requestId: 'invite-request',
    );
  }

  @override
  Future<PandoraMemberUpdateResult> updateMember(
    String organizationId,
    PandoraMemberUpdateRequest request,
  ) async {
    updated = request;
    final index = members.indexWhere((member) => member.id == request.userId);
    final previous = members[index];
    members[index] = PandoraTeamMember(
      id: previous.id,
      email: previous.email,
      displayName: previous.displayName,
      role: request.role ?? previous.role,
      status: request.status ?? previous.status,
    );
    return PandoraMemberUpdateResult(
      userId: request.userId,
      role: request.role ?? previous.role,
      status: request.status ?? previous.status,
      previousRole: previous.role,
      previousStatus: previous.status,
      changed: true,
      requestId: 'update-request',
    );
  }
}

void main() {
  testWidgets('owner can invite a PLP team member through normal admin UI', (tester) async {
    final gateway = _FakeAdminGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: PlpTeamManagementScreen(
          organizationId: 'org-plp',
          gateway: gateway,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-team-management-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plp-team-manage-add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('plp-team-invite-email')),
      'new.staff@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plp-team-invite-name')),
      'New Staff',
    );
    await tester.tap(find.byKey(const ValueKey('plp-team-invite-submit')));
    await tester.pumpAndSettle();

    expect(gateway.invited?.email, 'new.staff@example.com');
    expect(gateway.invited?.role, 'member');
    expect(find.text('New Staff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can change an existing PLP member access state', (tester) async {
    final gateway = _FakeAdminGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: PlpTeamManagementScreen(
          organizationId: 'org-plp',
          gateway: gateway,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('plp-team-manage-member-staff-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-team-member-role')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-team-member-status')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-team-member-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspended').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plp-team-member-save')));
    await tester.pumpAndSettle();

    expect(gateway.updated?.userId, 'staff-1');
    expect(gateway.updated?.status, 'suspended');
    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current owner row cannot open its own destructive access sheet', (tester) async {
    final gateway = _FakeAdminGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: PlpTeamManagementScreen(
          organizationId: 'org-plp',
          gateway: gateway,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('plp-team-manage-member-owner-1')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('plp-team-member-status')), findsNothing);
    expect(gateway.updated, isNull);
    expect(tester.takeException(), isNull);
  });
}

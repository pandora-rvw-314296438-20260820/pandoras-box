import 'package:flutter/material.dart';

import '../../core/data/enterprise_user_admin_api.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';
import 'enterprise_command_bus.dart';

class EnterpriseAppUsersScreen extends StatefulWidget {
  const EnterpriseAppUsersScreen({
    super.key,
    this.onSelectionChanged,
  });

  final ValueChanged<Map<String, String>?>? onSelectionChanged;

  @override
  State<EnterpriseAppUsersScreen> createState() =>
      _EnterpriseAppUsersScreenState();
}

class _EnterpriseAppUsersScreenState extends State<EnterpriseAppUsersScreen> {
  late Future<List<EnterpriseMember>> _members;
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'all';
  EnterpriseMember? _selectedMember;

  @override
  void initState() {
    super.initState();
    _members = const EnterpriseUserAdminApi().members();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = const EnterpriseUserAdminApi().members();
    setState(() => _members = next);
    await next;
  }

  void _select(EnterpriseMember member) {
    final selected = _selectedMember?.userId == member.userId ? null : member;
    setState(() => _selectedMember = selected);
    widget.onSelectionChanged?.call(
      selected == null
          ? null
          : <String, String>{
              'kind': 'organization_user',
              'id': selected.userId,
              'email': selected.email,
              'role': selected.role,
              'identityScope': 'pandora_organization',
            },
    );
  }

  void _offer(String command) {
    EnterpriseCommandDraftBus.shared.offer(command);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Team & Access',
        subtitle:
            'Enterprise access and PLP Property Staff are separate identity scopes.',
        onRefresh: _refresh,
        child: FutureBuilder<List<EnterpriseMember>>(
          future: _members,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return _error(snapshot.error.toString());
            }
            return _content(snapshot.data ?? const <EnterpriseMember>[]);
          },
        ),
      );

  Widget _content(List<EnterpriseMember> members) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = members.where((member) {
      final matchesQuery = query.isEmpty ||
          member.email.toLowerCase().contains(query) ||
          member.role.toLowerCase().contains(query) ||
          member.status.toLowerCase().contains(query);
      if (!matchesQuery) return false;
      return switch (_filter) {
        'privileged' =>
          const <String>{'owner', 'admin'}.contains(member.role.toLowerCase()),
        'active' => member.status.toLowerCase() == 'active',
        _ => true,
      };
    }).toList(growable: false);

    final active = members
        .where((member) => member.status.toLowerCase() == 'active')
        .length;
    final privileged = members
        .where(
          (member) => const <String>{'owner', 'admin'}
              .contains(member.role.toLowerCase()),
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading(
          'Dashboard',
          'Verified organization-access state from the provider.',
        ),
        const SizedBox(height: 10),
        _summaryMetrics(members.length, active, privileged),
        const SizedBox(height: 20),
        _sectionHeading(
          'Workspace',
          'Search, inspect and act on one identity scope at a time.',
        ),
        const SizedBox(height: 10),
        PandoraSurface(
          title: 'Enterprise access',
          subtitle:
              'Pandora organization identities only. These roles never imply PLP Property Staff permissions.',
          leading: const Icon(Icons.admin_panel_settings_outlined),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search Enterprise access',
                  hintText: 'Email, role or status',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  FilterChip(
                    label: const Text('Owner / Admin'),
                    selected: _filter == 'privileged',
                    onSelected: (_) => setState(() => _filter = 'privileged'),
                  ),
                  FilterChip(
                    label: const Text('Active'),
                    selected: _filter == 'active',
                    onSelected: (_) => setState(() => _filter = 'active'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No Enterprise access identities match this view.',
                    style: TextStyle(color: PandoraV2Colors.muted),
                  ),
                )
              else
                for (final member in visible) _memberRow(member),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton.icon(
                    onPressed: () => _offer(
                      'Prepare an Enterprise access invitation. Ask me for the email and Pandora organization role before any mutation. Keep PLP Property Staff completely separate.',
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Invite Enterprise user'),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selectedMember != null) ...[
          const SizedBox(height: 20),
          _sectionHeading(
            'Adaptive Canvas',
            'Inspect permission impact before a consequential change.',
          ),
          const SizedBox(height: 10),
          _memberCanvas(_selectedMember!),
        ],
        const SizedBox(height: 20),
        PandoraSurface(
          title: 'PLP Property Staff',
          subtitle: 'Separate identity scope · no silent role mapping',
          leading: const Icon(Icons.badge_outlined),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Property-staff roles such as reservations, housekeeping or operations are not inferred from Pandora organization roles. This screen will show staff identities only when the provider returns them for the PLP staff scope.',
                style: TextStyle(
                  color: PandoraV2Colors.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: OutlinedButton.icon(
                    onPressed: () => _offer(
                      'Show the provider-verified PLP Property Staff identities and role namespace. Keep them separate from Enterprise access and do not mutate anything.',
                    ),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Inspect Property Staff'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryMetrics(int total, int active, int privileged) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final columns = constraints.maxWidth >= 760 && scale < 1.6
              ? 3
              : constraints.maxWidth >= 480 && scale < 1.4
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(width, 'Enterprise identities', '$total',
                  'Provider-visible accounts'),
              _metric(width, 'Active', '$active', 'Active organization access'),
              _metric(width, 'Owner / Admin', '$privileged',
                  'Privileged Enterprise access'),
            ],
          );
        },
      );

  Widget _metric(double width, String label, String value, String detail) =>
      SizedBox(
        width: width,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PandoraV2Colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PandoraV2Colors.muted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _memberRow(EnterpriseMember member) {
    final selected = _selectedMember?.userId == member.userId;
    return Semantics(
      button: true,
      selected: selected,
      label: '${member.email}, role ${member.role}, status ${member.status}',
      child: InkWell(
        key: ValueKey<String>('enterprise-user-${member.userId}'),
        onTap: () => _select(member),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 7),
          decoration: BoxDecoration(
            color: selected ? PandoraV2Colors.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? PandoraV2Colors.ink : PandoraV2Colors.muted,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.email.isEmpty ? 'Account' : member.email,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${member.role} · ${member.status}',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle_rounded, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberCanvas(EnterpriseMember member) => PandoraSurface(
        title: 'Permission impact · ${member.email}',
        subtitle: 'Enterprise access only',
        leading: const Icon(Icons.fact_check_outlined),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Current role: ${member.role}\nCurrent status: ${member.status}\nIdentity scope: Pandora organization',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              'Any role change or revocation must be authorized and provider-verified before this page changes. PLP Property Staff access is unaffected.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton.icon(
                    onPressed: () => _offer(
                      'Show the permission impact of changing ${member.email} from Enterprise role ${member.role}. Do not mutate anything until I choose and approve the target role.',
                    ),
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Review role change'),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: OutlinedButton.icon(
                    onPressed: () => _offer(
                      'Prepare to revoke Enterprise access for ${member.email}. Show impact and reversibility, request approval, and only update this page after provider readback. Do not change PLP Property Staff.',
                    ),
                    icon: const Icon(Icons.person_off_outlined),
                    label: const Text('Review revocation'),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: TextButton(
                    onPressed: () {
                      setState(() => _selectedMember = null);
                      widget.onSelectionChanged?.call(null);
                    },
                    child: const Text('Clear selection'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _sectionHeading(String title, String subtitle) => Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      );

  Widget _error(String value) => PandoraSurface(
        title: 'Team & Access unavailable',
        subtitle: 'No identity or permission state was changed.',
        leading: const Icon(Icons.error_outline_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              value.replaceFirst('EnterpriseUserAdminException: ', ''),
              style: const TextStyle(color: PandoraV2Colors.muted),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
}

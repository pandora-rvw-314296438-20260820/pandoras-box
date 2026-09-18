import 'package:flutter/material.dart';

import '../../core/data/enterprise_user_admin_api.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';

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
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _members = const EnterpriseUserAdminApi().members();
  }

  Future<void> _refresh() async {
    final next = const EnterpriseUserAdminApi().members();
    setState(() => _members = next);
    await next;
  }

  void _select(EnterpriseMember member) {
    final selected = _selectedUserId == member.userId ? null : member;
    setState(() => _selectedUserId = selected?.userId);
    widget.onSelectionChanged?.call(
      selected == null
          ? null
          : <String, String>{
              'kind': 'organization_user',
              'id': selected.userId,
              'email': selected.email,
              'role': selected.role,
            },
    );
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'App Users',
        subtitle: 'Pandora organization identity and access',
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
              return _error('${snapshot.error}');
            }
            final members = snapshot.data ?? const <EnterpriseMember>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PandoraSurface(
                  title: 'Organization users',
                  subtitle:
                      'Secure invitations and membership readback come from Supabase Auth. Reusable passwords are never displayed.',
                  leading: const Icon(Icons.group_outlined),
                  child: members.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No organization users are visible to this account.',
                            style: TextStyle(color: PandoraV2Colors.muted),
                          ),
                        )
                      : Column(
                          children: [
                            for (final member in members) _memberRow(member),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                PandoraSurface(
                  title: 'Use the command bar',
                  subtitle: 'Examples',
                  leading: const Icon(Icons.auto_awesome_rounded),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create admin for name@example.com'),
                      SizedBox(height: 6),
                      Text('Invite viewer for finance@example.com'),
                      SizedBox(height: 10),
                      Text(
                        'Pandora validates your owner/admin role, sends a secure invitation when required, assigns the scoped organization role, and verifies the membership before the page refreshes.',
                        style: TextStyle(
                          color: PandoraV2Colors.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _memberRow(EnterpriseMember member) {
    final selected = _selectedUserId == member.userId;
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
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: selected ? PandoraV2Colors.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? PandoraV2Colors.ink : PandoraV2Colors.line,
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
              if (selected) const Icon(Icons.check_circle_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _error(String value) => PandoraSurface(
        title: 'App Users unavailable',
        subtitle: 'No membership data was changed.',
        leading: const Icon(Icons.error_outline_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              value.replaceFirst('EnterpriseUserAdminException: ', ''),
              style: const TextStyle(color: PandoraV2Colors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
}

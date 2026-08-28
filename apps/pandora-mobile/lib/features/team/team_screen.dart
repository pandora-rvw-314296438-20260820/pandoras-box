import 'package:flutter/material.dart';

import '../../core/data/pandora_user_admin_api.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, this.gateway});

  final PandoraUserAdminGateway? gateway;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late final PandoraUserAdminGateway _gateway;
  List<PandoraOrganizationAccess> _organizations = const [];
  List<PandoraTeamMember> _members = const [];
  String? _selectedOrganizationId;
  PandoraUserAdminFailure? _failure;
  bool _loading = true;
  bool _refreshing = false;
  bool _inviting = false;

  PandoraOrganizationAccess? get _selectedOrganization {
    final id = _selectedOrganizationId;
    if (id == null) return null;
    for (final organization in _organizations) {
      if (organization.id == id) return organization;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? SupabasePandoraUserAdminGateway();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    if (!mounted) return;
    setState(() {
      if (initial) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _failure = null;
    });

    try {
      final organizations = await _gateway.loadOrganizations();
      var selected = _selectedOrganizationId;
      if (!organizations.any((organization) => organization.id == selected)) {
        selected = organizations.isEmpty ? null : organizations.first.id;
      }
      final members = selected == null
          ? const <PandoraTeamMember>[]
          : await _gateway.loadMembers(selected);
      if (!mounted) return;
      setState(() {
        _organizations = organizations;
        _selectedOrganizationId = selected;
        _members = members;
      });
    } on PandoraUserAdminFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _failure = const PandoraUserAdminFailure(
          code: 'UNKNOWN',
          message: 'Pandora could not load the team right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _selectOrganization(String? id) async {
    if (id == null || id == _selectedOrganizationId) return;
    setState(() {
      _selectedOrganizationId = id;
      _members = const [];
      _loading = true;
      _failure = null;
    });
    try {
      final members = await _gateway.loadMembers(id);
      if (!mounted || _selectedOrganizationId != id) return;
      setState(() => _members = members);
    } on PandoraUserAdminFailure catch (failure) {
      if (!mounted || _selectedOrganizationId != id) return;
      setState(() => _failure = failure);
    } finally {
      if (mounted && _selectedOrganizationId == id) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openInvite() async {
    final organization = _selectedOrganization;
    if (organization == null || _inviting) return;
    final request = await showModalBottomSheet<PandoraInviteRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _InviteMemberSheet(isOwner: organization.isOwner),
    );
    if (request == null || !mounted) return;

    setState(() {
      _inviting = true;
      _failure = null;
    });
    try {
      final result = await _gateway.inviteMember(organization.id, request);
      final members = await _gateway.loadMembers(organization.id);
      if (!mounted) return;
      setState(() => _members = members);
      final text = result.inviteSent
          ? 'Invitation sent to ${result.email}.'
          : result.existingAccount
              ? '${result.email} was added to the team.'
              : '${result.email} is ready to join.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    } on PandoraUserAdminFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PandoraPage(
          title: 'Team',
          subtitle: 'Invite people and give each person the access they need.',
          onRefresh: _load,
          actions: [
            IconButton(
              tooltip: 'Refresh team',
              onPressed: _refreshing ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          child: _buildBody(context),
        ),
      );

  Widget _buildBody(BuildContext context) {
    if (_loading && _organizations.isEmpty) {
      return const _TeamLoadingState();
    }

    if (_failure?.isPermissionFailure == true ||
        (!_loading && _organizations.isEmpty && _failure == null)) {
      return _NoTeamAccessState(onRetry: () => _load(initial: true));
    }

    if (_failure != null && _organizations.isEmpty) {
      return _TeamFailureState(
        failure: _failure!,
        onRetry: () => _load(initial: true),
      );
    }

    final organization = _selectedOrganization;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_organizations.length > 1) ...[
          PandoraSurface(
            title: 'Organization',
            child: DropdownButtonFormField<String>(
              initialValue: _selectedOrganizationId,
              decoration: const InputDecoration(
                labelText: 'Manage team for',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              items: _organizations
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _selectOrganization,
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
        ],
        _TeamSummary(
          organization: organization,
          members: _members,
          inviting: _inviting,
          refreshing: _refreshing,
          onInvite: _openInvite,
        ),
        if (_failure != null) ...[
          const SizedBox(height: PandoraSpacing.md),
          _InlineFailure(failure: _failure!, onRetry: _load),
        ],
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'People',
          subtitle: _members.isEmpty
              ? 'The people who can use this Pandora organization appear here.'
              : '${_members.length} ${_members.length == 1 ? 'person' : 'people'}',
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: PandoraSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _members.isEmpty
                  ? _EmptyTeamState(onInvite: _openInvite)
                  : Column(
                      children: [
                        for (var index = 0;
                            index < _members.length;
                            index++) ...[
                          _MemberTile(member: _members[index]),
                          if (index != _members.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
        ),
        const SizedBox(height: PandoraSpacing.lg),
      ],
    );
  }
}

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({
    required this.organization,
    required this.members,
    required this.inviting,
    required this.refreshing,
    required this.onInvite,
  });

  final PandoraOrganizationAccess? organization;
  final List<PandoraTeamMember> members;
  final bool inviting;
  final bool refreshing;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final active = members.where((member) => member.isActive).length;
    final invited = members.where((member) => member.isInvited).length;
    return PandoraSurface(
      title: organization?.name ?? 'Your team',
      subtitle: organization == null
          ? 'Organization access is being checked.'
          : 'You are an ${_roleLabel(organization!.role).toLowerCase()}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: PandoraSpacing.sm,
            runSpacing: PandoraSpacing.sm,
            children: [
              _Metric(label: 'Active', value: '$active'),
              _Metric(label: 'Invited', value: '$invited'),
              _Metric(label: 'Total', value: '${members.length}'),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
          FilledButton.icon(
            onPressed: organization == null || inviting ? null : onInvite,
            icon: inviting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: Text(inviting ? 'Adding person…' : 'Add person'),
          ),
          if (refreshing) ...[
            const SizedBox(height: PandoraSpacing.sm),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        child: Container(
          constraints: const BoxConstraints(minWidth: 92),
          padding: const EdgeInsets.symmetric(
            horizontal: PandoraSpacing.md,
            vertical: PandoraSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final PandoraTeamMember member;

  @override
  Widget build(BuildContext context) {
    final statusColor = member.isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;
    return Semantics(
      container: true,
      label:
          '${member.primaryLabel}, ${_roleLabel(member.role)}, ${_statusLabel(member.status)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(child: Text(member.initials)),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.primaryLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (member.displayName != null && member.email != null)
                    Text(
                      member.email!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: PandoraSpacing.xxs),
                  Wrap(
                    spacing: PandoraSpacing.xs,
                    runSpacing: PandoraSpacing.xxs,
                    children: [
                      _Tag(label: _roleLabel(member.role)),
                      _Tag(
                        label: _statusLabel(member.status),
                        foreground: statusColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.foreground});

  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: (foreground ?? Theme.of(context).colorScheme.onSurface)
              .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet({required this.isOwner});

  final bool isOwner;

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'UTC');
  String _role = 'member';

  List<String> get _roles => widget.isOwner
      ? const ['admin', 'operator', 'member', 'viewer']
      : const ['operator', 'member', 'viewer'];

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      PandoraInviteRequest(
        email: _emailController.text,
        displayName: _nameController.text,
        timezone: _timezoneController.text,
        role: _role,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        PandoraSpacing.lg,
        PandoraSpacing.sm,
        PandoraSpacing.lg,
        PandoraSpacing.lg + bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add a person',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              'Pandora will send an invitation and apply the selected access after the person confirms their email.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: PandoraSpacing.lg),
            TextFormField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'person@example.com',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter an email address.';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: PandoraSpacing.md),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => (value?.trim().length ?? 0) > 120
                  ? 'Keep the name under 120 characters.'
                  : null,
            ),
            const SizedBox(height: PandoraSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Access',
                prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              ),
              items: _roles
                  .map(
                    (role) => DropdownMenuItem<String>(
                      value: role,
                      child: Text(_roleLabel(role)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _role = value ?? 'member'),
            ),
            const SizedBox(height: PandoraSpacing.md),
            TextFormField(
              controller: _timezoneController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Timezone',
                helperText: 'Used for activity times and notifications.',
                prefixIcon: Icon(Icons.schedule_rounded),
              ),
              validator: (value) {
                final timezone = value?.trim() ?? '';
                if (timezone.isEmpty) return 'Enter a timezone or use UTC.';
                if (timezone.length > 64) {
                  return 'Keep the timezone under 64 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: PandoraSpacing.lg),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send invitation'),
            ),
            const SizedBox(height: PandoraSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamLoadingState extends StatelessWidget {
  const _TeamLoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 72),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _EmptyTeamState extends StatelessWidget {
  const _EmptyTeamState({required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.lg),
        child: Column(
          children: [
            Icon(
              Icons.group_add_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: PandoraSpacing.sm),
            Text('No one has been added yet.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              'Add the first person and choose what they can access.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: PandoraSpacing.md),
            OutlinedButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add person'),
            ),
          ],
        ),
      );
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.failure, required this.onRetry});

  final PandoraUserAdminFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: PandoraSpacing.sm),
              Expanded(
                child: Text(
                  failure.message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _TeamFailureState extends StatelessWidget {
  const _TeamFailureState({required this.failure, required this.onRetry});

  final PandoraUserAdminFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        title: 'Team is temporarily unavailable',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(failure.message),
            if (failure.requestId != null) ...[
              const SizedBox(height: PandoraSpacing.xs),
              SelectableText(
                'Reference: ${failure.requestId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: PandoraSpacing.md),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
}

class _NoTeamAccessState extends StatelessWidget {
  const _NoTeamAccessState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        title: 'Owner or administrator access required',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Only an active organization owner or administrator can invite people or view the team directory.',
            ),
            const SizedBox(height: PandoraSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check access again'),
            ),
          ],
        ),
      );
}

String _roleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Administrator',
      'operator' => 'Operator',
      'viewer' => 'Viewer',
      _ => 'Member',
    };

String _statusLabel(String status) => switch (status) {
      'active' => 'Active',
      'invited' => 'Invited',
      'suspended' => 'Suspended',
      'revoked' => 'Revoked',
      _ => status,
    };

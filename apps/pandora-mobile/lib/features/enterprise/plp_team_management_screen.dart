import 'package:flutter/material.dart';

import '../../core/data/pandora_user_admin_api.dart';

class PlpTeamManagementScreen extends StatefulWidget {
  const PlpTeamManagementScreen({
    super.key,
    required this.organizationId,
    required this.onBack,
    this.onChanged,
    this.gateway,
    this.openInviteOnLoad = false,
  });

  final String organizationId;
  final VoidCallback onBack;
  final VoidCallback? onChanged;
  final PandoraUserAdminGateway? gateway;
  final bool openInviteOnLoad;

  @override
  State<PlpTeamManagementScreen> createState() =>
      _PlpTeamManagementScreenState();
}

class _PlpTeamManagementScreenState extends State<PlpTeamManagementScreen> {
  static const _canvas = Color(0xFF050505);
  static const _paper = Color(0xFF0E0E0F);
  static const _ink = Color(0xFFF2EEE7);
  static const _muted = Color(0xFFA49D93);
  static const _gold = Color(0xFFD6AD63);
  static const _goldSoft = Color(0xFF17130D);
  static const _line = Color(0xFF2C2924);
  static const _green = Color(0xFF8FA889);

  late final PandoraUserAdminGateway _gateway;
  PandoraOrganizationAccess? _organization;
  List<PandoraTeamMember> _members = const <PandoraTeamMember>[];
  PandoraUserAdminFailure? _failure;
  bool _loading = true;
  bool _refreshing = false;
  bool _mutating = false;
  bool _initialInviteOpened = false;

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
      PandoraOrganizationAccess? selected;
      for (final item in organizations) {
        if (item.id == widget.organizationId) {
          selected = item;
          break;
        }
      }
      if (selected == null) {
        throw const PandoraUserAdminFailure(
          code: 'ORGANIZATION_ACCESS_REQUIRED',
          message: 'PLP team administration is not available for this account.',
        );
      }
      final members = await _gateway.loadMembers(selected.id);
      if (!mounted) return;
      setState(() {
        _organization = selected;
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
          message: 'Pandora could not load the PLP team right now.',
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

    if (initial &&
        widget.openInviteOnLoad &&
        !_initialInviteOpened &&
        mounted &&
        _organization != null) {
      _initialInviteOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openInvite();
      });
    }
  }

  Future<void> _openInvite() async {
    final organization = _organization;
    if (organization == null || _mutating) return;
    final request = await showModalBottomSheet<PandoraInviteRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _paper,
      builder: (context) => _InviteSheet(isOwner: organization.isOwner),
    );
    if (request == null || !mounted) return;

    setState(() {
      _mutating = true;
      _failure = null;
    });
    try {
      final result = await _gateway.inviteMember(organization.id, request);
      await _load();
      widget.onChanged?.call();
      if (!mounted) return;
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
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _openMember(PandoraTeamMember member) async {
    final organization = _organization;
    if (organization == null || _mutating || member.isCurrentUser) return;
    if (!organization.isOwner &&
        (member.role == 'owner' || member.role == 'admin')) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Only an owner can change owner or administrator access.',
            ),
          ),
        );
      return;
    }

    final request = await showModalBottomSheet<PandoraMemberUpdateRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _paper,
      builder: (context) => _ManageSheet(
        member: member,
        isOwner: organization.isOwner,
      ),
    );
    if (request == null || !mounted) return;

    setState(() {
      _mutating = true;
      _failure = null;
    });
    try {
      final result = await _gateway.updateMember(organization.id, request);
      await _load();
      widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.changed
                  ? '${member.primaryLabel} access was updated.'
                  : 'No access changes were needed.',
            ),
          ),
        );
    } on PandoraUserAdminFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Administrator';
      case 'operator':
        return 'Operator';
      case 'viewer':
        return 'Viewer';
      default:
        return 'Team member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _members.where((member) => member.isActive).length;
    final invited = _members.where((member) => member.isInvited).length;
    return Material(
      color: _canvas,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onBack: widget.onBack,
              onRefresh: _refreshing ? null : () => _load(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  key: const ValueKey<String>('plp-team-management-page'),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
                  children: [
                    const Text(
                      'TEAM & ACCESS',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Manage your people',
                      style: TextStyle(
                        color: _ink,
                        fontFamily: 'serif',
                        fontSize: 38,
                        height: .98,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'One PLP directory for invitations, roles and access status.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Metric(label: 'Active', value: '$active'),
                        _Metric(label: 'Invited', value: '$invited'),
                        _Metric(label: 'Total', value: '${_members.length}'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const ValueKey<String>('plp-team-manage-add'),
                      onPressed:
                          _organization == null || _mutating ? null : _openInvite,
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_mutating ? 'Working…' : 'Add person'),
                    ),
                    if (_failure != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        key: const ValueKey<String>('plp-team-manage-error'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF241311),
                          border: Border.all(color: const Color(0xFF5A312D)),
                        ),
                        child: Text(
                          _failure!.message,
                          style: const TextStyle(
                            color: Color(0xFFD8645B),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    const Text(
                      'People with access',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_members.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'No PLP membership records are available.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      for (var index = 0;
                          index < _members.length;
                          index++) ...[
                        _MemberRow(
                          member: _members[index],
                          roleLabel: _roleLabel(_members[index].role),
                          onTap: _members[index].isCurrentUser
                              ? null
                              : () => _openMember(_members[index]),
                        ),
                        if (index != _members.length - 1)
                          const Divider(height: 1, color: _line),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onRefresh});

  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: _PlpTeamManagementScreenState._paper,
          border: Border(
            bottom: BorderSide(color: _PlpTeamManagementScreenState._line),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey<String>('plp-team-management-back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'PUEBLO LA PERLA',
                style: TextStyle(
                  color: Color(0xFFCFB27A),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('plp-team-management-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 94),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
        decoration: BoxDecoration(
          color: _PlpTeamManagementScreenState._paper,
          border: Border.all(color: _PlpTeamManagementScreenState._line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: _PlpTeamManagementScreenState._ink,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: _PlpTeamManagementScreenState._muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.roleLabel,
    required this.onTap,
  });

  final PandoraTeamMember member;
  final String roleLabel;
  final VoidCallback? onTap;

  Color get _statusColor {
    switch (member.status) {
      case 'active':
        return _PlpTeamManagementScreenState._green;
      case 'invited':
        return const Color(0xFFD6AD63);
      case 'suspended':
        return const Color(0xFFC98654);
      default:
        return const Color(0xFFC6766E);
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        key: ValueKey<String>('plp-team-manage-member-${member.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _PlpTeamManagementScreenState._goldSoft,
                  border:
                      Border.all(color: _PlpTeamManagementScreenState._line),
                ),
                alignment: Alignment.center,
                child: Text(
                  member.initials,
                  style: const TextStyle(
                    color: _PlpTeamManagementScreenState._ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.primaryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _PlpTeamManagementScreenState._ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (member.isCurrentUser) ...[
                          const SizedBox(width: 6),
                          const Text(
                            'YOU',
                            style: TextStyle(
                              color: _PlpTeamManagementScreenState._gold,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      member.email ?? roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _PlpTeamManagementScreenState._muted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      roleLabel,
                      style: const TextStyle(
                        color: _PlpTeamManagementScreenState._gold,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: _statusColor.withValues(alpha: .4)),
                ),
                child: Text(
                  member.status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _PlpTeamManagementScreenState._gold,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.isOwner});

  final bool isOwner;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  String _role = 'member';

  List<String> get _roles => widget.isOwner
      ? const ['owner', 'admin', 'operator', 'member', 'viewer']
      : const ['operator', 'member', 'viewer'];

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').hasMatch(email)) {
      return;
    }
    Navigator.of(context).pop(
      PandoraInviteRequest(
        email: email,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        role: _role,
        timezone: 'Asia/Manila',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 10, 22, bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add a person',
            style: TextStyle(
              color: _PlpTeamManagementScreenState._ink,
              fontFamily: 'serif',
              fontSize: 30,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('plp-team-invite-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('plp-team-invite-name'),
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('plp-team-invite-role'),
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
            items: [
              for (final role in _roles)
                DropdownMenuItem<String>(
                  value: role,
                  child: Text(role[0].toUpperCase() + role.substring(1)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _role = value);
            },
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey<String>('plp-team-invite-submit'),
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _PlpTeamManagementScreenState._ink,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: const Text('Send invitation'),
          ),
        ],
      ),
    );
  }
}

class _ManageSheet extends StatefulWidget {
  const _ManageSheet({required this.member, required this.isOwner});

  final PandoraTeamMember member;
  final bool isOwner;

  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  late String _role;
  late String _status;

  bool get _pendingInvite => widget.member.isInvited;

  List<String> get _roles => widget.isOwner
      ? const ['owner', 'admin', 'operator', 'member', 'viewer']
      : const ['operator', 'member', 'viewer'];

  List<String> get _statuses => _pendingInvite
      ? const ['revoked']
      : const ['active', 'suspended', 'revoked'];

  @override
  void initState() {
    super.initState();
    _role = widget.member.role;
    _status = _pendingInvite ? 'revoked' : widget.member.status;
    if (!_roles.contains(_role)) _role = _roles.last;
    if (!_statuses.contains(_status)) _status = _statuses.first;
  }

  void _submit() {
    Navigator.of(context).pop(
      PandoraMemberUpdateRequest(
        userId: widget.member.id,
        role: _pendingInvite ? null : _role,
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 10, 22, bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.member.primaryLabel,
            style: const TextStyle(
              color: _PlpTeamManagementScreenState._ink,
              fontFamily: 'serif',
              fontSize: 30,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          if (!_pendingInvite) ...[
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('plp-team-member-role'),
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
              items: [
                for (final role in _roles)
                  DropdownMenuItem<String>(
                    value: role,
                    child: Text(role[0].toUpperCase() + role.substring(1)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('plp-team-member-status'),
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Access status',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
            items: [
              for (final status in _statuses)
                DropdownMenuItem<String>(
                  value: status,
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey<String>('plp-team-member-save'),
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _PlpTeamManagementScreenState._ink,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: const Text('Save access'),
          ),
        ],
      ),
    );
  }
}

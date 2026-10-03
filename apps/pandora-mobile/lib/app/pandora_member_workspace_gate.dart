import 'dart:async';

import 'package:flutter/material.dart';

import '../core/data/pandora_core_api.dart';
import '../core/data/pandora_enterprise_api.dart';
import '../core/security/pandora_auth.dart';
import '../core/security/pandora_identity_verification.dart';
import 'pandora_chat_shell.dart';
import 'pandora_core_client_scope.dart';

/// The normal customer entry point uses only the caller's own memberships.
/// Internal support staff still obtain the same audited, expiring entry receipt.
class PandoraMemberWorkspaceGate extends StatefulWidget {
  const PandoraMemberWorkspaceGate({
    super.key,
    required this.auth,
    required this.accessSource,
    this.coreGateway,
    this.enterpriseGateway,
    this.clientRuntimeFactory,
  });

  final PandoraAuth auth;
  final PandoraWorkspaceAccessSource accessSource;
  final PandoraCoreGateway? coreGateway;
  final PandoraEnterpriseGateway? enterpriseGateway;
  final PandoraClientRuntimeFactory? clientRuntimeFactory;

  @override
  State<PandoraMemberWorkspaceGate> createState() =>
      _PandoraMemberWorkspaceGateState();
}

class _PandoraMemberWorkspaceGateState extends State<PandoraMemberWorkspaceGate>
    with WidgetsBindingObserver {
  late final PandoraCoreGateway _coreGateway;
  List<PandoraEnterpriseMembership> _workspaces = const [];
  PandoraEnterpriseMembership? _selected;
  PandoraClientEntry? _entry;
  PandoraCoreFailure? _error;
  Timer? _verificationTimer;
  bool _loading = true;
  bool _opening = false;
  bool _signingOut = false;
  int _generation = 0;
  int _workspaceEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coreGateway = widget.coreGateway ?? SupabasePandoraCoreGateway();
    unawaited(_reload());
    _verificationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_selected != null && !_opening) unawaited(_reload());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  @override
  void dispose() {
    _generation++;
    _verificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final userId = widget.auth.currentSession?.userId;
    if (mounted) setState(() => _loading = true);
    try {
      if (userId == null) {
        throw const PandoraCoreFailure('SIGN_IN_REQUIRED', 'Sign in again.');
      }
      final access = await widget.accessSource
          .loadWorkspaceAccess()
          .timeout(const Duration(seconds: 10));
      if (!mounted ||
          generation != _generation ||
          widget.auth.currentSession?.userId != userId) return;
      final current = _selected;
      PandoraEnterpriseMembership? fresh;
      if (current != null) {
        for (final workspace in access.workspaces) {
          if (workspace.organizationId == current.organizationId) {
            fresh = workspace;
            break;
          }
        }
      }
      setState(() {
        _workspaces = access.workspaces;
        _loading = false;
        _error = null;
        if (current != null &&
            (fresh == null ||
                fresh.role != current.role ||
                fresh.adapter != current.adapter ||
                fresh.requiresOperatorEntry != current.requiresOperatorEntry ||
                (fresh.requiresOperatorEntry && _entry == null))) {
          _selected = null;
          _entry = null;
          _workspaceEpoch++;
          _error = const PandoraCoreFailure('ACCESS_CHANGED',
              'Workspace access changed. Select a workspace again.');
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _selected = null;
        _entry = null;
        _workspaces = const [];
        _workspaceEpoch++;
        _loading = false;
        _error = error is PandoraCoreFailure
            ? error
            : const PandoraCoreFailure('UNAVAILABLE',
                'Workspace access could not be checked. Retry when connected.');
      });
    }
  }

  Future<void> _open(PandoraEnterpriseMembership workspace) async {
    if (_opening ||
        _loading ||
        !_workspaces.any((value) => identical(value, workspace))) return;
    final generation = _generation;
    final userId = widget.auth.currentSession?.userId;
    if (userId == null) {
      setState(() {
        _workspaces = const [];
        _error = const PandoraCoreFailure('SIGN_IN_REQUIRED', 'Sign in again.');
      });
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      PandoraClientEntry? entry;
      if (workspace.requiresOperatorEntry) {
        var reason = '';
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Enter ${workspace.displayName}'),
            content: TextField(
              key: const ValueKey('member-entry-reason'),
              autofocus: true,
              maxLength: 300,
              decoration: const InputDecoration(
                  labelText: 'Reason for administrator access'),
              onChanged: (value) => reason = value,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Continue')),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
        if (reason.trim().length < 10) {
          throw const PandoraCoreFailure('REASON_REQUIRED',
              'Add a clear reason for entering this customer workspace.');
        }
        PandoraCoreRecord receipt;
        try {
          receipt = await _coreGateway.enterClient(workspace.organizationId,
              reason: reason.trim());
        } on PandoraCoreFailure catch (error) {
          if (error.code != 'STEP_UP_REQUIRED' ||
              !mounted ||
              !await verifyCoreIdentity(context, widget.auth)) rethrow;
          receipt = await _coreGateway.enterClient(workspace.organizationId,
              reason: reason.trim());
        }
        entry = PandoraClientEntry.verify(receipt,
            requestedOrganizationId: workspace.organizationId);
        if (entry.adapter != workspace.adapter) {
          throw const PandoraCoreFailure('SCOPE_MISMATCH',
              'The workspace changed. Refresh access before entering.');
        }
      }
      if (!mounted ||
          generation != _generation ||
          widget.auth.currentSession?.userId != userId) return;
      setState(() {
        _selected = workspace;
        _entry = entry;
        _workspaceEpoch++;
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = error is PandoraCoreFailure
            ? error
            : const PandoraCoreFailure(
                'UNAVAILABLE', 'This workspace could not be opened. Retry.'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _closeWorkspace() {
    setState(() {
      _selected = null;
      _entry = null;
      _workspaceEpoch++;
    });
    unawaited(_reload());
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    _generation++;
    setState(() {
      _signingOut = true;
      _selected = null;
      _entry = null;
      _workspaces = const [];
      _loading = false;
      _workspaceEpoch++;
    });
    try {
      await widget.auth.signOut();
    } catch (_) {
      if (mounted)
        setState(() => _error = const PandoraCoreFailure(
            'UNAVAILABLE', 'Pandora could not sign out. Retry.'));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    if (selected != null) {
      return Stack(children: [
        AbsorbPointer(
            absorbing: _loading,
            child: PandoraChatShell(
              key: ValueKey('member-workspace-$_workspaceEpoch'),
              memberWorkspace: selected,
              initialEntry: _entry,
              coreGateway: _coreGateway,
              enterpriseGateway: widget.enterpriseGateway,
              clientRuntimeFactory: widget.clientRuntimeFactory,
              onLeaveMemberWorkspace: _closeWorkspace,
              onMemberSignOut: _signOut,
            )),
        if (_loading)
          const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(child: LinearProgressIndicator())),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My workspaces'), actions: [
        IconButton(
            tooltip: 'Sign out',
            onPressed: _signingOut ? null : _signOut,
            icon: const Icon(Icons.logout_rounded)),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!.message)),
          if (!_loading && _workspaces.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'No active workspace invitations. Ask your customer administrator for access.')),
          for (final workspace in _workspaces)
            ListTile(
              key: ValueKey('member-workspace-${workspace.organizationId}'),
              title: Text(workspace.displayName),
              subtitle: Text(workspace.requiresOperatorEntry
                  ? 'Administrator access'
                  : workspace.role),
              leading: const Icon(Icons.business_outlined),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: _opening || _loading ? null : () => _open(workspace),
            ),
          if (_opening) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _loading || _opening ? null : _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh access'))),
        ]),
      ))),
    );
  }
}

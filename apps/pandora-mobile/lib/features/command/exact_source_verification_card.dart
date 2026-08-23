import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/widgets/pandora_surface.dart';

class ExactSourceVerificationCard extends StatefulWidget {
  const ExactSourceVerificationCard({super.key});

  @override
  State<ExactSourceVerificationCard> createState() =>
      _ExactSourceVerificationCardState();
}

class _ExactSourceVerificationCardState
    extends State<ExactSourceVerificationCard> {
  final _projectId = TextEditingController();
  final _exactSha = TextEditingController();
  final _maxRuntimeSeconds = TextEditingController();
  final _idempotencyKeys = IdempotencyKeyFactory();

  WorkerJobClass _jobClass = WorkerJobClass.nodeRegression;
  bool _submitting = false;
  bool _lockedAfterAmbiguousOutcome = false;
  bool _submissionAccepted = false;
  bool _polling = false;
  String? _error;
  String? _readError;
  String? _idempotencyKey;
  IntakeReceipt? _receipt;
  WorkerExecutionStatus? _execution;
  Timer? _pollTimer;

  bool get _inputsLocked => _lockedAfterAmbiguousOutcome || _submissionAccepted;

  @override
  void initState() {
    super.initState();
    _projectId.addListener(_inputChanged);
    _exactSha.addListener(_inputChanged);
    _maxRuntimeSeconds.addListener(_inputChanged);
  }

  void _inputChanged() {
    if (!_submissionAccepted && !_submitting) _idempotencyKey = null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _projectId.removeListener(_inputChanged);
    _exactSha.removeListener(_inputChanged);
    _maxRuntimeSeconds.removeListener(_inputChanged);
    _projectId.dispose();
    _exactSha.dispose();
    _maxRuntimeSeconds.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _inputsLocked) return;

    final runtimeText = _maxRuntimeSeconds.text.trim();
    final runtime = runtimeText.isEmpty ? null : int.tryParse(runtimeText);
    if (runtimeText.isNotEmpty && runtime == null) {
      setState(() {
        _error = 'Runtime must be a whole number between 30 and 1800 seconds.';
        _receipt = null;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _receipt = null;
    });
    try {
      _idempotencyKey ??= _idempotencyKeys.create('verify-exact-source');
      final receipt =
          await PandoraDependencies.of(context).repository.verifyExactSource(
                projectId: _projectId.text,
                exactSha: _exactSha.text,
                jobClass: _jobClass,
                maxRuntimeSeconds: runtime,
                idempotencyKey: _idempotencyKey,
              );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _submissionAccepted = true;
      });
      final planId = receipt.approvalId;
      if (planId != null && planId.isNotEmpty) {
        await _readExecution(planId);
      }
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _lockedAfterAmbiguousOutcome = error.outcomeMayBeUnknown;
        _error = error.outcomeMayBeUnknown
            ? 'Pandora could not confirm the outcome. This app will not retry '
                'the write. Check Activity and the exact plan before starting '
                'another verification request.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lockedAfterAmbiguousOutcome = true;
        _error = 'Pandora could not confirm the outcome. This app will not '
            'retry the write. Check Activity and the exact plan before '
            'starting another verification request.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _readExecution(String planId) async {
    if (_polling) return;
    _polling = true;
    try {
      final execution = await PandoraDependencies.of(context)
          .repository
          .workerExecution(planId: planId);
      if (!mounted) return;
      setState(() {
        _execution = execution;
        _readError = null;
      });
      if (execution.terminal) {
        _pollTimer?.cancel();
        _pollTimer = null;
      } else {
        _ensurePolling(planId);
      }
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      if (error.kind == PandoraApiErrorKind.sessionExpired) {
        _pollTimer?.cancel();
        _pollTimer = null;
      } else {
        _ensurePolling(planId);
      }
      setState(() {
        _readError = error.kind == PandoraApiErrorKind.sessionExpired
            ? 'Sign in again to continue reading this exact plan.'
            : 'The exact plan is recorded, but its latest proof could not be read.';
      });
    } catch (_) {
      if (mounted) {
        _ensurePolling(planId);
        setState(() {
          _readError =
              'The exact plan is recorded, but its latest proof could not be read.';
        });
      }
    } finally {
      _polling = false;
    }
  }

  void _ensurePolling(String planId) {
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _readExecution(planId),
    );
  }

  @override
  Widget build(BuildContext context) => PandoraSurface(
        key: const ValueKey<String>('exact-source-verification'),
        title: 'Verify one exact source',
        subtitle:
            'Creates a governed plan for a fixed commit and bounded worker job. '
            'It never permits a production mutation.',
        leading: const Icon(Icons.verified_user_outlined),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey<String>('exact-source-project-id'),
              controller: _projectId,
              readOnly: _inputsLocked,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Project ID',
                helperText: 'Required. The canonical ProjectOS project ID.',
              ),
            ),
            const SizedBox(height: PandoraSpacing.sm),
            TextField(
              key: const ValueKey<String>('exact-source-sha'),
              controller: _exactSha,
              readOnly: _inputsLocked,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(40),
              ],
              decoration: const InputDecoration(
                labelText: 'Exact source commit SHA',
                helperText: 'Required. Exactly 40 hexadecimal characters.',
              ),
            ),
            const SizedBox(height: PandoraSpacing.sm),
            DropdownButtonFormField<WorkerJobClass>(
              key: const ValueKey<String>('exact-source-job-class'),
              initialValue: _jobClass,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Worker job'),
              items: WorkerJobClass.values
                  .map(
                    (jobClass) => DropdownMenuItem<WorkerJobClass>(
                      value: jobClass,
                      child: Text(jobClass.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _inputsLocked
                  ? null
                  : (jobClass) {
                      if (jobClass != null) {
                        setState(() {
                          _jobClass = jobClass;
                          _idempotencyKey = null;
                        });
                      }
                    },
            ),
            const SizedBox(height: PandoraSpacing.sm),
            TextField(
              key: const ValueKey<String>('exact-source-runtime'),
              controller: _maxRuntimeSeconds,
              readOnly: _inputsLocked,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: 'Maximum runtime in seconds (optional)',
                helperText: '30–1800. Leave blank for the server default.',
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            FilledButton.icon(
              key: const ValueKey<String>('exact-source-submit'),
              onPressed: _submitting || _inputsLocked ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                _submitting ? 'Submitting once…' : 'Create verification plan',
              ),
            ),
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              'This submits verify-exact-source once. An accepted request is '
              'not a tested, deployed, or production-verified result.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: PandoraSpacing.md),
              Text(
                _error!,
                key: const ValueKey<String>('exact-source-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: PandoraSpacing.md),
              Text(
                _receipt!.reply,
                key: const ValueKey<String>('exact-source-receipt'),
              ),
              const SizedBox(height: PandoraSpacing.xs),
              Text(
                _receipt!.needsApproval
                    ? 'Owner approval is still required.'
                    : 'Recorded for governed planning. No execution is claimed.',
              ),
            ],
            if (_execution != null) ...[
              const SizedBox(height: PandoraSpacing.md),
              Text(
                _execution!.plainStage,
                key: const ValueKey<String>('exact-source-lifecycle-stage'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: PandoraSpacing.xs),
              Text(
                _execution!.workerClaimObserved
                    ? '${_execution!.workerLabel} claim: observed.'
                    : '${_execution!.workerLabel} claim: not observed yet.',
                key: const ValueKey<String>('exact-source-worker-claim'),
              ),
              Text(
                _execution!.providerResultObserved
                    ? 'Exact provider result: ${_execution!.providerOutcome ?? 'recorded'}.'
                    : 'Exact provider result: not observed yet.',
                key: const ValueKey<String>('exact-source-provider-result'),
              ),
              Text(
                _execution!.finalProofAvailable
                    ? 'Final reviewer proof: available in this owner read.'
                    : 'Final reviewer proof: not available yet.',
                key: const ValueKey<String>('exact-source-final-proof'),
              ),
            ],
            if (_readError != null) ...[
              const SizedBox(height: PandoraSpacing.sm),
              Text(
                _readError!,
                key: const ValueKey<String>('exact-source-read-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      );
}

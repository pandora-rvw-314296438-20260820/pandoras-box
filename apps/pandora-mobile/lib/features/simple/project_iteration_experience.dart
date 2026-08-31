import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/network/idempotency_key.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

class ProjectIterationExperienceScreen extends StatefulWidget {
  const ProjectIterationExperienceScreen({super.key, required this.project});

  final CustomerProject project;

  @override
  State<ProjectIterationExperienceScreen> createState() =>
      _ProjectIterationExperienceScreenState();
}

class _ProjectIterationExperienceScreenState
    extends State<ProjectIterationExperienceScreen>
    with WidgetsBindingObserver {
  final _change = TextEditingController();
  final _keys = IdempotencyKeyFactory();
  Timer? _refreshTimer;
  OwnerProjectUnderstanding _understanding =
      const OwnerProjectUnderstanding.waiting();
  String? _sourceIntentId;
  String? _idempotencyKey;
  String? _error;
  bool _submitting = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sourceIntentId != null) {
      unawaited(_refreshUnderstanding());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _change.dispose();
    super.dispose();
  }

  Future<void> _submitChange() async {
    final text = _change.text.trim();
    if (text.length < 10) {
      setState(() {
        _error = 'Tell Pandora a little more about what you want changed.';
      });
      return;
    }
    final experience = PandoraDependencies.of(context)
        .projectExperienceRepository;
    if (experience == null) {
      setState(() {
        _error = 'Pandora cannot save that change right now.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _idempotencyKey ??= _keys.create('project-change-intent');
      final intentId = await experience.submitChange(
        projectId: widget.project.id,
        changeText: text,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      setState(() {
        _sourceIntentId = intentId;
        _understanding = const OwnerProjectUnderstanding.waiting();
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_refreshUnderstanding()),
      );
      await _refreshUnderstanding();
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora could not save that change right now.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _refreshUnderstanding() async {
    final sourceIntentId = _sourceIntentId;
    if (_refreshing || sourceIntentId == null || _understanding.isReady) {
      return;
    }
    final experience = PandoraDependencies.of(context)
        .projectExperienceRepository;
    if (experience == null) return;

    _refreshing = true;
    try {
      final result = await experience.understanding(
        projectId: widget.project.id,
        expectedSourceIntentId: sourceIntentId,
      );
      if (!mounted) return;
      setState(() {
        _understanding = result;
        _error = null;
      });
      if (result.isReady) _refreshTimer?.cancel();
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      _refreshing = false;
    }
  }

  void _editAgain() {
    _refreshTimer?.cancel();
    setState(() {
      _sourceIntentId = null;
      _idempotencyKey = null;
      _understanding = const OwnerProjectUnderstanding.waiting();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _sourceIntentId != null;
    final ready = _understanding.isReady;
    final rejected =
        _understanding.state == OwnerProjectUnderstandingState.rejected;

    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: ready ? 'Change understood' : 'Change this project',
        subtitle: widget.project.name,
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen()),
        ),
        onAvatar: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!submitted) ...[
            const PandoraStatusPill(
              label: 'Current live version stays untouched',
              icon: Icons.shield_outlined,
              foreground: PandoraSimpleColors.green,
              background: PandoraSimpleColors.greenWash,
            ),
            const SizedBox(height: 16),
            const Text(
              'What should Pandora change?',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Describe the result you want. Pandora will prepare a new understanding and a new preview version. Nothing live is replaced yet.',
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _change,
              minLines: 5,
              maxLines: 12,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Make the booking flow shorter and put the direct booking button above the fold.',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: PandoraSimpleColors.deepRed),
              ),
            ],
            const SizedBox(height: 20),
            PandoraPrimaryButton(
              label: _submitting ? 'Saving change…' : 'Continue',
              icon: Icons.arrow_forward_rounded,
              loading: _submitting,
              onPressed: _submitting ? null : _submitChange,
              expanded: true,
            ),
          ],
          if (submitted && !ready) ...[
            const Center(
              child: PandoraIconBadge(
                icon: Icons.auto_awesome_rounded,
                size: 66,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              rejected
                  ? 'Pandora needs a clearer change'
                  : 'Pandora is understanding the change',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rejected
                  ? 'Edit the request and Pandora will prepare a new understanding.'
                  : 'This change is stored durably. You can leave and come back without changing the current live version.',
              textAlign: TextAlign.center,
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 20),
            PandoraSimpleCard(
              shadow: false,
              child: Text(
                _change.text.trim(),
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PandoraSimpleColors.deepRed),
              ),
            ],
            const SizedBox(height: 20),
            PandoraPrimaryButton(
              label: _refreshing ? 'Checking…' : 'Check again',
              icon: Icons.refresh_rounded,
              loading: _refreshing,
              onPressed: _refreshing ? null : _refreshUnderstanding,
              expanded: true,
            ),
            const SizedBox(height: 10),
            PandoraSecondaryButton(
              label: 'Edit change',
              icon: Icons.edit_outlined,
              onPressed: _editAgain,
              expanded: true,
            ),
          ],
          if (ready) ...[
            const PandoraStatusPill(
              label: 'Ready for a new preview',
              icon: Icons.check_rounded,
              foreground: PandoraSimpleColors.green,
              background: PandoraSimpleColors.greenWash,
            ),
            const SizedBox(height: 16),
            const Text(
              'Here’s what will change',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            if (_understanding.businessSummary != null) ...[
              const SizedBox(height: 16),
              PandoraSimpleCard(
                child: Text(
                  _understanding.businessSummary!,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (_understanding.requirements.isNotEmpty) ...[
              const SizedBox(height: 18),
              const PandoraSectionTitle(title: 'Updated result'),
              PandoraSimpleCard(
                shadow: false,
                child: Column(
                  children: [
                    for (final item in _understanding.requirements.take(6))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              color: PandoraSimpleColors.green,
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  color: PandoraSimpleColors.ink,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            PandoraPrimaryButton(
              label: 'Build updated preview',
              icon: Icons.auto_awesome_rounded,
              onPressed: () => Navigator.of(context).pop(true),
              expanded: true,
            ),
            const SizedBox(height: 10),
            PandoraSecondaryButton(
              label: 'Change something else',
              icon: Icons.edit_outlined,
              onPressed: _editAgain,
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }
}

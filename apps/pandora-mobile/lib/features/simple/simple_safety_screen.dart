import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import 'pandora_simple_ui.dart';

class SimpleSafetyScreen extends StatefulWidget {
  const SimpleSafetyScreen({super.key});

  @override
  State<SimpleSafetyScreen> createState() => _SimpleSafetyScreenState();
}

class _SimpleSafetyScreenState extends State<SimpleSafetyScreen> {
  ScreenController<SafetyOverview>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<SafetyOverview>(repository.safety)..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller!,
        builder: (context, _) {
          final controller = _controller!;
          return PandoraSimplePage(
            header: PandoraOwnerHeader(
              title: 'Verify & Safety',
              subtitle: 'What protects your business right now.',
              showBack: true,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            onRefresh: controller.refresh,
            child: _body(controller),
          );
        },
      );

  Widget _body(ScreenController<SafetyOverview> controller) {
    if (controller.isLoading && controller.data == null) {
      return const _SafetyLoading();
    }
    if (controller.data == null) {
      return _SafetyUnavailable(
        message: controller.error?.message ??
            'Pandora has not returned a verified safety state yet.',
        onRetry: controller.load,
      );
    }

    final safety = controller.data!;
    final groups = _groupSafetyItems(safety.sections);
    final attention = groups
        .expand((group) => group.items)
        .where((item) => _truth(item.status).isAttention)
        .length;
    final blocked = groups
        .expand((group) => group.items)
        .where((item) => _truth(item.status) == _SimpleTruth.blocked)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SafetyHero(
          auditValid: safety.auditChain.valid,
          auditLabel: safety.auditChain.label,
          attention: attention,
          blocked: blocked,
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 14),
          const _InlineNotice(
            message:
                'Fresh verification failed. Showing the last verified state where available.',
          ),
        ],
        const SizedBox(height: 26),
        const PandoraSectionTitle(
          title: 'Four protection layers',
          meta: 'No aggregate score',
        ),
        const Text(
          'Each claim stands on its own evidence. Missing proof stays visibly unverified.',
          style: TextStyle(
            color: PandoraSimpleColors.muted,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < groups.length; index++) ...[
          _SafetyGroupCard(group: groups[index]),
          if (index != groups.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 26),
        PandoraSimpleCard(
          backgroundColor: PandoraSimpleColors.blueWash,
          borderColor: const Color(0xFFDCE6FA),
          shadow: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PandoraIconBadge(
                icon: Icons.info_outline_rounded,
                foreground: PandoraSimpleColors.blue,
                background: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Technical diagnostics stay out of the way',
                      style: TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      safety.extraIdentityCheckAdvertised
                          ? 'The live provider currently advertises an extra identity check. Pandora keeps that requirement explicit instead of silently bypassing it.'
                          : 'Simple Mode shows business-safe conclusions here. Detailed provider diagnostics remain in Professional Mode under More.',
                      style: const TextStyle(
                        color: PandoraSimpleColors.muted,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyHero extends StatelessWidget {
  const _SafetyHero({
    required this.auditValid,
    required this.auditLabel,
    required this.attention,
    required this.blocked,
  });

  final bool auditValid;
  final String auditLabel;
  final int attention;
  final int blocked;

  @override
  Widget build(BuildContext context) {
    final healthy = auditValid && attention == 0 && blocked == 0;
    final foreground = blocked > 0
        ? PandoraSimpleColors.deepRed
        : attention > 0
            ? PandoraSimpleColors.amber
            : PandoraSimpleColors.green;
    final background = blocked > 0
        ? PandoraSimpleColors.blush
        : attention > 0
            ? PandoraSimpleColors.amberWash
            : PandoraSimpleColors.greenWash;
    final title = blocked > 0
        ? 'Protection is blocked'
        : attention > 0 || !auditValid
            ? 'Some protection needs attention'
            : 'Your protection is healthy';
    final message = healthy
        ? 'Pandora can verify the current protection layers without hiding technical uncertainty.'
        : 'Review the items below before approving or relying on protected work.';

    return PandoraSimpleCard(
      backgroundColor: background,
      borderColor: foreground.withValues(alpha: .16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PandoraIconBadge(
                icon: blocked > 0
                    ? Icons.gpp_bad_outlined
                    : attention > 0 || !auditValid
                        ? Icons.gpp_maybe_outlined
                        : Icons.verified_user_outlined,
                foreground: foreground,
                background: Colors.white,
                size: 50,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      message,
                      style: const TextStyle(
                        color: PandoraSimpleColors.muted,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PandoraStatusPill(
                label: auditLabel,
                icon: auditValid
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                foreground: auditValid
                    ? PandoraSimpleColors.green
                    : PandoraSimpleColors.deepRed,
                background: Colors.white,
              ),
              if (attention > 0)
                PandoraStatusPill(
                  label: '$attention need attention',
                  icon: Icons.warning_amber_rounded,
                  foreground: PandoraSimpleColors.amber,
                  background: Colors.white,
                ),
              if (blocked > 0)
                PandoraStatusPill(
                  label: '$blocked blocked',
                  icon: Icons.block_rounded,
                  foreground: PandoraSimpleColors.deepRed,
                  background: Colors.white,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyGroupCard extends StatelessWidget {
  const _SafetyGroupCard({required this.group});

  final _SimpleSafetyGroup group;

  @override
  Widget build(BuildContext context) {
    final summary = _groupTruth(group.items);
    return PandoraSimpleCard(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PandoraIconBadge(
                icon: group.icon,
                foreground: _truthForeground(summary),
                background: _truthBackground(summary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _TruthPill(truth: summary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.description,
            style: const TextStyle(
              color: PandoraSimpleColors.muted,
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < group.items.length; index++) ...[
            _SafetyItemRow(item: group.items[index]),
            if (index != group.items.length - 1)
              const Divider(height: 20, color: PandoraSimpleColors.line),
          ],
        ],
      ),
    );
  }
}

class _SafetyItemRow extends StatelessWidget {
  const _SafetyItemRow({required this.item});
  final SafetyItem item;

  @override
  Widget build(BuildContext context) {
    final truth = _truth(item.status);
    return Semantics(
      label: '${item.title}: ${truth.label}. ${item.explanation}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              _truthIcon(truth),
              size: 19,
              color: _truthForeground(truth),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.explanation,
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 12.8,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TruthPill(truth: truth),
        ],
      ),
    );
  }
}

class _TruthPill extends StatelessWidget {
  const _TruthPill({required this.truth});
  final _SimpleTruth truth;

  @override
  Widget build(BuildContext context) => PandoraStatusPill(
        label: truth.label,
        icon: _truthIcon(truth),
        foreground: _truthForeground(truth),
        background: _truthBackground(truth),
      );
}

class _SafetyLoading extends StatelessWidget {
  const _SafetyLoading();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            const PandoraSimpleCard(
              shadow: false,
              child: SizedBox(
                height: 76,
                child: Center(child: LinearProgressIndicator()),
              ),
            ),
            if (i != 3) const SizedBox(height: 12),
          ],
        ],
      );
}

class _SafetyUnavailable extends StatelessWidget {
  const _SafetyUnavailable({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        backgroundColor: PandoraSimpleColors.amberWash,
        borderColor: const Color(0xFFF1D3A8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PandoraIconBadge(
              icon: Icons.shield_outlined,
              foreground: PandoraSimpleColors.amber,
              background: Colors.white,
              size: 52,
            ),
            const SizedBox(height: 12),
            const Text(
              'Safety is not verified',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                color: PandoraSimpleColors.muted,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            PandoraPrimaryButton(
              label: 'Check again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
              expanded: true,
            ),
          ],
        ),
      );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        backgroundColor: PandoraSimpleColors.amberWash,
        borderColor: const Color(0xFFF1D3A8),
        shadow: false,
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: PandoraSimpleColors.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}

List<_SimpleSafetyGroup> _groupSafetyItems(List<SafetySection> sections) {
  final buckets = <_SafetyBucket, List<SafetyItem>>{
    for (final bucket in _SafetyBucket.values) bucket: <SafetyItem>[],
  };
  for (final item in sections.expand((section) => section.items)) {
    buckets[_bucketFor(item)]!.add(item);
  }
  return _SafetyBucket.values.map((bucket) {
    final items = buckets[bucket]!;
    if (items.isEmpty) {
      items.add(
        SafetyItem.fromJson(<String, Object?>{
          'id': 'simple-${bucket.name}-not-checked',
          'title': 'Evidence not returned',
          'plainStatus': 'Not checked',
          'explanation':
              'Pandora did not return a verified claim for this protection layer.',
        }),
      );
    }
    return _SimpleSafetyGroup(
      title: bucket.title,
      description: bucket.description,
      icon: bucket.icon,
      items: List<SafetyItem>.unmodifiable(items),
    );
  }).toList(growable: false);
}

_SafetyBucket _bucketFor(SafetyItem item) {
  final haystack = '${item.id} ${item.title} ${item.explanation}'.toLowerCase();
  if (_containsAny(haystack, const [
    'approval',
    'execute',
    'execution',
    'plan',
    'audit',
    'decision',
    'rollback',
  ])) {
    return _SafetyBucket.approvalExecution;
  }
  if (_containsAny(haystack, const [
    'source',
    'github',
    'repository',
    'repo',
    'commit',
    'sha',
    'deployment',
    'vercel',
  ])) {
    return _SafetyBucket.sourceAuthority;
  }
  if (_containsAny(haystack, const [
    'identity',
    'auth',
    'access',
    'owner',
    'session',
    'account',
    'permission',
  ])) {
    return _SafetyBucket.identityAccess;
  }
  return _SafetyBucket.runtimeSecrets;
}

bool _containsAny(String source, List<String> terms) =>
    terms.any(source.contains);

enum _SafetyBucket {
  identityAccess(
    'Identity & Access',
    'Who can act, which identity is active, and whether access is verified.',
    Icons.badge_outlined,
  ),
  approvalExecution(
    'Approval & Execution',
    'Whether decisions, execution boundaries, audit integrity, and recovery are protected.',
    Icons.fact_check_outlined,
  ),
  sourceAuthority(
    'Source Authority',
    'Whether code, repository identity, deployment source, and exact SHA remain bound.',
    Icons.account_tree_outlined,
  ),
  runtimeSecrets(
    'Runtime & Secrets',
    'Whether runtime services and secret boundaries are healthy without exposing credentials.',
    Icons.lock_outline_rounded,
  );

  const _SafetyBucket(this.title, this.description, this.icon);
  final String title;
  final String description;
  final IconData icon;
}

class _SimpleSafetyGroup {
  const _SimpleSafetyGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.items,
  });
  final String title;
  final String description;
  final IconData icon;
  final List<SafetyItem> items;
}

enum _SimpleTruth {
  healthy('Healthy'),
  attention('Needs attention'),
  blocked('Blocked'),
  notChecked('Not checked'),
  notApplicable('Not applicable');

  const _SimpleTruth(this.label);
  final String label;
  bool get isAttention =>
      this == _SimpleTruth.attention || this == _SimpleTruth.blocked;
}

_SimpleTruth _truth(String status) {
  final value = status.trim().toLowerCase().replaceAll('_', ' ');
  if (value.contains('not applicable') || value.contains('not configured')) {
    return _SimpleTruth.notApplicable;
  }
  if (value.contains('block') ||
      value.contains('critical') ||
      value.contains('failed') ||
      value.contains('down') ||
      value.contains('unhealthy') ||
      value.contains('invalid')) {
    return _SimpleTruth.blocked;
  }
  if (value.contains('attention') ||
      value.contains('degraded') ||
      value.contains('warning') ||
      value.contains('stale') ||
      value.contains('partial')) {
    return _SimpleTruth.attention;
  }
  if (value.contains('healthy') ||
      value.contains('verified') ||
      value.contains('ready') ||
      value.contains('connected') ||
      value.contains('valid') ||
      value.contains('protected') ||
      value.contains('active')) {
    return _SimpleTruth.healthy;
  }
  return _SimpleTruth.notChecked;
}

_SimpleTruth _groupTruth(List<SafetyItem> items) {
  final truths =
      items.map((item) => _truth(item.status)).toList(growable: false);
  if (truths.contains(_SimpleTruth.blocked)) {
    return _SimpleTruth.blocked;
  }
  if (truths.contains(_SimpleTruth.attention)) {
    return _SimpleTruth.attention;
  }
  if (truths.contains(_SimpleTruth.notChecked)) {
    return _SimpleTruth.notChecked;
  }
  if (truths.every((truth) => truth == _SimpleTruth.notApplicable)) {
    return _SimpleTruth.notApplicable;
  }
  return _SimpleTruth.healthy;
}

Color _truthForeground(_SimpleTruth truth) => switch (truth) {
      _SimpleTruth.healthy => PandoraSimpleColors.green,
      _SimpleTruth.attention => PandoraSimpleColors.amber,
      _SimpleTruth.blocked => PandoraSimpleColors.deepRed,
      _SimpleTruth.notChecked => PandoraSimpleColors.muted,
      _SimpleTruth.notApplicable => PandoraSimpleColors.blue,
    };

Color _truthBackground(_SimpleTruth truth) => switch (truth) {
      _SimpleTruth.healthy => PandoraSimpleColors.greenWash,
      _SimpleTruth.attention => PandoraSimpleColors.amberWash,
      _SimpleTruth.blocked => PandoraSimpleColors.blush,
      _SimpleTruth.notChecked => const Color(0xFFF2F1EF),
      _SimpleTruth.notApplicable => PandoraSimpleColors.blueWash,
    };

IconData _truthIcon(_SimpleTruth truth) => switch (truth) {
      _SimpleTruth.healthy => Icons.check_circle_outline_rounded,
      _SimpleTruth.attention => Icons.warning_amber_rounded,
      _SimpleTruth.blocked => Icons.block_rounded,
      _SimpleTruth.notChecked => Icons.help_outline_rounded,
      _SimpleTruth.notApplicable => Icons.remove_circle_outline_rounded,
    };

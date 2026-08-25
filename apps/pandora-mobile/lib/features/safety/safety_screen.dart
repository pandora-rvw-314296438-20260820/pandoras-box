import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
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
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: 'Safety',
      subtitle: 'Authorization, audit integrity, source authority, and runtime health.',
      actions: [
        IconButton(
          tooltip: 'Refresh Safety',
          onPressed: () => _controller?.refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      onRefresh: () => _controller!.refresh(),
      child: AnimatedBuilder(
        animation: _controller!,
        builder: (context, _) {
          final controller = _controller!;
          if (controller.isLoading && controller.data == null) {
            return const ContentSkeleton(lines: 7);
          }
          if (controller.error != null && controller.data == null) {
            return ErrorContent(
              title: 'Safety could not be checked',
              message: controller.error!.message,
              onRetry: controller.load,
            );
          }
          final safety = controller.data;
          if (safety == null) {
            return const EmptyContent(
              title: 'Safety not checked',
              message: 'Pandora returned no verified safety state.',
            );
          }
          final items = safety.sections
              .expand((section) => section.items)
              .toList(growable: false);
          final healthy = items
              .where(
                (item) =>
                    statusToneFor(item.status) == PandoraStatusTone.verified,
              )
              .length;
          final attention = items
              .where(
                (item) =>
                    statusToneFor(item.status) == PandoraStatusTone.attention ||
                    statusToneFor(item.status) == PandoraStatusTone.critical,
              )
              .length;
          final unchecked = items.length - healthy - attention;
          final heroTone = !safety.auditChain.valid
              ? PandoraStatusTone.critical
              : attention > 0
              ? PandoraStatusTone.attention
              : statusToneFor(safety.state);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.error != null) ...[
                DegradedContentNotice(
                  message: controller.error!.message,
                  onRetry: controller.refresh,
                ),
                const SizedBox(height: PandoraSpacing.md),
              ],
              OwnerBriefingHero(
                eyebrow: 'Current safety posture',
                title: safety.status,
                message: safety.auditChain.valid
                    ? 'The audit chain is verified. Individual checks below remain evidence-based and separate.'
                    : 'The audit chain needs attention. Treat protected operations as blocked until it is verified.',
                icon: safety.auditChain.valid
                    ? Icons.shield_outlined
                    : Icons.gpp_bad_outlined,
                tone: heroTone,
                statusLabel: safety.auditChain.label,
                footer: safety.auditChain.checkedAt == null
                    ? const Text('Audit check time not verified')
                    : Text(
                        'Checked ${ownerRelativeTime(safety.auditChain.checkedAt)}',
                      ),
              ),
              const SizedBox(height: PandoraSpacing.md),
              OwnerMetricGrid(
                metrics: [
                  OwnerMetric(
                    label: 'Healthy',
                    value: '$healthy',
                    icon: Icons.check_circle_outline_rounded,
                    tone: PandoraStatusTone.verified,
                  ),
                  OwnerMetric(
                    label: 'Needs attention',
                    value: '$attention',
                    icon: Icons.warning_amber_rounded,
                    tone: attention > 0
                        ? PandoraStatusTone.attention
                        : PandoraStatusTone.neutral,
                  ),
                  OwnerMetric(
                    label: 'Not checked',
                    value: '$unchecked',
                    icon: Icons.help_outline_rounded,
                    tone: unchecked > 0
                        ? PandoraStatusTone.attention
                        : PandoraStatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: PandoraSpacing.xl),
              const OwnerSectionHeading(
                title: 'Safety checks',
                subtitle: 'No aggregate score: each claim stands on its own evidence.',
              ),
              for (final section in safety.sections) ...[
                const SizedBox(height: PandoraSpacing.sm),
                _SafetySectionCard(section: section),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _SafetySectionCard extends StatelessWidget {
  const _SafetySectionCard({required this.section});

  final SafetySection section;

  @override
  Widget build(BuildContext context) {
    final items = List<SafetyItem>.of(section.items)
      ..sort(
        (left, right) => _attentionRank(right).compareTo(_attentionRank(left)),
      );
    return PandoraSurface(
      title: section.title,
      child: items.isEmpty
          ? const Text('No checks were returned for this section.')
          : Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(providerIconFor(items[index].title)),
                    title: Text(items[index].title),
                    subtitle: Text(items[index].explanation),
                    trailing: StatusBadge(
                      label: items[index].status,
                      tone: statusToneFor(items[index].status),
                      compact: true,
                    ),
                  ),
                  if (index != items.length - 1) const Divider(),
                ],
              ],
            ),
    );
  }
}

int _attentionRank(SafetyItem item) {
  return switch (statusToneFor(item.status)) {
    PandoraStatusTone.critical => 4,
    PandoraStatusTone.attention => 3,
    PandoraStatusTone.neutral => 2,
    PandoraStatusTone.informative => 1,
    PandoraStatusTone.verified => 0,
  };
}

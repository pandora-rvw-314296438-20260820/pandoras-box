import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/freshness_label.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';
import '../simple/ask_pandora_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  ScreenController<List<ConnectionSummary>>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<ConnectionSummary>>(
      () => repository.connections(allowCached: true),
    )..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: 'Connections',
      subtitle: 'Provider health, capability, and verified freshness.',
      actions: [
        IconButton(
          tooltip: 'Refresh Connections',
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
            return const ContentSkeleton(lines: 6);
          }
          if (controller.error != null && controller.data == null) {
            return ErrorContent(
              title: 'Connections could not load',
              message: controller.error!.message,
              onRetry: controller.load,
            );
          }
          final raw = controller.data ?? const <ConnectionSummary>[];
          final items = deduplicateConnections(raw);
          if (items.isEmpty) {
            return const EmptyContent(
              title: 'No connections returned',
              message: 'Pandora has not returned a verified connection list.',
            );
          }
          final changeReady = items
              .where(
                (connection) =>
                    resolveOwnerConnectionState(connection) ==
                        OwnerConnectionState.verified &&
                    connection.canChange,
              )
              .length;
          final needsAttention = items.where((connection) {
            final state = resolveOwnerConnectionState(connection);
            return state == OwnerConnectionState.needsAttention ||
                state == OwnerConnectionState.stale ||
                state == OwnerConnectionState.capabilityUnverified;
          }).length;
          final healthy = items
              .where(
                (connection) =>
                    resolveOwnerConnectionState(connection) ==
                    OwnerConnectionState.verified,
              )
              .length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.degradedReason != null ||
                  controller.error != null) ...[
                DegradedContentNotice(
                  message:
                      controller.degradedReason ?? controller.error!.message,
                  onRetry: controller.refresh,
                ),
                const SizedBox(height: PandoraSpacing.md),
              ],
              OwnerBriefingHero(
                eyebrow: 'Provider posture',
                title: needsAttention == 0
                    ? 'Connected services are ready'
                    : '$needsAttention connection${needsAttention == 1 ? '' : 's'} need attention',
                message: 'Capabilities are shown without exposing credentials or secret values.',
                icon: needsAttention == 0
                    ? Icons.cable_rounded
                    : Icons.warning_amber_rounded,
                tone: needsAttention == 0
                    ? PandoraStatusTone.verified
                    : PandoraStatusTone.attention,
                statusLabel: raw.length == items.length
                    ? '${items.length} providers'
                    : '${items.length} unique providers · ${raw.length - items.length} duplicate record${raw.length - items.length == 1 ? '' : 's'} collapsed',
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
                    label: 'Change-ready',
                    value: '$changeReady',
                    icon: Icons.edit_note_rounded,
                    tone: PandoraStatusTone.informative,
                  ),
                  OwnerMetric(
                    label: 'Needs attention',
                    value: '$needsAttention',
                    icon: Icons.warning_amber_rounded,
                    tone: needsAttention > 0
                        ? PandoraStatusTone.attention
                        : PandoraStatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: PandoraSpacing.xl),
              const OwnerSectionHeading(
                title: 'Connected services',
                subtitle: 'Attention-first, with capability and freshness.',
              ),
              const SizedBox(height: PandoraSpacing.sm),
              for (var index = 0; index < items.length; index++) ...[
                _ConnectionCard(
                  connection: items[index],
                  onTest: controller.refresh,
                  onAction: (action) => _openGovernedConnectionAction(
                    context,
                    items[index],
                    action,
                  ),
                ),
                if (index != items.length - 1)
                  const SizedBox(height: PandoraSpacing.sm),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.onTest,
    required this.onAction,
  });

  final ConnectionSummary connection;
  final VoidCallback onTest;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final ownerState = resolveOwnerConnectionState(connection);
    final needsReconnect =
        ownerState == OwnerConnectionState.needsAttention ||
        ownerState == OwnerConnectionState.stale;
    final primaryAction = ownerState == OwnerConnectionState.legacy
        ? 'Review'
        : ownerState == OwnerConnectionState.capabilityUnverified
        ? 'Verify'
        : !connection.canRead
        ? 'Connect'
        : needsReconnect
        ? 'Reconnect'
        : 'Manage';
    return PandoraSurface(
      title: connection.name,
      subtitle: connection.purpose,
      leading: Icon(providerIconFor(connection.name)),
      trailing: StatusBadge(
        label: ownerState.label,
        tone: ownerState == OwnerConnectionState.verified
            ? PandoraStatusTone.verified
            : ownerState == OwnerConnectionState.legacy
            ? PandoraStatusTone.neutral
            : PandoraStatusTone.attention,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OwnerSignal(
            label: 'Verified capability',
            value: ownerConnectionCapabilityLabel(connection),
            icon: connection.canChange
                ? Icons.edit_note_rounded
                : connection.canRead
                ? Icons.visibility_outlined
                : Icons.link_off_rounded,
            tone: connection.canChange || connection.canRead
                ? PandoraStatusTone.informative
                : PandoraStatusTone.attention,
          ),
          const SizedBox(height: PandoraSpacing.sm),
          FreshnessLabel(freshness: connection.freshness),
          const SizedBox(height: PandoraSpacing.md),
          Wrap(
            spacing: PandoraSpacing.xs,
            runSpacing: PandoraSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: onTest,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Test now'),
              ),
              FilledButton.icon(
                onPressed: () => onAction(primaryAction),
                icon: Icon(
                  primaryAction == 'Connect'
                      ? Icons.add_link_rounded
                      : primaryAction == 'Reconnect'
                      ? Icons.sync_rounded
                      : primaryAction == 'Verify'
                      ? Icons.fact_check_outlined
                      : primaryAction == 'Review'
                      ? Icons.history_rounded
                      : Icons.tune_rounded,
                ),
                label: Text(primaryAction),
              ),
              if (connection.canRead)
                TextButton.icon(
                  onPressed: () => onAction('Disconnect'),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

void _openGovernedConnectionAction(
  BuildContext context,
  ConnectionSummary connection,
  String action,
) {
  final verb = action.toLowerCase();
  final prompt = verb == 'disconnect'
      ? 'Disconnect ${connection.name}. Verify the impact, affected systems, rollback path, and current provider state first. Prepare the governed change for my approval; do not execute it just because I asked.'
      : verb == 'connect'
      ? 'Connect ${connection.name}. Verify the required scopes and provider health first, then prepare the governed connection for my approval.'
      : verb == 'reconnect'
      ? 'Reconnect ${connection.name}. Test the current connection and credentials first, then prepare only the necessary governed repair for my approval.'
      : verb == 'verify'
      ? 'Verify ${connection.name}. Check the live provider state and current capabilities. Do not treat an old credential or stale record as proof of access.'
      : verb == 'review'
      ? 'Review the legacy ${connection.name} record. Confirm whether it is still used by the current Pandora architecture before proposing any change.'
      : 'Review and manage ${connection.name}. Test its current health and capabilities, then show me any governed change that needs my approval.';
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AskPandoraScreen(initialPrompt: prompt),
    ),
  );
}

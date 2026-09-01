import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

class SimpleBusinessScreen extends StatefulWidget {
  const SimpleBusinessScreen({super.key});

  @override
  State<SimpleBusinessScreen> createState() => _SimpleBusinessScreenState();
}

class _SimpleBusinessScreenState extends State<SimpleBusinessScreen> {
  bool _loading = true;
  String? _error;
  List<ProjectSummary> _projects = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _projects.isEmpty) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await PandoraDependencies.of(context)
          .repository
          .projects(allowCached: true);
      if (!mounted) return;
      setState(() {
        _projects =
            snapshot.data.where(isOwnerVisibleProject).toList(growable: false);
        _loading = false;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora could not load your business view.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _projects
        .where(
          (project) =>
              project.evidenceState(EvidenceStage.productionVerified) ==
                  EvidenceClaimState.verified &&
              project.freshness.isFresh,
        )
        .length;
    final needsYou = _projects
        .where((project) => project.blocker?.trim().isNotEmpty == true)
        .length;
    final working = (_projects.length - live - needsYou).clamp(
      0,
      _projects.length,
    );

    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: 'Business',
        subtitle: 'What Pandora is producing for your business.',
        onNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen()),
        ),
        onAvatar: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      ),
      onRefresh: _load,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(
                  color: PandoraSimpleColors.red,
                ),
              ),
            )
          : _error != null
              ? PandoraSimpleCard(
                  shadow: false,
                  backgroundColor: const Color(0xFFFFF4F5),
                  borderColor: const Color(0xFFF0C3CA),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _error!,
                        style:
                            const TextStyle(color: PandoraSimpleColors.deepRed),
                      ),
                      const SizedBox(height: 12),
                      PandoraSecondaryButton(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        onPressed: _load,
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Business pulse',
                      style: TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'A simple view of what is live, what Pandora is working on, and what needs you.',
                      style: pandoraSimpleMutedText,
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final items = <Widget>[
                          _PulseCard(
                            label: 'Live',
                            value: '$live',
                            icon: Icons.public_rounded,
                            foreground: PandoraSimpleColors.green,
                            background: PandoraSimpleColors.greenWash,
                          ),
                          _PulseCard(
                            label: 'Working',
                            value: '$working',
                            icon: Icons.auto_awesome_rounded,
                            foreground: PandoraSimpleColors.blue,
                            background: PandoraSimpleColors.blueWash,
                          ),
                          _PulseCard(
                            label: 'Needs You',
                            value: '$needsYou',
                            icon: Icons.priority_high_rounded,
                            foreground: PandoraSimpleColors.amber,
                            background: PandoraSimpleColors.amberWash,
                          ),
                        ];
                        if (constraints.maxWidth < 620) {
                          return Column(
                            children: [
                              for (var i = 0; i < items.length; i++) ...[
                                items[i],
                                if (i < items.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              Expanded(child: items[i]),
                              if (i < items.length - 1)
                                const SizedBox(width: 10),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    const PandoraSectionTitle(title: 'Current outcomes'),
                    if (_projects.isEmpty)
                      const PandoraSimpleCard(
                        shadow: false,
                        child: Text(
                          'No customer projects are visible yet. Create a Project and Pandora will track its result here.',
                          style: pandoraSimpleMutedText,
                        ),
                      )
                    else
                      for (final project in _projects.take(8))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: PandoraSimpleCard(
                            shadow: false,
                            child: Row(
                              children: [
                                const PandoraIconBadge(
                                  icon: Icons.insights_outlined,
                                  foreground: PandoraSimpleColors.purple,
                                  background: PandoraSimpleColors.purpleWash,
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        canonicalOwnerProjectLabel(project),
                                        style: const TextStyle(
                                          color: PandoraSimpleColors.ink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        project.purpose,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: pandoraSimpleMutedText,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        shadow: false,
        child: Row(
          children: [
            PandoraIconBadge(
              icon: icon,
              foreground: foreground,
              background: background,
              size: 48,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label, style: pandoraSimpleMutedText),
              ],
            ),
          ],
        ),
      );
}

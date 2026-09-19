import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';
import 'enterprise_command_bus.dart';
import 'enterprise_vision_embed.dart';

class EnterpriseVisionScreen extends StatelessWidget {
  const EnterpriseVisionScreen({super.key});

  static final Uri _sourceUri = Uri.parse(
    'https://webcamlivestream.com/japan/tokyo/shibuya-ai-vision-miyamasuzaka/',
  );

  void _askPandora(BuildContext context) {
    EnterpriseCommandDraftBus.shared.offer(
      'Explain the Vision Intelligence capability shown on this page. '
      'The live Shibuya feed is display-only in this build: do not claim '
      'Pandora is analyzing, identifying, tracking, retaining, or alerting '
      'on people or objects in this public feed. Explain what becomes '
      'available when an enterprise connects a camera it is authorized to use.',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vision Intelligence context added to Pandora.'),
      ),
    );
  }

  Future<void> _openSource() async {
    await launchUrl(_sourceUri);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Vision Intelligence',
        subtitle:
            'Live camera awareness and incident review for authorized enterprise environments.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _intro(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 920;
                final camera = _camera(context);
                final status = _feedStatus(context);
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      camera,
                      const SizedBox(height: 14),
                      status,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: camera),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: status),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _capabilities(),
            const SizedBox(height: 20),
            _architecture(),
          ],
        ),
      );

  Widget _intro() => PandoraSurface(
        title: 'Live Vision Feed',
        subtitle: 'Shibuya · Tokyo, Japan',
        leading: const Icon(Icons.videocam_rounded),
        child: const Text(
          'A live Shibuya intersection camera provides continuous pedestrian and vehicle '
          'activity inside Pandora Enterprise. Automated analysis is '
          'not connected to this public source.',
          style: TextStyle(
            color: PandoraV2Colors.muted,
            height: 1.45,
          ),
        ),
      );

  Widget _camera(BuildContext context) => PandoraSurface(
        title: 'Live camera',
        subtitle: 'Shibuya Ai Vision · live channel feed',
        leading: const Icon(Icons.live_tv_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF111111),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildEnterpriseVisionEmbed(),
                      Align(
                        alignment: Alignment.topLeft,
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xD9111111),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Color(0xFFF04B45),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'LIVE SHIBUYA',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .55,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Source: Shibuya Ai Vision Miyamasuzaka · live public urban camera. '
              '',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _openSource,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open live source'),
                ),
                FilledButton.icon(
                  onPressed: () => _askPandora(context),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Ask Pandora'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _feedStatus(BuildContext context) => PandoraSurface(
        title: 'Live feed status',
        subtitle: 'Current live source and analysis state',
        leading: const Icon(Icons.verified_user_outlined),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VisionStatusRow(
              icon: Icons.public_rounded,
              label: 'Live source',
              value: 'Shibuya Ai Vision',
            ),
            SizedBox(height: 12),
            _VisionStatusRow(
              icon: Icons.psychology_alt_outlined,
              label: 'AI analysis',
              value: 'Not connected to public source',
            ),
            SizedBox(height: 12),
            _VisionStatusRow(
              icon: Icons.person_search_outlined,
              label: 'Biometrics',
              value: 'Off',
            ),
            SizedBox(height: 12),
            _VisionStatusRow(
              icon: Icons.inventory_2_outlined,
              label: 'Pandora retention',
              value: 'None',
            ),
            SizedBox(height: 14),
            Divider(height: 1),
            SizedBox(height: 14),
            Text(
              'When an authorized enterprise camera is connected, Pandora can '
              'enable governed detection, search, timelines and incident review '
              'under that customer’s configured policy.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      );

  Widget _capabilities() => PandoraSurface(
        title: 'What Vision Intelligence adds',
        subtitle: 'Available for enterprise-owned or otherwise authorized cameras',
        leading: const Icon(Icons.visibility_outlined),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 840
                ? 3
                : width >= 520
                    ? 2
                    : 1;
            final cardWidth =
                (width - ((columns - 1) * 10)) / columns;
            const capabilities = <_VisionCapability>[
              _VisionCapability(
                Icons.manage_search_rounded,
                'Search footage',
                'Ask for moments, objects, vehicles or events instead of '
                    'scrubbing through hours of video.',
              ),
              _VisionCapability(
                Icons.center_focus_strong_rounded,
                'Detect & review',
                'Generate machine observations for configured objects and '
                    'zones, then keep human verification explicit.',
              ),
              _VisionCapability(
                Icons.timeline_rounded,
                'Build timelines',
                'Turn relevant camera events into a chronological incident '
                    'view with source timestamps.',
              ),
              _VisionCapability(
                Icons.content_cut_rounded,
                'Extract clips',
                'Save the relevant interval while keeping the original source '
                    'and provenance separate.',
              ),
              _VisionCapability(
                Icons.notifications_active_outlined,
                'Operational alerts',
                'Apply customer-defined rules to authorized feeds and surface '
                    'events that need attention.',
              ),
              _VisionCapability(
                Icons.auto_awesome_rounded,
                'Pandora Chat',
                'Query verified camera events naturally from the same '
                    'Enterprise workspace.',
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final capability in capabilities)
                  SizedBox(
                    width: cardWidth,
                    child: _VisionCapabilityCard(capability: capability),
                  ),
              ],
            );
          },
        ),
      );

  Widget _architecture() => PandoraSurface(
        title: 'Enterprise camera path',
        subtitle: 'Live Shibuya feed now · governed customer ingest next',
        leading: const Icon(Icons.account_tree_outlined),
        child: const Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _VisionPathChip(
              icon: Icons.videocam_outlined,
              label: 'Camera / NVR',
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: PandoraV2Colors.muted,
            ),
            _VisionPathChip(
              icon: Icons.memory_rounded,
              label: 'Edge / ingest',
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: PandoraV2Colors.muted,
            ),
            _VisionPathChip(
              icon: Icons.visibility_rounded,
              label: 'Vision events',
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: PandoraV2Colors.muted,
            ),
            _VisionPathChip(
              icon: Icons.auto_awesome_rounded,
              label: 'Pandora',
            ),
          ],
        ),
      );
}

class _VisionStatusRow extends StatelessWidget {
  const _VisionStatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: PandoraV2Colors.ink),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _VisionCapability {
  const _VisionCapability(this.icon, this.title, this.description);

  final IconData icon;
  final String title;
  final String description;
}

class _VisionCapabilityCard extends StatelessWidget {
  const _VisionCapabilityCard({required this.capability});

  final _VisionCapability capability;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 146),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(capability.icon, size: 22),
            const SizedBox(height: 10),
            Text(
              capability.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              capability.description,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _VisionPathChip extends StatelessWidget {
  const _VisionPathChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

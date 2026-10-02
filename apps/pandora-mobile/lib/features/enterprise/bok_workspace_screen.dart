import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';
import 'enterprise_workspace_home.dart';

class BokWorkspaceScreen extends StatelessWidget {
  const BokWorkspaceScreen({
    super.key,
    required this.workspace,
    required this.section,
  });

  final EnterpriseWorkspaceProfile workspace;
  final EnterpriseWorkspaceSection section;

  @override
  Widget build(BuildContext context) {
    final openDrawer = PandoraNavigationScope.maybeOf(context)?.openDrawer;
    return ColoredBox(
      key: ValueKey<String>('bok-workspace-' + section.routeSlug),
      color: const Color(0xFF0D0B09),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Row(
              children: [
                if (openDrawer != null)
                  IconButton(
                    tooltip: 'Navigation',
                    onPressed: openDrawer,
                    icon: const Icon(Icons.menu_rounded),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    section.label,
                    style: const TextStyle(
                      color: Color(0xFFF4EFE7),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17130F),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF342B22)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operational workspace',
                    style: TextStyle(
                      color: Color(0xFFF4EFE7),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No provider-backed BOK business dataset is connected for this section yet. Pandora will keep operational values unknown rather than inventing zeroes.',
                    style: TextStyle(
                      color: Color(0xFFB9AA99),
                      height: 1.4,
                    ),
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

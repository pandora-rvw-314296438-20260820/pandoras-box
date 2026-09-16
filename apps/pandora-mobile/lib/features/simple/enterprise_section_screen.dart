import 'package:flutter/material.dart';

import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';

class EnterpriseSectionScreen extends StatelessWidget {
  const EnterpriseSectionScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.items = const <String>[],
  });

  final String title;
  final String description;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) => PandoraPage(
    title: title,
    subtitle: description,
    child: PandoraSurface(
      title: title,
      subtitle: 'Enterprise control panel',
      leading: Icon(icon),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            Text(
              'This section is ready for its provider-specific controls and data.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 6),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}

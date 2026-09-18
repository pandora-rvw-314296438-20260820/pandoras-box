import 'package:flutter/material.dart';

import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import 'eurofish_enterprise_command_bar.dart';

class EurofishSectionScreen extends StatelessWidget {
  const EurofishSectionScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.items,
    required this.suggestedPrompt,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<String> items;
  final String suggestedPrompt;

  @override
  Widget build(BuildContext context) => EurofishEnterprisePage(
        contextLabel: title,
        suggestedPrompt: suggestedPrompt,
        child: PandoraPage(
          title: title,
          subtitle: description,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _brandStrip(),
              const SizedBox(height: 14),
              PandoraSurface(
                title: title,
                subtitle: '1064 Euro-Fish Trading enterprise workspace',
                leading: Icon(icon, color: const Color(0xFFEAB308)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final item in items) _item(item)],
                ),
              ),
              const SizedBox(height: 14),
              _truthPanel(),
            ],
          ),
        ),
      );

  Widget _brandStrip() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A192F), Color(0xFF1E3A8A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x66EAB308)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xFFEAB308),
              child: Icon(Icons.set_meal_rounded, color: Color(0xFF0A192F)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1064 EURO-FISH TRADING',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Aquaculture • Floriculture • Import logistics',
                    style: TextStyle(color: Color(0xFFD7E3FF), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _item(String item) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: Color(0xFF60A5FA),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(item, style: const TextStyle(height: 1.4))),
          ],
        ),
      );

  Widget _truthPanel() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x334B5563)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 19, color: Color(0xFFEAB308)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'This lab does not invent live orders, stock, shipment, '
                'financial or compliance values. Pandora will surface those '
                'only after a verified business source is connected.',
                style: TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}

import 'package:flutter/material.dart';

import '../../core/data/project_experience_api.dart';
import 'pandora_v2_ui.dart';

class PandoraProfessionalBuildPlan extends StatelessWidget {
  const PandoraProfessionalBuildPlan({
    super.key,
    required this.understanding,
    this.showDeliveryPromise = true,
  });

  final OwnerProjectUnderstanding understanding;
  final bool showDeliveryPromise;

  String get _summary =>
      understanding.productPromise ??
      understanding.intentSummary ??
      understanding.businessSummary ??
      'Pandora has turned your request into a working product plan.';

  String? get _whyItMatters {
    final business = understanding.businessSummary?.trim();
    if (business == null || business.isEmpty || business == _summary.trim()) {
      return null;
    }
    return business;
  }

  String? get _audience {
    if (understanding.audiences.isNotEmpty) {
      return understanding.audiences.take(3).join(' · ');
    }
    final value = understanding.targetUsers?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get _productShape {
    final value = understanding.projectType?.trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'project') {
      return null;
    }
    final words = value
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    return words
        .asMap()
        .entries
        .map(
          (entry) => entry.key == 0
              ? '${entry.value[0].toUpperCase()}${entry.value.substring(1)}'
              : entry.value,
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final requirements =
        (understanding.firstVersionCapabilities.isNotEmpty
                ? understanding.firstVersionCapabilities
                : understanding.requirements)
            .take(7)
            .toList();
    final objectives =
        (understanding.successCriteria.isNotEmpty
                ? understanding.successCriteria
                : understanding.objectives)
            .take(4)
            .toList();
    final workflows = understanding.primaryWorkflows.take(5).toList();
    final experiences = understanding.coreExperiences.take(5).toList();
    final integrations = understanding.integrations.take(5).toList();
    final customerValue = understanding.customerValue?.trim();
    final ownerValue = understanding.ownerValue?.trim();
    final reviewAssurance = understanding.reviewAssurance?.trim();
    final whyItMatters = _whyItMatters;
    final audience = _audience;
    final productShape = _productShape;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface,
        border: Border.all(color: PandoraV2Colors.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PANDORA’S BUILD PLAN',
            style: TextStyle(
              color: PandoraV2Colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _summary,
            style: const TextStyle(
              color: PandoraV2Colors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -.45,
              height: 1.16,
            ),
          ),
          if (productShape != null || audience != null) ...[
            const SizedBox(height: 16),
            if (productShape != null)
              _PlanFact(label: 'Product', value: productShape),
            if (audience != null) ...[
              if (productShape != null) const SizedBox(height: 8),
              _PlanFact(label: 'Designed for', value: audience),
            ],
          ],
          if (customerValue != null && customerValue.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _PlanSectionTitle('For your customers'),
            const SizedBox(height: 8),
            Text(
              customerValue,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 15.5,
                height: 1.42,
              ),
            ),
          ],
          if (ownerValue != null && ownerValue.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _PlanSectionTitle('For you'),
            const SizedBox(height: 8),
            Text(
              ownerValue,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 15.5,
                height: 1.42,
              ),
            ),
          ] else if (whyItMatters != null) ...[
            const SizedBox(height: 22),
            const _PlanSectionTitle('Why this is worth building'),
            const SizedBox(height: 8),
            Text(
              whyItMatters,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 15.5,
                height: 1.42,
              ),
            ),
          ],
          if (requirements.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _PlanSectionTitle('Your first working version'),
            const SizedBox(height: 10),
            for (final requirement in requirements)
              _PlanBullet(text: requirement),
          ],
          if (experiences.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _PlanSectionTitle('Core experience'),
            const SizedBox(height: 10),
            for (final experience in experiences)
              _PlanBullet(text: experience),
          ],
          if (workflows.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _PlanSectionTitle('Main workflows'),
            const SizedBox(height: 10),
            for (final workflow in workflows)
              _PlanBullet(text: workflow),
          ],
          if (integrations.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _PlanSectionTitle('Connections'),
            const SizedBox(height: 10),
            for (final integration in integrations)
              _PlanBullet(text: integration),
          ],
          if (objectives.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _PlanSectionTitle('Success looks like'),
            const SizedBox(height: 10),
            for (final objective in objectives)
              _PlanBullet(text: objective, check: true),
          ],
          if (reviewAssurance != null && reviewAssurance.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _PlanSectionTitle('Before anything goes live'),
            const SizedBox(height: 8),
            Text(
              reviewAssurance,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
          if (showDeliveryPromise) ...[
            const SizedBox(height: 20),
            const Divider(height: 1, color: PandoraV2Colors.line),
            const SizedBox(height: 18),
            const _PlanSectionTitle('What happens when you tap Build it'),
            const SizedBox(height: 10),
            const _PlanDeliveryLine(
              icon: Icons.code_rounded,
              text: 'Pandora writes the real source code for this plan.',
            ),
            const _PlanDeliveryLine(
              icon: Icons.build_circle_outlined,
              text:
                  'It compiles and checks the working version before you review it.',
            ),
            const _PlanDeliveryLine(
              icon: Icons.visibility_outlined,
              text: 'You see the result before anything is published.',
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanSectionTitle extends StatelessWidget {
  const _PlanSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: PandoraV2Colors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -.1,
        ),
      );
}

class _PlanFact extends StatelessWidget {
  const _PlanFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
}

class _PlanBullet extends StatelessWidget {
  const _PlanBullet({required this.text, this.check = false});

  final String text;
  final bool check;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                check
                    ? Icons.check_circle_outline_rounded
                    : Icons.arrow_forward_rounded,
                size: 17,
                color: PandoraV2Colors.ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 15,
                  height: 1.38,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PlanDeliveryLine extends StatelessWidget {
  const _PlanDeliveryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: PandoraV2Colors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 14,
                  height: 1.38,
                ),
              ),
            ),
          ],
        ),
      );
}

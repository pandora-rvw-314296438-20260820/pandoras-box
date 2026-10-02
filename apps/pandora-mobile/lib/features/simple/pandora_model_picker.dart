import 'package:flutter/material.dart';

import '../../core/data/pandora_intelligence_api.dart';
import 'pandora_simple_ui.dart';

class PandoraModelPickerSheet extends StatelessWidget {
  const PandoraModelPickerSheet({
    super.key,
    required this.models,
    required this.selected,
    this.lastExecutedModel,
  });

  final List<PandoraIntelligenceModelCatalogEntry> models;
  final PandoraChatModelSelection selected;
  final String? lastExecutedModel;

  List<PandoraIntelligenceModelCatalogEntry> get _visibleModels {
    final result = <PandoraIntelligenceModelCatalogEntry>[
      const PandoraIntelligenceModelCatalogEntry.auto(),
    ];
    final seen = <String>{'auto:auto'};
    for (final model in models) {
      final key = '${model.provider}:${model.model}';
      if (seen.add(key) && !model.isAuto) result.add(model);
    }
    return result;
  }

  bool _selected(PandoraIntelligenceModelCatalogEntry model) =>
      model.isAuto
          ? selected.isAuto
          : !selected.isAuto &&
              selected.provider == model.provider &&
              selected.model == model.model;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .72;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        key: const ValueKey<String>('pandora-model-picker-sheet'),
        color: const Color(0xFF0B0B0B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3C),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Model',
                        style: TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Auto routes for you. Manual choices come from the live verified catalog; Pandora records the requested and executed model if a fallback is needed.',
                        style: TextStyle(
                          color: PandoraSimpleColors.muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      if (lastExecutedModel != null &&
                          lastExecutedModel!.trim().isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          'Last executed · ${lastExecutedModel!}',
                          style: const TextStyle(
                            color: Color(0xFFC8C8CC),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x1FFFFFFF)),
                Flexible(
                  child: ListView.builder(
                    key: const ValueKey<String>('pandora-model-picker-list'),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                    itemCount: _visibleModels.length,
                    itemBuilder: (context, index) {
                      final model = _visibleModels[index];
                      final active = _selected(model);
                      return _ModelPickerRow(
                        key: ValueKey<String>(
                          'pandora-model-option-${model.provider}-${model.model}',
                        ),
                        model: model,
                        selected: active,
                        onTap: model.available
                            ? () => Navigator.of(context).pop(model.selection)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PandoraReasoningPickerSheet extends StatelessWidget {
  const PandoraReasoningPickerSheet({
    super.key,
    required this.selected,
  });

  final PandoraIntelligenceMode selected;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          key: const ValueKey<String>('pandora-reasoning-picker-sheet'),
          color: const Color(0xFF0B0B0B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 14, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Reasoning',
                        style: TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  for (final mode in PandoraIntelligenceMode.values)
                    _ReasoningRow(
                      mode: mode,
                      selected: selected == mode,
                      onTap: () => Navigator.of(context).pop(mode),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  static String label(PandoraIntelligenceMode mode) => switch (mode) {
        PandoraIntelligenceMode.auto => 'Auto',
        PandoraIntelligenceMode.fast => 'Fast',
        PandoraIntelligenceMode.deep => 'Deep',
      };

  static String description(PandoraIntelligenceMode mode) => switch (mode) {
        PandoraIntelligenceMode.auto =>
          'Pandora chooses the right reasoning depth for the request.',
        PandoraIntelligenceMode.fast =>
          'Prefer faster responses for straightforward work.',
        PandoraIntelligenceMode.deep =>
          'Prefer deeper reasoning for complex work.',
      };
}

class _ModelPickerRow extends StatelessWidget {
  const _ModelPickerRow({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final PandoraIntelligenceModelCatalogEntry model;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = model.available;
    final subtitle = model.isAuto
        ? 'Pandora chooses the route for each turn.'
        : enabled
            ? '${model.providerLabel} · Probe verified'
            : '${model.providerLabel} · ${model.unavailableReason ?? 'Unavailable'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : .48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraSimpleColors.muted,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  color: PandoraSimpleColors.ink,
                  size: 20,
                )
              else if (!enabled)
                const Icon(
                  Icons.lock_outline_rounded,
                  color: PandoraSimpleColors.muted,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasoningRow extends StatelessWidget {
  const _ReasoningRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final PandoraIntelligenceMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(
            'pandora-reasoning-option-${mode.name}',
          ),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PandoraReasoningPickerSheet.label(mode),
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        PandoraReasoningPickerSheet.description(mode),
                        style: const TextStyle(
                          color: PandoraSimpleColors.muted,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    color: PandoraSimpleColors.ink,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
}

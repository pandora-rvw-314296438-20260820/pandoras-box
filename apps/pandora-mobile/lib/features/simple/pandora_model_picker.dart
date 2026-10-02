import 'package:flutter/material.dart';

import '../../core/data/pandora_intelligence_api.dart';

class PandoraComposerModelControls extends StatelessWidget {
  const PandoraComposerModelControls({
    super.key,
    required this.modelLabel,
    required this.reasoningMode,
    required this.enabled,
    required this.onModel,
    required this.onReasoning,
  });

  final String modelLabel;
  final PandoraIntelligenceMode reasoningMode;
  final bool enabled;
  final VoidCallback onModel;
  final VoidCallback onReasoning;

  String get _reasoningLabel => switch (reasoningMode) {
        PandoraIntelligenceMode.fast => 'Fast',
        PandoraIntelligenceMode.deep => 'Deep',
        PandoraIntelligenceMode.auto => 'Auto',
      };

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: _ComposerSelector(
              key: const ValueKey<String>('ask-pandora-model-control'),
              label: 'Model · $modelLabel',
              enabled: enabled,
              onTap: onModel,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: _ComposerSelector(
              key: const ValueKey<String>('ask-pandora-reasoning-control'),
              label: 'Reasoning · $_reasoningLabel',
              enabled: enabled,
              onTap: onReasoning,
            ),
          ),
        ],
      );
}

class _ComposerSelector extends StatelessWidget {
  const _ComposerSelector({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFFD9D9DB)
                          : const Color(0xFF737477),
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 1),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: enabled
                      ? const Color(0xFF9A9B9E)
                      : const Color(0xFF5F6063),
                ),
              ],
            ),
          ),
        ),
      );
}

class PandoraModelPickerSheet extends StatelessWidget {
  const PandoraModelPickerSheet({
    super.key,
    required this.models,
    required this.selection,
  });

  final List<PandoraChatModelOption> models;
  final PandoraChatModelSelection selection;

  @override
  Widget build(BuildContext context) {
    final selectedProvider = selection.provider;
    final selectedModel = selection.model;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Material(
          color: const Color(0xFF0B0B0C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Model',
                  style: TextStyle(
                    color: Color(0xFFF4F4F5),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ModelTile(
                key: const ValueKey<String>('model-picker-auto'),
                title: 'Auto',
                subtitle: 'Pandora chooses the verified model for this turn.',
                selected: selection.isAuto,
                enabled: true,
                onTap: () => Navigator.of(context).pop(
                  const PandoraChatModelSelection.auto(),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF242426)),
              Expanded(
                child: models.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No verified conversational model catalog is available.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF8D8E92)),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 14),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final selected = selectedProvider ==
                                  model.routingProvider &&
                              selectedModel == model.modelId;
                          final status = model.selectable
                              ? model.providerName
                              : '${model.providerName} · ${model.unavailableReason ?? 'Unavailable'}';
                          return _ModelTile(
                            key: ValueKey<String>(
                              'model-picker-${model.modelId}',
                            ),
                            title: model.modelName,
                            subtitle: status,
                            selected: selected,
                            enabled: model.selectable,
                            onTap: model.selectable
                                ? () => Navigator.of(context).pop(
                                      PandoraChatModelSelection.manual(
                                        provider: model.routingProvider,
                                        model: model.modelId,
                                      ),
                                    )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          title,
          style: TextStyle(
            color: enabled
                ? const Color(0xFFF0F0F1)
                : const Color(0xFF77787C),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled
                ? const Color(0xFF9A9B9E)
                : const Color(0xFF66676A),
            fontSize: 12.5,
            height: 1.25,
          ),
        ),
        trailing: selected
            ? const Icon(Icons.check_rounded, color: Color(0xFFF0F0F1))
            : enabled
                ? null
                : const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: Color(0xFF66676A),
                  ),
        onTap: enabled ? onTap : null,
      );
}

class PandoraReasoningPickerSheet extends StatelessWidget {
  const PandoraReasoningPickerSheet({
    super.key,
    required this.selection,
  });

  final PandoraIntelligenceMode selection;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Material(
          color: const Color(0xFF0B0B0C),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Reasoning',
                    style: TextStyle(
                      color: Color(0xFFF4F4F5),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _ReasoningTile(
                  mode: PandoraIntelligenceMode.auto,
                  label: 'Auto',
                  detail: 'Pandora chooses the right reasoning depth.',
                  selected: selection,
                ),
                _ReasoningTile(
                  mode: PandoraIntelligenceMode.fast,
                  label: 'Fast',
                  detail: 'Prioritize lower latency.',
                  selected: selection,
                ),
                _ReasoningTile(
                  mode: PandoraIntelligenceMode.deep,
                  label: 'Deep',
                  detail: 'Use deeper reasoning for difficult work.',
                  selected: selection,
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReasoningTile extends StatelessWidget {
  const _ReasoningTile({
    required this.mode,
    required this.label,
    required this.detail,
    required this.selected,
  });

  final PandoraIntelligenceMode mode;
  final String label;
  final String detail;
  final PandoraIntelligenceMode selected;

  @override
  Widget build(BuildContext context) => ListTile(
        key: ValueKey<String>('reasoning-picker-${mode.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF0F0F1),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          detail,
          style: const TextStyle(
            color: Color(0xFF8D8E92),
            fontSize: 12.5,
          ),
        ),
        trailing: selected == mode
            ? const Icon(Icons.check_rounded, color: Color(0xFFF0F0F1))
            : null,
        onTap: () => Navigator.of(context).pop(mode),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/pandora_intelligence_api.dart';

const String pandoraLocalDeviceProvider = 'pandora_local';
const String pandoraLocalDeviceModel = 'qwen2.5-1.5b-instruct-q4_k_m';

bool isPandoraLocalDeviceSelection(PandoraChatModelSelection selection) =>
    selection.selection == 'manual' &&
    selection.provider == pandoraLocalDeviceProvider &&
    selection.model == pandoraLocalDeviceModel;

class PandoraModelPickerChoice {
  const PandoraModelPickerChoice({
    required this.selection,
    required this.label,
  });

  final PandoraChatModelSelection selection;
  final String label;
}

const List<String> _pandoraFlagshipOrder = <String>[
  'Mistral Large 3',
  'DeepSeek V3.2',
  'Kimi K2.5',
  'GLM 5',
  'Qwen3 VL 235B',
  'Nemotron 3 Super 120B',
  'MiniMax M2.5',
  'Kimi K2 Thinking',
  'Devstral 2 123B',
  'Qwen3 Next 80B',
  'Qwen3 Coder Next',
  'GLM 4.7',
  'MiniMax M2.1',
  'Magistral Small',
  'Gemma 3 27B',
  'Nemotron Nano 3 30B',
  'MiniMax M2',
  'Ministral 14B',
  'GLM 4.7 Flash',
  'Gemma 3 12B',
  'Nemotron Nano 12B VL',
  'Ministral 8B',
  'Nemotron Nano 9B',
  'Palmyra Vision 7B',
  'Gemma 3 4B',
  'Ministral 3B',
];

String _normalizedModelName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<PandoraChatModelOption> pandoraOrderedSelectableModels(
  List<PandoraChatModelOption> models,
) {
  final rank = <String, int>{
    for (var i = 0; i < _pandoraFlagshipOrder.length; i += 1)
      _normalizedModelName(_pandoraFlagshipOrder[i]): i,
  };
  final selectable = models.where((model) => model.selectable).toList();
  selectable.sort((a, b) {
    final aRank = rank[_normalizedModelName(a.modelName)];
    final bRank = rank[_normalizedModelName(b.modelName)];
    if (aRank != null && bRank != null) return aRank.compareTo(bRank);
    if (aRank != null) return -1;
    if (bRank != null) return 1;
    final byName = a.modelName.toLowerCase().compareTo(
          b.modelName.toLowerCase(),
        );
    if (byName != 0) return byName;
    return a.modelId.compareTo(b.modelId);
  });
  return selectable;
}

/// A modal, opaque surface. Selection is the user's routing preference; a
/// response's execution model must never change the selected row here.
class PandoraModelPickerOverlay extends StatefulWidget {
  const PandoraModelPickerOverlay({
    super.key,
    required this.models,
    required this.selection,
    required this.reasoningMode,
    required this.onDismiss,
    required this.onModelSelected,
    required this.onReasoningSelected,
    this.localAiEnabled = false,
    this.localAiAvailable = false,
    this.localAiModelName,
    this.startAtEnd = false,
    this.generationActive = false,
    this.error,
    this.onRetry,
  });

  final List<PandoraChatModelOption> models;
  final PandoraChatModelSelection selection;
  final PandoraIntelligenceMode reasoningMode;
  final VoidCallback onDismiss;
  final ValueChanged<PandoraModelPickerChoice> onModelSelected;
  final ValueChanged<PandoraIntelligenceMode> onReasoningSelected;
  final bool localAiEnabled;
  final bool localAiAvailable;
  final String? localAiModelName;
  final bool startAtEnd;
  final bool generationActive;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<PandoraModelPickerOverlay> createState() =>
      _PandoraModelPickerOverlayState();
}

class _PandoraModelPickerOverlayState extends State<PandoraModelPickerOverlay> {
  static const _surfaceColor = Color(0xFF1B1B1B);
  final ScrollController _scrollController = ScrollController();
  final FocusScopeNode _focusScope = FocusScopeNode(
    debugLabel: 'Pandora options',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final FocusNode _closeFocus = FocusNode(debugLabel: 'Close Pandora options');
  late bool _advancedExpanded;

  List<PandoraChatModelOption> get _selectable =>
      pandoraOrderedSelectableModels(widget.models);

  bool get _localSelectable => widget.localAiEnabled && widget.localAiAvailable;

  @override
  void initState() {
    super.initState();
    _advancedExpanded = !widget.selection.isAuto || widget.startAtEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusScope.requestFocus(_closeFocus);
      if (widget.startAtEnd && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _closeFocus.dispose();
    _focusScope.dispose();
    super.dispose();
  }

  bool _isSelected(PandoraChatModelOption model) =>
      widget.selection.selection == 'manual' &&
      widget.selection.provider == model.routingProvider &&
      widget.selection.model == model.modelId;

  Widget _selectionRow({
    required Key key,
    required String label,
    required bool selected,
    String? subtitle,
    VoidCallback? onTap,
    bool locked = false,
  }) =>
      Semantics(
        identifier: key is ValueKey<String>
            ? 'pandora.chat.${key.value.replaceFirst('model-picker-', 'model.')}'
            : null,
        container: true,
        button: true,
        selected: selected,
        enabled: onTap != null,
        inMutuallyExclusiveGroup: true,
        label: label,
        value: selected ? 'Selected' : null,
        hint: locked ? 'Currently unavailable' : subtitle,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: locked
                                ? Colors.white.withValues(alpha: .45)
                                : Colors.white,
                            fontSize: 15,
                            height: 1.3,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .66),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox.square(
                    dimension: 24,
                    child: selected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: Colors.white,
                          )
                        : locked
                            ? Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: .45),
                              )
                            : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _reasoningChoice(
    String label,
    PandoraIntelligenceMode mode,
    String key,
  ) {
    final selected = widget.reasoningMode == mode;
    return Semantics(
      identifier:
          'pandora.chat.reasoning.${key.replaceFirst('reasoning-picker-', '')}',
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: '$label response depth',
      value: selected ? 'Selected' : null,
      onTap: () => widget.onReasoningSelected(mode),
      excludeSemantics: true,
      child: ChoiceChip(
        key: ValueKey<String>(key),
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        onSelected: (_) => widget.onReasoningSelected(mode),
        selectedColor: const Color(0xFF3C3C3C),
        backgroundColor: _surfaceColor,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 14),
        checkmarkColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: .22)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }

  String get _reasoningDescription => switch (widget.reasoningMode) {
        PandoraIntelligenceMode.fast =>
          'A brief response with less deliberation.',
        PandoraIntelligenceMode.deep =>
          'More deliberate work when the selected model supports it.',
        _ => 'A balance of response speed and depth.',
      };

  @override
  Widget build(BuildContext context) {
    final unavailable =
        widget.models.where((model) => !model.selectable).length;
    final selectable = _selectable;
    return BlockSemantics(
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: FocusScope(
          node: _focusScope,
          autofocus: true,
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    widget.onDismiss();
                    return null;
                  },
                ),
              },
              child: Stack(
                key: const ValueKey<String>('pandora-model-picker-overlay'),
                fit: StackFit.expand,
                children: [
                  ModalBarrier(
                    key: const ValueKey<String>('pandora-model-picker-dismiss'),
                    color: Colors.black.withValues(alpha: .55),
                    dismissible: true,
                    onDismiss: widget.onDismiss,
                    semanticsLabel: 'Close Pandora options',
                    barrierSemanticsDismissible: true,
                  ),
                  // The Scaffold may already consume IME insets. Reading this
                  // subtree's remaining inset avoids applying it twice.
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: SafeArea(
                      minimum: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Semantics(
                            identifier: 'pandora.chat.model-picker',
                            scopesRoute: true,
                            namesRoute: true,
                            explicitChildNodes: true,
                            label: 'Pandora options',
                            child: Material(
                              key: const ValueKey<String>(
                                'pandora-model-picker-surface',
                              ),
                              color: _surfaceColor,
                              surfaceTintColor: Colors.transparent,
                              elevation: 16,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: .16),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                key: const ValueKey<String>(
                                  'pandora-model-picker-list',
                                ),
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(left: 12),
                                            child: Text(
                                              'Pandora options',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Semantics(
                                          identifier:
                                              'pandora.chat.model-picker.close',
                                          child: IconButton(
                                            key: const ValueKey<String>(
                                              'pandora-model-picker-close',
                                            ),
                                            focusNode: _closeFocus,
                                            tooltip: 'Close Pandora options',
                                            onPressed: widget.onDismiss,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (widget.generationActive)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          12,
                                          0,
                                          12,
                                          12,
                                        ),
                                        child: Text(
                                          'Changes apply to your next message.',
                                          style: TextStyle(
                                            color: Color(0xFFCCCCCC),
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    _selectionRow(
                                      key: const ValueKey<String>(
                                        'model-picker-auto',
                                      ),
                                      label: 'Auto',
                                      subtitle:
                                          'Pandora chooses a suitable model for each message.',
                                      selected: widget.selection.isAuto,
                                      onTap: () => widget.onModelSelected(
                                        const PandoraModelPickerChoice(
                                          selection:
                                              PandoraChatModelSelection.auto(),
                                          label: 'Auto',
                                        ),
                                      ),
                                    ),
                                    const Divider(color: Color(0xFF353535)),
                                    Semantics(
                                      identifier:
                                          'pandora.chat.reasoning-options',
                                      container: true,
                                      explicitChildNodes: true,
                                      label: 'Response depth',
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Response depth',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                _reasoningChoice(
                                                  'Balanced',
                                                  PandoraIntelligenceMode.auto,
                                                  'reasoning-picker-balanced',
                                                ),
                                                _reasoningChoice(
                                                  'Fast',
                                                  PandoraIntelligenceMode.fast,
                                                  'reasoning-picker-fast',
                                                ),
                                                _reasoningChoice(
                                                  'Deep',
                                                  PandoraIntelligenceMode.deep,
                                                  'reasoning-picker-deep',
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _reasoningDescription,
                                              style: const TextStyle(
                                                color: Color(0xFFCCCCCC),
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Divider(color: Color(0xFF353535)),
                                    Semantics(
                                      identifier: 'pandora.chat.model.advanced',
                                      expanded: _advancedExpanded,
                                      child: ListTile(
                                        key: const ValueKey<String>(
                                          'pandora-model-picker-advanced',
                                        ),
                                        title: const Text(
                                          'Choose a model',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                          ),
                                        ),
                                        subtitle: const Text(
                                          'Advanced',
                                          style: TextStyle(
                                            color: Color(0xFFBBBBBB),
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Icon(
                                          _advancedExpanded
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          color: Colors.white,
                                        ),
                                        onTap: () => setState(
                                          () => _advancedExpanded =
                                              !_advancedExpanded,
                                        ),
                                      ),
                                    ),
                                    if (_advancedExpanded) ...[
                                      for (final model in selectable)
                                        _selectionRow(
                                          key: ValueKey<String>(
                                            'model-picker-${model.modelId}',
                                          ),
                                          label: model.modelName,
                                          selected: _isSelected(model),
                                          onTap: () => widget.onModelSelected(
                                            PandoraModelPickerChoice(
                                              selection:
                                                  PandoraChatModelSelection
                                                      .manual(
                                                provider: model.routingProvider,
                                                model: model.modelId,
                                              ),
                                              label: model.modelName,
                                            ),
                                          ),
                                        ),
                                      _selectionRow(
                                        key: const ValueKey<String>(
                                          'model-picker-local-device',
                                        ),
                                        label: widget.localAiModelName ??
                                            'Local device (Qwen)',
                                        selected: isPandoraLocalDeviceSelection(
                                          widget.selection,
                                        ),
                                        locked: !_localSelectable,
                                        onTap: _localSelectable
                                            ? () => widget.onModelSelected(
                                                  PandoraModelPickerChoice(
                                                    selection:
                                                        const PandoraChatModelSelection
                                                            .manual(
                                                      provider:
                                                          pandoraLocalDeviceProvider,
                                                      model:
                                                          pandoraLocalDeviceModel,
                                                    ),
                                                    label: widget
                                                            .localAiModelName ??
                                                        'Local device (Qwen)',
                                                  ),
                                                )
                                            : null,
                                      ),
                                      if (unavailable > 0)
                                        Padding(
                                          key: const ValueKey<String>(
                                            'model-picker-unavailable-count',
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            '$unavailable more unavailable',
                                            style: const TextStyle(
                                              color: Color(0xFFBBBBBB),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                    if (widget.error != null)
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.error!,
                                              style: const TextStyle(
                                                color: Color(0xFFE6CDB1),
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                            if (widget.onRetry != null)
                                              TextButton(
                                                onPressed: widget.onRetry,
                                                child: const Text('Try again'),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
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
      ),
    );
  }
}

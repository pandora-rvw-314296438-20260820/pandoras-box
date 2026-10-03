import 'package:flutter/material.dart';

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
    final byName =
        a.modelName.toLowerCase().compareTo(b.modelName.toLowerCase());
    if (byName != 0) return byName;
    return a.modelId.compareTo(b.modelId);
  });
  return selectable;
}

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

  @override
  State<PandoraModelPickerOverlay> createState() =>
      _PandoraModelPickerOverlayState();
}

class _PandoraModelPickerOverlayState extends State<PandoraModelPickerOverlay> {
  static const double _rowHeight = 34;
  final ScrollController _scrollController = ScrollController();
  bool _atEnd = false;

  List<PandoraChatModelOption> get _selectable =>
      pandoraOrderedSelectableModels(widget.models);

  int get _unavailableCount =>
      widget.models.where((model) => !model.selectable).length;

  bool get _localSelectable =>
      widget.localAiEnabled && widget.localAiAvailable;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    if (widget.startAtEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        _handleScroll();
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final next = _scrollController.position.maxScrollExtent > 0 &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 1;
    if (next != _atEnd && mounted) setState(() => _atEnd = next);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
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
    VoidCallback? onTap,
    bool locked = false,
    bool unavailableSummary = false,
  }) {
    final color = unavailableSummary
        ? Colors.white.withValues(alpha: .18)
        : locked
            ? Colors.white.withValues(alpha: .30)
            : selected
                ? Colors.white
                : Colors.white.withValues(alpha: .60);
    final style = TextStyle(
      color: color,
      fontSize: unavailableSummary ? 13 : 15,
      height: 1,
      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
    );
    final row = SizedBox(
      key: key,
      height: _rowHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (locked) ...[
              Icon(
                Icons.lock_outline_rounded,
                size: 11,
                color: Colors.white.withValues(alpha: .30),
              ),
              const SizedBox(width: 8),
            ],
            Text(label, textAlign: TextAlign.right, style: style),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  Widget _modelViewport() {
    final selectable = _selectable;
    final totalItems =
        selectable.length + 1 + (_unavailableCount > 0 ? 1 : 0);
    return SizedBox(
      height: _rowHeight * 5,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _atEnd
              ? const <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                ]
              : const <Color>[
                  Color(0x00FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                ],
          stops: _atEnd
              ? const <double>[0, .20, 1]
              : const <double>[0, .80, 1],
        ).createShader(rect),
        child: ListView.builder(
          key: const ValueKey<String>('pandora-model-picker-list'),
          controller: _scrollController,
          reverse: true,
          itemExtent: _rowHeight,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < selectable.length) {
              final model = selectable[index];
              return _selectionRow(
                key: ValueKey<String>('model-picker-' + model.modelId),
                label: model.modelName,
                selected: _isSelected(model),
                onTap: () => widget.onModelSelected(
                  PandoraModelPickerChoice(
                    selection: PandoraChatModelSelection.manual(
                      provider: model.routingProvider,
                      model: model.modelId,
                    ),
                    label: model.modelName,
                  ),
                ),
              );
            }
            final localIndex = selectable.length;
            if (index == localIndex) {
              final localSelected =
                  isPandoraLocalDeviceSelection(widget.selection);
              return _selectionRow(
                key: const ValueKey<String>('model-picker-local-device'),
                label: 'Local device (Qwen)',
                selected: localSelected,
                locked: !_localSelectable,
                onTap: _localSelectable
                    ? () => widget.onModelSelected(
                          const PandoraModelPickerChoice(
                            selection: PandoraChatModelSelection.manual(
                              provider: pandoraLocalDeviceProvider,
                              model: pandoraLocalDeviceModel,
                            ),
                            label: 'Local device (Qwen)',
                          ),
                        )
                    : null,
              );
            }
            return _selectionRow(
              key: const ValueKey<String>('model-picker-unavailable-count'),
              label: _unavailableCount.toString() + ' more unavailable',
              selected: false,
              unavailableSummary: true,
            );
          },
        ),
      ),
    );
  }

  Widget _reasoningChoice(
    String label,
    PandoraIntelligenceMode value,
    Key key,
  ) {
    final selected = widget.reasoningMode == value;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onReasoningSelected(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: .32),
            fontSize: 15,
            height: 1,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      key: const ValueKey<String>('pandora-model-picker-overlay'),
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey<String>('pandora-model-picker-dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 400,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0x47000000),
                      Color(0x9E000000),
                      Color(0xC7000000),
                    ],
                    stops: <double>[0, .30, .62, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 74.5,
            bottom: safeBottom + 92,
            width: 285,
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _modelViewport(),
                  _selectionRow(
                    key: const ValueKey<String>('model-picker-auto'),
                    label: 'Auto',
                    selected: widget.selection.isAuto,
                    onTap: () => widget.onModelSelected(
                      const PandoraModelPickerChoice(
                        selection: PandoraChatModelSelection.auto(),
                        label: 'Auto',
                      ),
                    ),
                  ),
                  Text(
                    'Model',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .25),
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Reasoning',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .25),
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _reasoningChoice(
                        'Balanced',
                        PandoraIntelligenceMode.auto,
                        const ValueKey<String>('reasoning-picker-balanced'),
                      ),
                      const SizedBox(width: 18),
                      _reasoningChoice(
                        'Fast',
                        PandoraIntelligenceMode.fast,
                        const ValueKey<String>('reasoning-picker-fast'),
                      ),
                      const SizedBox(width: 18),
                      _reasoningChoice(
                        'Deep',
                        PandoraIntelligenceMode.deep,
                        const ValueKey<String>('reasoning-picker-deep'),
                      ),
                    ],
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

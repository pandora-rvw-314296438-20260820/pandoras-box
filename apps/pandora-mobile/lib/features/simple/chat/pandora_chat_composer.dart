import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// This is a projection of the chat controller, not a second turn lifecycle.
enum PandoraComposerPhase { idle, generating, queued, reconciling }

@immutable
class PandoraComposerState {
  const PandoraComposerState({
    this.phase = PandoraComposerPhase.idle,
    this.enabled = true,
    this.voiceAvailable = true,
    this.voiceActive = false,
    this.generationIdentity,
  });

  final PandoraComposerPhase phase;
  final bool enabled;
  final bool voiceAvailable;
  final bool voiceActive;

  /// Stable turn/attempt/generation key supplied by the chat controller.
  final String? generationIdentity;

  bool get canSend =>
      enabled &&
      (phase == PandoraComposerPhase.idle ||
          phase == PandoraComposerPhase.generating);
  bool get canStop =>
      enabled &&
      (phase == PandoraComposerPhase.generating ||
          phase == PandoraComposerPhase.queued);
  bool get canDictate =>
      enabled &&
      voiceAvailable &&
      !voiceActive &&
      phase == PandoraComposerPhase.idle;
}

/// A persistent input field whose actions read the current authoritative intent
/// and text at activation, including an activation before the next Flutter frame.
class PandoraChatComposer extends StatefulWidget {
  /// Initial viewport clearance before the first measured composer frame.
  /// Context chips, text scaling and multiline input can increase this extent.
  static const double minimumExtent = 66;

  const PandoraChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.state,
    required this.onSend,
    required this.onStop,
    this.onVoice,
    this.onModelOptions,
    this.modelLabel = 'Auto',
    this.pickerOpen = false,
    this.leading,
    this.context,
    this.onChanged,
    this.onHeightChanged,
    this.maxLength = 4000,
    this.maxInputExtent = 160,
  }) : assert(maxInputExtent >= 54);

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueListenable<PandoraComposerState> state;

  /// Must synchronously admit the local intent and clear the admitted draft.
  /// Network acceptance and generation must not delay local admission.
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final VoidCallback? onVoice;
  final VoidCallback? onModelOptions;
  final String modelLabel;
  final bool pickerOpen;
  final Widget? leading;
  final Widget? context;
  final ValueChanged<String>? onChanged;
  final ValueChanged<double>? onHeightChanged;
  final int maxLength;

  /// The integrating LayoutBuilder may lower this bound for a short IME
  /// viewport. It must still fit one scaled text line and its input padding.
  final double maxInputExtent;

  @override
  State<PandoraChatComposer> createState() => _PandoraChatComposerState();
}

class _PandoraChatComposerState extends State<PandoraChatComposer> {
  bool _dispatching = false;

  void _send() {
    if (_dispatching) return;
    final current = widget.controller.text.trim();
    if (current.isEmpty || !widget.state.value.canSend) return;
    _dispatching = true;
    try {
      widget.onSend(current);
    } finally {
      _dispatching = false;
    }
  }

  void _activatePrimary({required bool allowVoice}) {
    if (widget.controller.text.trim().isNotEmpty) {
      _send();
      return;
    }
    // Clearing a visible Send button must never turn the old frame's tap into
    // an unexpected microphone activation. Typing into a visible Voice button
    // still sends the current text, preserving the existing current-text fix.
    if (allowVoice && widget.state.value.canDictate) widget.onVoice?.call();
  }

  void _stop(String? expectedGeneration) {
    final current = widget.state.value;
    if (current.canStop && current.generationIdentity == expectedGeneration) {
      widget.onStop();
    }
  }

  @override
  Widget build(BuildContext context) => _ComposerExtent(
        onHeightChanged: widget.onHeightChanged,
        child: ValueListenableBuilder<PandoraComposerState>(
          valueListenable: widget.state,
          builder: (context, state, _) => Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.context != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: widget.context!,
                  ),
                KeyedSubtree(
                  key: const ValueKey<String>('ask-pandora-composer-dock'),
                  child: Container(
                    key: const ValueKey<String>('ask-pandora-composer'),
                    constraints: const BoxConstraints(minHeight: 54),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(27),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.leading != null)
                          SizedBox(
                            width: 48,
                            height: 54,
                            child: Center(child: widget.leading),
                          ),
                        Expanded(
                          child: Shortcuts(
                            shortcuts: const <ShortcutActivator, Intent>{
                              SingleActivator(
                                LogicalKeyboardKey.enter,
                                control: true,
                              ): _SendDraftIntent(),
                              SingleActivator(LogicalKeyboardKey.enter,
                                  meta: true): _SendDraftIntent(),
                            },
                            child: Actions(
                              actions: <Type, Action<Intent>>{
                                _SendDraftIntent:
                                    CallbackAction<_SendDraftIntent>(
                                  onInvoke: (_) {
                                    _send();
                                    return null;
                                  },
                                ),
                              },
                              child: Semantics(
                                identifier: 'pandora.chat.input',
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxHeight: widget.maxInputExtent),
                                  child: TextField(
                                    key: const ValueKey<String>(
                                      'ask-pandora-objective',
                                    ),
                                    controller: widget.controller,
                                    focusNode: widget.focusNode,
                                    readOnly: !state.enabled,
                                    minLines: 1,
                                    maxLines: 5,
                                    maxLength: widget.maxLength,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.send,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: 'Message Pandora…',
                                      hintMaxLines: 1,
                                      hintStyle: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .45),
                                        fontSize: 16.5,
                                      ),
                                      counterText: '',
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.fromLTRB(
                                        6,
                                        16,
                                        3,
                                        16,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.5,
                                      height: 1.25,
                                    ),
                                    onChanged: widget.onChanged,
                                    // Sending from the IME does not give up the
                                    // draft's focus; immediate follow-up typing
                                    // remains in this same persistent field.
                                    onEditingComplete: () {},
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onModelOptions != null)
                          _ComposerAction(
                            key: const ValueKey<String>(
                              'ask-pandora-model-control',
                            ),
                            identifier: 'pandora.chat.model-options',
                            label: widget.modelLabel == 'Auto'
                                ? 'Pandora options, automatic model selection'
                                : 'Pandora options, ${widget.modelLabel} selected',
                            icon: Icons.tune_rounded,
                            selected: widget.pickerOpen,
                            onPressed: state.enabled
                                ? () {
                                    if (widget.state.value.enabled) {
                                      widget.onModelOptions?.call();
                                    }
                                  }
                                : null,
                          ),
                        // The stop slot is always present. Typing, emptying the
                        // draft and voice readiness cannot move or replace it.
                        _ComposerAction(
                          key: const ValueKey<String>('ask-pandora-stop'),
                          identifier: 'pandora.chat.stop',
                          label: 'Stop response',
                          icon: Icons.stop_rounded,
                          visible: state.canStop,
                          onPressed: state.canStop
                              ? () => _stop(state.generationIdentity)
                              : null,
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: widget.controller,
                          builder: (context, value, _) {
                            final empty = value.text.trim().isEmpty;
                            final voice = empty && widget.onVoice != null;
                            final enabled = empty
                                ? voice && state.canDictate
                                : state.canSend;
                            return _ComposerAction(
                              key: const ValueKey<String>('ask-pandora-submit'),
                              identifier: voice
                                  ? 'pandora.chat.voice'
                                  : 'pandora.chat.send',
                              label: voice
                                  ? (state.voiceActive
                                      ? 'Listening'
                                      : 'Voice input')
                                  : (state.phase ==
                                          PandoraComposerPhase.generating
                                      ? 'Send next message'
                                      : 'Send message'),
                              icon: voice
                                  ? Icons.mic_none_rounded
                                  : Icons.arrow_upward_rounded,
                              onPressed: enabled
                                  ? () => _activatePrimary(allowVoice: empty)
                                  : null,
                              // An empty generating frame can be visually
                              // disabled immediately before new draft text
                              // arrives. Physical activation still reads the
                              // latest draft and authoritative admission state.
                              liveActivation: () =>
                                  _activatePrimary(allowVoice: empty),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SendDraftIntent extends Intent {
  const _SendDraftIntent();
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    super.key,
    required this.identifier,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.visible = true,
    this.selected = false,
    this.liveActivation,
  });

  final String identifier;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool visible;
  final bool selected;
  final VoidCallback? liveActivation;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 54,
        child: Visibility(
          visible: visible,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: Semantics(
            identifier: identifier,
            label: label,
            button: true,
            enabled: onPressed != null,
            selected: selected,
            onTap: onPressed,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: liveActivation,
              child: IconButton(
                tooltip: label,
                padding: EdgeInsets.zero,
                onPressed: onPressed,
                icon: Icon(
                  icon,
                  size: 21,
                  color: Colors.white.withValues(
                    alpha: onPressed == null ? .28 : .88,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Observes layout without an intrinsic-height pass or a polling timer.
class _ComposerExtent extends SingleChildRenderObjectWidget {
  const _ComposerExtent({required super.child, this.onHeightChanged});

  final ValueChanged<double>? onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ComposerExtentRender(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _ComposerExtentRender renderObject,
  ) =>
      renderObject.onHeightChanged = onHeightChanged;
}

class _ComposerExtentRender extends RenderProxyBox {
  _ComposerExtentRender(this.onHeightChanged);

  ValueChanged<double>? onHeightChanged;
  double? _lastHeight;
  int _revision = 0;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastHeight == size.height) return;
    final extent = size.height;
    _lastHeight = extent;
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached || revision != _revision) return;
      onHeightChanged?.call(extent);
    });
  }
}

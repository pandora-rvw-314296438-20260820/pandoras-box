import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/pandora_tokens.dart';
import '../simple/pandora_v2_ui.dart';
import 'enterprise_inline_theatre.dart';
import 'enterprise_page_context.dart';
import 'enterprise_that_scope_command_runner.dart';

/// Persistent bottom Pandora command bar for Enterprise routes (P0-001).
///
/// Idle = bar only. Submit stays on the originating page (P0-002 companion).
class EnterpriseCommandBar extends StatefulWidget {
  const EnterpriseCommandBar({
    super.key,
    required this.controller,
    this.onSubmit,
    this.enabled = true,
  });

  final EnterprisePageContextController controller;

  /// Optional observer — must not navigate to AskPandora / full-page chat.
  final ValueChanged<EnterpriseCommandSubmission>? onSubmit;

  final bool enabled;

  static const accessibleName = 'Ask Pandora on this page';
  static const composerKey = ValueKey<String>(
    'enterprise-command-bar-composer',
  );
  static const sendKey = ValueKey<String>('enterprise-command-bar-send');
  static const barKey = ValueKey<String>('enterprise-command-bar');
  static const needsYouKey = ValueKey<String>(
    'enterprise-command-bar-needs-you',
  );

  /// Reserved height for content inset above the bar (composer row + padding).
  static const double reservedContentInset = 72;

  @override
  State<EnterpriseCommandBar> createState() => _EnterpriseCommandBarState();
}

class _EnterpriseCommandBarState extends State<EnterpriseCommandBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant EnterpriseCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    if (!widget.enabled) return;
    final submission = widget.controller.submit(_text.text);
    widget.onSubmit?.call(submission);
    if (submission.accepted) {
      _text.clear();
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsYou = widget.controller.needsYouReason;
    final envelope = widget.controller.envelope;

    return Material(
      key: EnterpriseCommandBar.barKey,
      color: PandoraV2Colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, thickness: 1, color: PandoraV2Colors.line),
          if (needsYou != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                key: EnterpriseCommandBar.needsYouKey,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.soft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PandoraV2Colors.warning),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.priority_high_rounded,
                          color: PandoraV2Colors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Needs You — $needsYou',
                            style: const TextStyle(
                              color: PandoraV2Colors.ink,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          onPressed: widget.controller.clearNeedsYou,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: PandoraV2Colors.muted,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: EnterpriseCommandBar.accessibleName,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: PandoraSize.compactMark,
                      ),
                      child: TextField(
                        key: EnterpriseCommandBar.composerKey,
                        controller: _text,
                        focusNode: _focus,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(
                          color: PandoraV2Colors.ink,
                          fontSize: 15,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: EnterpriseCommandBar.accessibleName,
                          hintStyle: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: PandoraV2Colors.soft,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: PandoraV2Colors.line,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: PandoraV2Colors.line,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: PandoraV2Colors.ink,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: PandoraSize.compactMark,
                  height: PandoraSize.compactMark,
                  child: IconButton(
                    key: EnterpriseCommandBar.sendKey,
                    tooltip: 'Send to Pandora',
                    style: IconButton.styleFrom(
                      backgroundColor: PandoraV2Colors.ink,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: PandoraV2Colors.line,
                      minimumSize: const Size(
                        PandoraSize.compactMark,
                        PandoraSize.compactMark,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.enabled ? _submit : null,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                  ),
                ),
              ],
            ),
          ),
          // Non-secret context for SR / diagnostics (P0-003).
          Semantics(
            container: true,
            label:
                'Context project ${envelope.project}, surface ${envelope.surface}',
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Hosts page content above the persistent Enterprise command stack.
///
/// Bottom stack (page stays mounted): page content → inline Activity Theatre →
/// command bar. Idle = theatre fully hidden; only the bar is visible
/// (P0-001 / P0-004).
class EnterpriseCommandHost extends StatefulWidget {
  const EnterpriseCommandHost({
    super.key,
    required this.controller,
    required this.child,
    this.showBar = true,
    this.onSubmit,
    this.theatreController,
    this.thatScopeCommandRunner,
  });

  final EnterprisePageContextController controller;
  final Widget child;
  final bool showBar;
  final ValueChanged<EnterpriseCommandSubmission>? onSubmit;

  /// Optional external theatre controller. When null, the host owns one so the
  /// mount point stays available without idle a11y chrome.
  final EnterpriseInlineTheatreController? theatreController;

  /// Optional that-scope runner override (tests inject a fake provider port).
  /// When null, a default runner wrapping [EnterpriseCodeApi] is used.
  final EnterpriseThatScopeCommandRunner? thatScopeCommandRunner;

  @override
  State<EnterpriseCommandHost> createState() => _EnterpriseCommandHostState();
}

class _EnterpriseCommandHostState extends State<EnterpriseCommandHost> {
  EnterpriseInlineTheatreController? _ownedTheatre;

  EnterpriseInlineTheatreController get _theatre {
    final external = widget.theatreController;
    if (external != null) return external;
    return _ownedTheatre ??= EnterpriseInlineTheatreController();
  }

  @override
  void dispose() {
    _ownedTheatre?.dispose();
    super.dispose();
  }

  void _handleSubmit(EnterpriseCommandSubmission submission) {
    widget.onSubmit?.call(submission);
    // P0-003/P0-006: incomplete identity → Theatre Needs You (exact scope named).
    if (!submission.accepted && submission.needsYouReason != null) {
      _theatre.admitIdentityNeedsYou(
        reason: submission.needsYouReason!,
        identityScope: submission.envelope.identityScope,
      );
      return;
    }
    // A6: accepted Code that-scope → provider mutation/readback → Success|Failed.
    // App Users accepted remains a no-op inside the runner (P0-019).
    if (submission.accepted) {
      final runner =
          widget.thatScopeCommandRunner ?? EnterpriseThatScopeCommandRunner();
      unawaited(
        runner.run(submission: submission, theatre: _theatre),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theatre = _theatre;
    final hosted = widget.showBar
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.child),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EnterpriseInlineTheatre(controller: theatre),
                    EnterpriseCommandBar(
                      controller: widget.controller,
                      onSubmit: _handleSubmit,
                    ),
                  ],
                ),
              ),
            ],
          )
        : widget.child;

    return EnterprisePageContextScope(
      controller: widget.controller,
      child: hosted,
    );
  }
}

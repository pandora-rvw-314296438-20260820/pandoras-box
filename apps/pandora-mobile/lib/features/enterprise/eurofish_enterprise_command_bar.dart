import 'package:flutter/material.dart';

import '../simple/ask_pandora_screen.dart';

class EurofishEnterpriseCommandBar extends StatefulWidget {
  const EurofishEnterpriseCommandBar({
    super.key,
    required this.contextLabel,
    this.suggestedPrompt,
  });

  final String contextLabel;
  final String? suggestedPrompt;

  @override
  State<EurofishEnterpriseCommandBar> createState() =>
      _EurofishEnterpriseCommandBarState();
}

class _EurofishEnterpriseCommandBarState
    extends State<EurofishEnterpriseCommandBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final prompt = value.isEmpty ? widget.suggestedPrompt?.trim() : value;
    if (prompt == null || prompt.isEmpty) return;

    final contextualPrompt =
        '1064 Euro-Fish Trading â€” ${widget.contextLabel}. $prompt '
        'Use verified connected business data when available. '
        'If a fact or live value is unavailable, say so rather than guessing.';

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: contextualPrompt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF20B1220),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x663B82F6)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFEAB308),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key:
                            ValueKey<String>('eurofish-enterprise-command-bar'),
                        controller: _controller,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'Ask Pandora about this pageâ€¦',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      key: const ValueKey<String>(
                        'eurofish-enterprise-command-submit',
                      ),
                      tooltip: 'Send to Pandora',
                      onPressed: _submit,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class EurofishEnterprisePage extends StatelessWidget {
  const EurofishEnterprisePage({
    super.key,
    required this.contextLabel,
    required this.child,
    this.suggestedPrompt,
  });

  final String contextLabel;
  final Widget child;
  final String? suggestedPrompt;
  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 92), child: child),
          Align(
            alignment: Alignment.bottomCenter,
            child: EurofishEnterpriseCommandBar(
              contextLabel: contextLabel,
              suggestedPrompt: suggestedPrompt,
            ),
          ),
        ],
      );
}

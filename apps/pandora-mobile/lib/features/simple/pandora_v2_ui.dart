
import 'package:flutter/material.dart';

import '../../core/widgets/pandora_mark.dart';

abstract final class PandoraV2Colors {
  static const canvas = Color(0xFFF6F5F2);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF171717);
  static const muted = Color(0xFF6B6A66);
  static const line = Color(0xFFE4E3DF);
  static const soft = Color(0xFFF0EFEB);
  static const success = Color(0xFF0B6B45);
  static const warning = Color(0xFF8A5A12);
  static const danger = Color(0xFFB42318);
}

const pandoraV2Body = TextStyle(
  color: PandoraV2Colors.ink,
  fontSize: 15,
  height: 1.42,
);

const pandoraV2Muted = TextStyle(
  color: PandoraV2Colors.muted,
  fontSize: 14,
  height: 1.38,
);

class PandoraV2Page extends StatelessWidget {
  const PandoraV2Page({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 32),
    this.scrollable = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return ColoredBox(
      color: PandoraV2Colors.canvas,
      child: SafeArea(
        child: scrollable
            ? SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: body,
              )
            : body,
      ),
    );
  }
}

class PandoraV2BrandHeader extends StatelessWidget {
  const PandoraV2BrandHeader({super.key, this.onAvatar});

  final VoidCallback? onAvatar;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const PandoraMark(size: 34),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Account',
            child: InkResponse(
              onTap: onAvatar,
              radius: 28,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PandoraV2Colors.soft,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  'M',
                  style: TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class PandoraV2ObjectHeader extends StatelessWidget {
  const PandoraV2ObjectHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onMore,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: PandoraV2Colors.ink,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.25,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
            if (onMore != null)
              IconButton(
                tooltip: 'More',
                onPressed: onMore,
                icon: const Icon(Icons.more_vert_rounded),
                color: PandoraV2Colors.ink,
              ),
          ],
        ),
      );
}

class PandoraV2IntentSurface extends StatelessWidget {
  const PandoraV2IntentSurface({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSubmit,
    this.onVoice,
    this.onAttachment,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onVoice;
  final VoidCallback? onAttachment;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PandoraV2Colors.line)),
        ),
        child: Column(
          children: [
            TextField(
              controller: controller,
              enabled: enabled,
              autofocus: autofocus,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 18,
                height: 1.35,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF989793),
                  fontSize: 18,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
              ),
            ),
            Row(
              children: [
                if (onAttachment != null)
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: enabled ? onAttachment : null,
                    icon: const Icon(Icons.attach_file_rounded),
                    color: PandoraV2Colors.muted,
                  ),
                if (onVoice != null)
                  IconButton(
                    tooltip: 'Speak',
                    onPressed: enabled ? onVoice : null,
                    icon: const Icon(Icons.mic_none_rounded),
                    color: PandoraV2Colors.muted,
                  ),
                const Spacer(),
                IconButton.filled(
                  tooltip: 'Continue',
                  onPressed: enabled
                      ? () {
                          final value = controller.text.trim();
                          if (value.isNotEmpty) onSubmit(value);
                        }
                      : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PandoraV2Colors.ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: PandoraV2Colors.soft,
                    disabledForegroundColor: PandoraV2Colors.muted,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
}

class PandoraV2PrimaryAction extends StatelessWidget {
  const PandoraV2PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: PandoraV2Colors.ink,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFB8B7B2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, size: 19),
                    ],
                  ],
                ),
        ),
      );
}

class PandoraV2ObjectWindow extends StatelessWidget {
  const PandoraV2ObjectWindow({
    super.key,
    required this.title,
    required this.subtitle,
    this.detail,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PandoraV2Colors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraV2Colors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: pandoraV2Muted),
                      if (detail != null && detail!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: pandoraV2Body,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing ??
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: PandoraV2Colors.ink,
                      size: 21,
                    ),
              ],
            ),
          ),
        ),
      );
}

class PandoraV2InlineMessage extends StatelessWidget {
  const PandoraV2InlineMessage({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.danger = false,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PandoraV2Colors.line),
            bottom: BorderSide(color: PandoraV2Colors.line),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: danger ? PandoraV2Colors.danger : PandoraV2Colors.ink,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(message, style: pandoraV2Muted),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: PandoraV2Colors.ink),
                child: Text(actionLabel!),
              ),
          ],
        ),
      );
}

class PandoraV2Skeleton extends StatelessWidget {
  const PandoraV2Skeleton({super.key, this.height = 92});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(14),
        ),
      );
}

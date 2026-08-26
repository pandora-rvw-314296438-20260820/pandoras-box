import 'package:flutter/material.dart';

import '../../core/design/pandora_tokens.dart';
import '../../core/widgets/pandora_mark.dart';

abstract final class PandoraSimpleColors {
  static const red = Color(0xFFD40A24);
  static const deepRed = Color(0xFFB9091F);
  static const ink = Color(0xFF151515);
  static const muted = Color(0xFF6E6D69);
  static const canvas = Color(0xFFF8F8F6);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE9E7E3);
  static const blush = Color(0xFFFFF2F4);
  static const blueWash = Color(0xFFF1F5FF);
  static const greenWash = Color(0xFFF0FAF3);
  static const purpleWash = Color(0xFFF7F1FF);
  static const amberWash = Color(0xFFFFF7ED);
  static const green = Color(0xFF26954A);
  static const blue = Color(0xFF2F6FD7);
  static const purple = Color(0xFF7A45C5);
  static const amber = Color(0xFFD77816);
}

class PandoraSimplePage extends StatelessWidget {
  const PandoraSimplePage({
    super.key,
    required this.header,
    required this.child,
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 36),
  });

  final Widget header;
  final Widget child;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
    return ColoredBox(
      color: PandoraSimpleColors.canvas,
      child: SafeArea(
        bottom: false,
        child: onRefresh == null
            ? scrollView
            : RefreshIndicator(
                color: PandoraSimpleColors.red,
                onRefresh: onRefresh!,
                child: scrollView,
              ),
      ),
    );
  }
}

class PandoraOwnerHeader extends StatelessWidget {
  const PandoraOwnerHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.leadingMark = true,
    this.centerBrand = false,
    this.showBack = false,
    this.onBack,
    this.onNotifications,
    this.onAvatar,
    this.avatarTooltip = 'Open Settings',
  });

  final String title;
  final String subtitle;
  final bool leadingMark;
  final bool centerBrand;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onNotifications;
  final VoidCallback? onAvatar;
  final String avatarTooltip;

  @override
  Widget build(BuildContext context) {
    if (centerBrand) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SizedBox(
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _HeaderButton(
                  tooltip: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onPressed: showBack
                      ? (onBack ?? () => Navigator.of(context).maybePop())
                      : null,
                ),
              ),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PandoraMark(size: 44, color: PandoraSimpleColors.red),
                  SizedBox(width: 10),
                  Text(
                    'PANDORA',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NotificationButton(onPressed: onNotifications),
                    const SizedBox(width: 8),
                    _OwnerAvatar(
                      onPressed: onAvatar,
                      tooltip: avatarTooltip,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          if (leadingMark) ...[
            const PandoraMark(size: 52, color: PandoraSimpleColors.red),
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
                    color: PandoraSimpleColors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                    height: 1.04,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _NotificationButton(onPressed: onNotifications),
          const SizedBox(width: 8),
          _OwnerAvatar(onPressed: onAvatar, tooltip: avatarTooltip),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: PandoraSimpleColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: PandoraSimpleColors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 48,
              child: Icon(
                icon,
                color: onPressed == null
                    ? PandoraSimpleColors.line
                    : PandoraSimpleColors.ink,
              ),
            ),
          ),
        ),
      );
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Open Needs You',
        child: InkResponse(
          radius: 28,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: PandoraSimpleColors.ink,
                  size: 29,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: PandoraSimpleColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({required this.onPressed, required this.tooltip});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFFE9ECE9),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox.square(
              dimension: 48,
              child: Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class PandoraSimpleCard extends StatelessWidget {
  const PandoraSimpleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.backgroundColor = PandoraSimpleColors.surface,
    this.borderColor = PandoraSimpleColors.line,
    this.radius = 20,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ]
          : null,
    );
    final body = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

class PandoraSectionTitle extends StatelessWidget {
  const PandoraSectionTitle({
    super.key,
    required this.title,
    this.meta,
    this.actionLabel,
    this.onAction,
    this.live = false,
  });

  final String title;
  final String? meta;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool live;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.25,
                ),
              ),
            ),
            if (live) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: PandoraSimpleColors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Live',
                style: TextStyle(
                  color: PandoraSimpleColors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (meta != null) ...[
              const SizedBox(width: 6),
              Text(
                meta!,
                style: const TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 14,
                ),
              ),
            ],
            const Spacer(),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: PandoraSimpleColors.deepRed,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(48, 44),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w650),
                ),
              ),
          ],
        ),
      );
}

class PandoraIconBadge extends StatelessWidget {
  const PandoraIconBadge({
    super.key,
    required this.icon,
    this.foreground = PandoraSimpleColors.red,
    this.background = PandoraSimpleColors.blush,
    this.size = 44,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * .32),
          border: Border.all(color: foreground.withValues(alpha: .08)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: foreground, size: size * .52),
      );
}

class PandoraStatusPill extends StatelessWidget {
  const PandoraStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.foreground = PandoraSimpleColors.green,
    this.background = PandoraSimpleColors.greenWash,
  });

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: foreground, size: 16),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w650,
              ),
            ),
          ],
        ),
      );
}

class PandoraPrimaryButton extends StatelessWidget {
  const PandoraPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.loading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: PandoraSimpleColors.red,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PandoraSimpleColors.red.withValues(alpha: .45),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(icon),
      label: Text(label),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class PandoraSecondaryButton extends StatelessWidget {
  const PandoraSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: PandoraSimpleColors.deepRed,
      side: const BorderSide(color: Color(0xFFE6A8B2)),
      minimumSize: const Size(0, 54),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    final button = icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon),
            label: Text(label),
          );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class PandoraFlowStep {
  const PandoraFlowStep({required this.label, required this.state});

  final String label;
  final PandoraFlowStepState state;
}

enum PandoraFlowStepState { complete, current, pending }

class PandoraFlowStepper extends StatelessWidget {
  const PandoraFlowStepper({super.key, required this.steps});

  final List<PandoraFlowStep> steps;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                Expanded(child: _StepItem(step: steps[index], index: index)),
                if (index < steps.length - 1)
                  Container(
                    width: 18,
                    height: 1.5,
                    color: steps[index].state == PandoraFlowStepState.complete
                        ? PandoraSimpleColors.red
                        : PandoraSimpleColors.line,
                  ),
              ],
            ],
          );
        },
      );
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.step, required this.index});

  final PandoraFlowStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final active = step.state != PandoraFlowStepState.pending;
    final complete = step.state == PandoraFlowStepState.complete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? PandoraSimpleColors.red : const Color(0xFFD7D6D4),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: complete
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          style: TextStyle(
            color: active
                ? PandoraSimpleColors.deepRed
                : PandoraSimpleColors.muted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class PandoraDeviceSelector<T> extends StatelessWidget {
  const PandoraDeviceSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.iconBuilder,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final IconData Function(T value) iconBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F4),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: PandoraSimpleColors.line),
        ),
        child: Row(
          children: [
            for (final value in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: value == selected
                        ? PandoraSimpleColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(value),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 50),
                        decoration: value == selected
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE4E1DE),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0C000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              )
                            : null,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              iconBuilder(value),
                              size: 20,
                              color: value == selected
                                  ? PandoraSimpleColors.red
                                  : PandoraSimpleColors.muted,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                labelBuilder(value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: value == selected
                                      ? PandoraSimpleColors.deepRed
                                      : PandoraSimpleColors.muted,
                                  fontWeight: value == selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class PandoraPhoneFrame extends StatelessWidget {
  const PandoraPhoneFrame({
    super.key,
    required this.child,
    this.width = 340,
    this.height = 690,
  });

  final Widget child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(45),
          boxShadow: const [
            BoxShadow(
              color: Color(0x35000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(37),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 114,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111111),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(17),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class PandoraAirconHero extends StatelessWidget {
  const PandoraAirconHero({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 155,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF8F6F2), Color(0xFFEAE4DD)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 12,
              child: Container(
                width: 42,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFF5C8C55),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
            Positioned(
              left: 2,
              right: 2,
              bottom: 0,
              child: Container(
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F1EB),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 72,
              right: 30,
              top: 39,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFD8D8D6)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E2E2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 12,
              child: Container(
                width: 48,
                height: 30,
                decoration: BoxDecoration(
                  color: PandoraSimpleColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
}

class PandoraEmptyTruth extends StatelessWidget {
  const PandoraEmptyTruth({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        shadow: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PandoraIconBadge(icon: Icons.verified_user_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: PandoraSimpleColors.muted,
                      height: 1.35,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: PandoraSimpleColors.deepRed,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

const PandoraSimpleText = TextStyle(
  color: PandoraSimpleColors.ink,
  fontSize: 15,
  height: 1.35,
);

const PandoraSimpleMutedText = TextStyle(
  color: PandoraSimpleColors.muted,
  fontSize: 14,
  height: 1.35,
);

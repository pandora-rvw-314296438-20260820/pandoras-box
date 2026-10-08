import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/pandora_navigation.dart';
import 'plp_editorial_surfaces.dart';
import 'plp_line_icons.dart';

/// Visual parts of the PLP billing workspace (approved concept): temporal
/// hero, billing playhead, plan axis, black handoff/cancel panels and the
/// waiting band. They render only what they are given; all values come from
/// the owner API through the billing screen.

const plpBillingRule = Color(0xFFD3CBBE);
const plpBillingOnInkMuted = Color(0xFFBDB7AE);
const plpBillingOnInkEyebrow = Color(0xFFD5CCB7);
const plpBillingOnInkTrack = Color(0xFF3A3733);

const _actionStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
);

bool plpReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

class PlpBillingTitle extends StatelessWidget {
  const PlpBillingTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: plpInk,
          fontSize: 43,
          height: 0.98,
          letterSpacing: -1.4,
          fontWeight: FontWeight.w400,
        ),
      );
}

enum PlpBillingTone { good, off, warn }

class PlpBillingStatusLine extends StatelessWidget {
  const PlpBillingStatusLine({
    super.key,
    required this.lead,
    required this.rest,
    required this.tone,
  });

  final String lead;
  final String rest;
  final PlpBillingTone tone;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (tone) {
                PlpBillingTone.good => plpGood,
                PlpBillingTone.warn => plpWarn,
                PlpBillingTone.off => Colors.transparent,
              },
              border: tone == PlpBillingTone.off
                  ? Border.all(color: plpMuted)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: lead,
                style: const TextStyle(color: plpInk),
                children: [
                  if (rest.isNotEmpty)
                    TextSpan(
                      text: ' $rest',
                      style: const TextStyle(color: plpMuted),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 14.5, height: 1.3),
            ),
          ),
        ],
      );
}

class PlpBillingLabel extends StatelessWidget {
  const PlpBillingLabel(this.text, {super.key, this.icon});
  final String text;
  final PlpLineGlyph? icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (icon != null) ...[
            PlpLineIcon(icon!, size: 11, color: plpMuted, strokeWidth: 2),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: plpMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      );
}

/// Massive "N days" with the exact date beneath.
class PlpBillingTemporalHero extends StatelessWidget {
  const PlpBillingTemporalHero({
    super.key,
    required this.value,
    required this.unit,
    required this.caption,
    required this.date,
  });

  final String value;
  final String unit;
  final String caption;
  final String? date;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: [
          '$value $unit'.trim(),
          if (date != null) '$caption $date',
        ].join(', '),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      key: const ValueKey('plp-billing-hero-value'),
                      style: const TextStyle(
                        color: plpInk,
                        fontSize: 104,
                        height: 0.86,
                        letterSpacing: -5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        unit,
                        style: const TextStyle(
                          color: plpMuted,
                          fontSize: 22,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (date != null) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      if (caption.isNotEmpty)
                        TextSpan(
                          text: '$caption ',
                          style: const TextStyle(color: plpMuted),
                        ),
                      TextSpan(
                        text: date,
                        style: const TextStyle(color: plpInk),
                      ),
                    ],
                  ),
                  key: const ValueKey('plp-billing-hero-date'),
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ],
          ),
        ),
      );
}

/// The PayPal seal: an outline check-seal with a short label. Tapping it
/// asks the owner API to re-check PayPal.
class PlpBillingSeal extends StatefulWidget {
  const PlpBillingSeal({
    super.key,
    required this.label,
    required this.verified,
    required this.checking,
    required this.onTap,
    this.labelFirst = false,
  });

  final String label;
  final bool verified;
  final bool checking;
  final VoidCallback? onTap;
  final bool labelFirst;

  @override
  State<PlpBillingSeal> createState() => _PlpBillingSealState();
}

class _PlpBillingSealState extends State<PlpBillingSeal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PlpBillingSeal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.checking && !plpReduceMotion(context);
    if (animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!animate && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = RotationTransition(
      turns: _spin,
      child: PlpLineIcon(
        widget.verified ? PlpLineGlyph.seal : PlpLineGlyph.sealPlain,
        size: 18,
      ),
    );
    final text = Text(
      widget.label,
      key: const ValueKey('plp-billing-seal-label'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: plpMuted, fontSize: 11, letterSpacing: .1),
    );
    final children = widget.labelFirst
        ? <Widget>[Flexible(child: text), const SizedBox(width: 6), icon]
        : <Widget>[icon, const SizedBox(width: 6), Flexible(child: text)];
    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      hint: widget.onTap == null ? null : 'Check PayPal again',
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('plp-billing-seal'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// Horizontal timeline of the current cycle with a today marker and the
/// PayPal seal pinned at the last verification point.
class PlpBillingPlayhead extends StatelessWidget {
  const PlpBillingPlayhead({
    super.key,
    required this.today,
    required this.sealAt,
    required this.startLabel,
    required this.endLabel,
    required this.ghost,
    required this.seal,
  });

  /// 0..1 position of today within the cycle.
  final double today;

  /// 0..1 position of the last PayPal verification.
  final double sealAt;
  final String startLabel;
  final String endLabel;
  final bool ghost;
  final PlpBillingSeal seal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final x = (today.clamp(0.0, 1.0)) * w;
          final sx = (sealAt.clamp(0.0, 1.0)) * w;
          final right = sx > w * .55;
          final pinned = PlpBillingSeal(
            label: seal.label,
            verified: seal.verified,
            checking: seal.checking,
            onTap: seal.onTap,
            labelFirst: right,
          );
          return SizedBox(
            key: const ValueKey('plp-billing-playhead'),
            height: 66,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -13,
                  left: right ? null : sx - 9,
                  right: right ? w - sx - 9 : null,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.max(120, w - 4)),
                    child: pinned,
                  ),
                ),
                Positioned(
                  left: sx - .5,
                  top: 19,
                  child: Container(width: 1, height: 8, color: plpInk),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 26,
                  height: 9,
                  child: CustomPaint(
                    painter: _PlayheadPainter(x / (w == 0 ? 1 : w), ghost),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        startLabel,
                        style: const TextStyle(color: plpMuted, fontSize: 11),
                      ),
                      Text(
                        endLabel,
                        key: const ValueKey('plp-billing-playhead-end'),
                        style: TextStyle(
                          color: ghost ? plpInk : plpMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter(this.today, this.ghost);
  final double today;
  final bool ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final y = 4.5;
    final x = today * size.width;
    final ink = Paint()
      ..color = plpInk
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(x, y), ink);
    if (ghost) {
      final dash = Paint()
        ..color = plpMuted
        ..strokeWidth = 1;
      for (var d = x + 4; d < size.width; d += 8) {
        canvas.drawLine(
            Offset(d, y), Offset(math.min(d + 4, size.width), y), dash);
      }
    } else {
      canvas.drawLine(
        Offset(x, y),
        Offset(size.width, y),
        Paint()
          ..color = plpBillingRule
          ..strokeWidth = 1,
      );
    }
    canvas.drawLine(const Offset(.5, 0), Offset(.5, size.height), ink);
    canvas.drawLine(
      Offset(size.width - .5, 0),
      Offset(size.width - .5, size.height),
      Paint()
        ..color = const Color(0xFFB9B0A2)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = plpInk);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.today != today || old.ghost != ghost;
}

class PlpPlanNode {
  const PlpPlanNode({
    required this.code,
    required this.name,
    required this.price,
  });
  final String code;
  final String name;
  final String price;
}

/// Spatial plan axis: one hairline rail with a node per backend plan.
class PlpPlanAxis extends StatelessWidget {
  const PlpPlanAxis({
    super.key,
    required this.nodes,
    required this.current,
    required this.selected,
    required this.pending,
    required this.onSelect,
    this.hero = false,
  });

  final List<PlpPlanNode> nodes;

  /// Confirmed plan (filled marker) when nothing else is selected.
  final String? current;

  /// Previewed plan; the marker slides here.
  final String? selected;

  /// Plan waiting for PayPal approval (dashed ring).
  final String? pending;
  final ValueChanged<String>? onSelect;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final marker = selected ?? current;
    final from = nodes.indexWhere((n) => n.code == current);
    final to = nodes.indexWhere((n) => n.code == selected);
    final count = nodes.length;
    double at(int i) => count == 1 ? 0 : i / (count - 1);
    final reduce = plpReduceMotion(context);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      double cx(int i) => 6 + at(i) * (w - 12);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 13,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 6,
                  right: 6,
                  top: 6,
                  child: Container(height: 1, color: plpBillingRule),
                ),
                if (from >= 0 && to >= 0 && from != to)
                  AnimatedPositioned(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: math.min(cx(from), cx(to)),
                    width: (cx(to) - cx(from)).abs(),
                    top: 6,
                    child: Container(height: 1, color: plpInk),
                  ),
                for (var i = 0; i < count; i++)
                  Positioned(
                    left: cx(i) - 8.5,
                    top: -2,
                    child: SizedBox.square(
                      dimension: 17,
                      child: Center(
                        child: _PlanNodeDot(
                          key: ValueKey('plp-billing-node-${nodes[i].code}'),
                          filled: nodes[i].code == marker,
                          pending: nodes[i].code == pending &&
                              nodes[i].code != marker,
                          reduce: reduce,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: hero ? 20 : 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: _PlanNodeLabel(
                    node: nodes[i],
                    align: count == 1 || i == 0
                        ? CrossAxisAlignment.start
                        : i == count - 1
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center,
                    dim: selected != null &&
                        nodes[i].code == current &&
                        current != selected,
                    selected: nodes[i].code == marker,
                    hero: hero,
                    onTap: onSelect == null
                        ? null
                        : () => onSelect!(nodes[i].code),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _PlanNodeDot extends StatelessWidget {
  const _PlanNodeDot({
    super.key,
    required this.filled,
    required this.pending,
    required this.reduce,
  });
  final bool filled;
  final bool pending;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return const SizedBox.square(
        key: ValueKey('plp-billing-node-pending'),
        dimension: 17,
        child: CustomPaint(painter: _DashedRingPainter()),
      );
    }
    final size = filled ? 13.0 : 11.0;
    return AnimatedContainer(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? plpInk : plpCanvas,
        border: Border.all(color: plpInk),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = plpInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(.5), i * sweep, sweep * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) => false;
}

class _PlanNodeLabel extends StatelessWidget {
  const _PlanNodeLabel({
    required this.node,
    required this.align,
    required this.dim,
    required this.selected,
    required this.hero,
    required this.onTap,
  });

  final PlpPlanNode node;
  final CrossAxisAlignment align;
  final bool dim;
  final bool selected;
  final bool hero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        selected: selected,
        label: '${node.name}, ${node.price}',
        child: ExcludeSemantics(
          child: GestureDetector(
            key: ValueKey('plp-billing-plan-${node.code}'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: align,
                children: [
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dim ? plpMuted : plpInk,
                      fontSize: hero ? 29 : 20,
                      letterSpacing: hero ? -.5 : -.2,
                    ),
                  ),
                  SizedBox(height: hero ? 8 : 5),
                  Text(
                    node.price,
                    style: TextStyle(
                      color: plpMuted,
                      fontSize: hero ? 13 : 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// A thin-ruled tappable line (difference line, cancel line, entry line).
class PlpBillingRuledLine extends StatelessWidget {
  const PlpBillingRuledLine({
    super.key,
    required this.lead,
    this.rest = '',
    this.onTap,
    this.bottomRule = true,
    this.height = 56,
    this.leadSize = 15,
    this.restSize = 13,
    this.chevron,
    this.semanticsLabel,
  });

  final String lead;
  final String rest;
  final VoidCallback? onTap;
  final bool bottomRule;
  final double height;
  final double leadSize;
  final double restSize;

  /// Defaults to showing the chevron only when tappable. Lines that are
  /// temporarily inert (dimmed lock, raised panel) keep it for continuity.
  final bool? chevron;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semanticsLabel ?? '$lead$rest',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                border: Border(
                  top: const BorderSide(color: plpLine),
                  bottom: bottomRule
                      ? const BorderSide(color: plpLine)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: lead,
                        style: TextStyle(color: plpInk, fontSize: leadSize),
                        children: [
                          if (rest.isNotEmpty)
                            TextSpan(
                              text: rest,
                              style: TextStyle(
                                color: plpMuted,
                                fontSize: restSize,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (chevron ?? onTap != null)
                    PlpLineIcon(
                      PlpLineGlyph.chevronRight,
                      color: onTap != null ? plpInk : plpMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Short warn line (attention or error) with an optional text action.
class PlpBillingNotice extends StatelessWidget {
  const PlpBillingNotice({
    super.key,
    required this.title,
    this.body = '',
    this.action,
    this.onAction,
  });

  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 7,
              height: 7,
              color: plpWarn,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: plpInk, fontSize: 15)),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: plpMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: plpInk,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(action!),
              ),
          ],
        ),
      );
}

/// Full-bleed black panel rising from the bottom (handoff or cancel).
class PlpBillingBlackPanel extends StatelessWidget {
  const PlpBillingBlackPanel({
    super.key,
    required this.child,
    this.height,
  });

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.maybeOf(context)?.padding.bottom ?? 0;
    return Material(
      color: plpInk,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 28, 22, 22 + bottom),
          child: child,
        ),
      ),
    );
  }
}

class PlpBillingHandoffContent extends StatelessWidget {
  const PlpBillingHandoffContent({
    super.key,
    required this.planName,
    required this.price,
    required this.busy,
    required this.onContinue,
    required this.onNotNow,
  });

  final String planName;
  final String price;
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('plp-billing-handoff'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PAYPAL HANDOFF',
            style: TextStyle(
              color: plpBillingOnInkEyebrow,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            planName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 43,
              height: .98,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: const TextStyle(color: plpBillingOnInkMuted, fontSize: 20),
          ),
          const SizedBox(height: 18),
          const Text(
            'You\u2019ll approve this in PayPal.',
            style: TextStyle(color: plpBillingOnInkMuted, fontSize: 13),
          ),
          const Spacer(),
          Semantics(
            button: true,
            enabled: !busy,
            label: busy ? 'Opening PayPal' : 'Continue to PayPal',
            child: ExcludeSemantics(
              child: Material(
                color: busy ? plpBillingOnInkMuted : Colors.white,
                child: InkWell(
                  key: const ValueKey('plp-billing-continue'),
                  onTap: busy ? null : onContinue,
                  child: SizedBox(
                    height: 54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          busy ? 'OPENING PAYPAL\u2026' : 'CONTINUE TO PAYPAL',
                          style: _actionStyle.copyWith(color: plpInk),
                        ),
                        if (!busy) ...[
                          const SizedBox(width: 10),
                          const PlpLineIcon(PlpLineGlyph.externalLink,
                              size: 16, color: plpInk),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey('plp-billing-not-now'),
            onPressed: busy ? null : onNotNow,
            style: TextButton.styleFrom(
              foregroundColor: plpBillingOnInkMuted,
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: const Text('Not now'),
          ),
        ],
      );
}

class PlpBillingCancelContent extends StatelessWidget {
  const PlpBillingCancelContent({
    super.key,
    required this.accessLine,
    required this.busy,
    required this.onConfirmed,
    required this.onKeep,
  });

  final String accessLine;
  final bool busy;
  final VoidCallback onConfirmed;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('plp-billing-cancel-panel'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cancel subscription',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Text(
            accessLine,
            key: const ValueKey('plp-billing-cancel-access'),
            style: const TextStyle(color: plpBillingOnInkMuted, fontSize: 13),
          ),
          const SizedBox(height: 22),
          PlpHoldToConfirm(
            key: const ValueKey('plp-billing-hold'),
            label: 'HOLD TO CANCEL',
            busyLabel: 'CANCELLING\u2026',
            busy: busy,
            semanticsActionLabel: 'Cancel subscription now',
            onConfirmed: onConfirmed,
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey('plp-billing-keep'),
            onPressed: busy ? null : onKeep,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: const Text('Keep plan'),
          ),
        ],
      );
}

/// Press and hold for [duration]; releasing early aborts with no effect.
/// Screen readers get a custom semantics action instead of the hold.
class PlpHoldToConfirm extends StatefulWidget {
  const PlpHoldToConfirm({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.semanticsActionLabel,
    required this.onConfirmed,
    this.duration = const Duration(milliseconds: 1500),
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final String semanticsActionLabel;
  final VoidCallback onConfirmed;
  final Duration duration;

  @override
  State<PlpHoldToConfirm> createState() => _PlpHoldToConfirmState();
}

class _PlpHoldToConfirmState extends State<PlpHoldToConfirm>
    with SingleTickerProviderStateMixin {
  // `preserve`: the hold length is a safety interval, so platform reduced
  // motion must never shorten it to an instant tap.
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.duration,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onStatus);
  bool _fired = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _confirm();
  }

  void _confirm() {
    if (_fired || widget.busy) return;
    _fired = true;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  void _start() {
    if (widget.busy || _fired) return;
    _fill.forward();
  }

  void _release() {
    if (_fired || _fill.isCompleted) return;
    if (plpReduceMotion(context)) {
      _fill.value = 0;
    } else {
      _fill.reverse();
    }
  }

  @override
  void didUpdateWidget(PlpHoldToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy && !widget.busy) {
      _fired = false;
      _fill.value = 0;
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: !widget.busy,
        label: widget.busy ? widget.busyLabel : 'Hold to cancel',
        hint: 'Press and hold for one and a half seconds',
        customSemanticsActions: widget.busy
            ? null
            : <CustomSemanticsAction, VoidCallback>{
                CustomSemanticsAction(label: widget.semanticsActionLabel):
                    _confirm,
              },
        child: ExcludeSemantics(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _start(),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x8CFFFFFF)),
              ),
              child: AnimatedBuilder(
                animation: _fill,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _fill.value,
                      child: const ColoredBox(color: Color(0x1FFFFFFF)),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: _fill.value,
                        child: Container(height: 2, color: Colors.white),
                      ),
                    ),
                    Center(
                      child: Text(
                        widget.busy ? widget.busyLabel : widget.label,
                        style: _actionStyle.copyWith(color: Colors.white),
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

/// Black band pinned at the top while PayPal approval is pending.
class PlpBillingWaitingBand extends StatefulWidget {
  const PlpBillingWaitingBand({
    super.key,
    required this.onOpenNavigation,
    required this.onBack,
    required this.onOpenPaypal,
    required this.onCheckAgain,
    required this.checking,
    this.problem,
  });

  final VoidCallback onOpenNavigation;
  final VoidCallback? onBack;
  final VoidCallback? onOpenPaypal;
  final VoidCallback? onCheckAgain;
  final bool checking;
  final String? problem;

  @override
  State<PlpBillingWaitingBand> createState() => _PlpBillingWaitingBandState();
}

class _PlpBillingWaitingBandState extends State<PlpBillingWaitingBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (plpReduceMotion(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = plpReduceMotion(context);
    final top = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    final hasDrawer =
        PandoraNavigationScope.maybeOf(context)?.openDrawer != null;
    return Material(
      key: const ValueKey('plp-billing-waiting'),
      color: plpInk,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14 + top, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (hasDrawer) ...[
                  PandoraMenuButton(onPressed: widget.onOpenNavigation),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox.square(dimension: 44),
                const Expanded(
                  child: Text(
                    'SUBSCRIPTION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontSize: 16,
                      letterSpacing: 2.6,
                    ),
                  ),
                ),
                if (widget.onBack != null)
                  IconButton(
                    key: const ValueKey('plp-billing-back'),
                    onPressed: widget.onBack,
                    tooltip: 'Back',
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            Semantics(
              liveRegion: true,
              child: const Text(
                'Waiting for PayPal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.02,
                  letterSpacing: -.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 1,
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    final w = constraints.maxWidth;
                    final seg = w * .28;
                    final left =
                        reduce ? w * .34 : -seg + (_sweep.value * (w + seg));
                    return ClipRect(
                      child: Stack(
                        children: [
                          Container(color: plpBillingOnInkTrack),
                          Positioned(
                            left: left,
                            width: seg,
                            top: 0,
                            bottom: 0,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('plp-billing-open-paypal'),
                  onPressed: widget.onOpenPaypal,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                    shape: const RoundedRectangleBorder(),
                    textStyle: _actionStyle,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('OPEN PAYPAL'),
                      SizedBox(width: 8),
                      PlpLineIcon(PlpLineGlyph.externalLink,
                          size: 14, color: Colors.white),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                TextButton(
                  key: const ValueKey('plp-billing-check-again'),
                  onPressed: widget.onCheckAgain,
                  style: TextButton.styleFrom(
                    foregroundColor: plpBillingOnInkMuted,
                    disabledForegroundColor: plpBillingOnInkMuted,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                    shape: const RoundedRectangleBorder(),
                    textStyle: _actionStyle,
                  ),
                  child:
                      Text(widget.checking ? 'CHECKING\u2026' : 'CHECK AGAIN'),
                ),
              ],
            ),
            if (widget.problem != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.problem!,
                key: const ValueKey('plp-billing-waiting-problem'),
                style: const TextStyle(
                  color: plpBillingOnInkMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

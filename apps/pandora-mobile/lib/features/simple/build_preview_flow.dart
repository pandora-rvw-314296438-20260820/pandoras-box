import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import '../approvals/approvals_screen.dart';
import '../command/command_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

void _openPreview(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class BuildProgressScreen extends StatelessWidget {
  const BuildProgressScreen({
    super.key,
    required this.receipt,
    required this.request,
    this.releaseRequest = false,
  });

  final IntakeReceipt receipt;
  final String request;
  final bool releaseRequest;

  @override
  Widget build(BuildContext context) {
    final waitingForDecision = receipt.needsApproval;
    final reviewState = waitingForDecision
        ? PandoraFlowStepState.current
        : PandoraFlowStepState.pending;
    final buildState = waitingForDecision
        ? PandoraFlowStepState.pending
        : PandoraFlowStepState.current;
    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: releaseRequest ? 'Release progress' : 'Build progress',
        subtitle: request,
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () => _openPreview(context, const ApprovalsScreen()),
        onAvatar: () => _openPreview(context, const SettingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PandoraFlowStepper(
            steps: [
              const PandoraFlowStep(
                label: 'Ask',
                state: PandoraFlowStepState.complete,
              ),
              const PandoraFlowStep(
                label: 'Understand',
                state: PandoraFlowStepState.complete,
              ),
              PandoraFlowStep(label: 'Build', state: buildState),
              PandoraFlowStep(label: 'Review', state: reviewState),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            waitingForDecision
                ? (releaseRequest
                      ? 'Release is waiting for your decision'
                      : 'Pandora is waiting for your decision')
                : (releaseRequest
                      ? 'Pandora is preparing your release'
                      : 'Pandora is preparing your system'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PandoraSimpleColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            waitingForDecision
                ? 'Nothing will change until you approve the decision in Needs You.'
                : (releaseRequest
                      ? 'Pandora is preparing the reviewed result for final checks, your approval, and a safe release.'
                      : 'Pandora is doing the work and will notify you when your decision is required.'),
            textAlign: TextAlign.center,
            style: pandoraSimpleMutedText,
          ),
          const SizedBox(height: 24),
          _OrbitingBuildMark(
            releaseRequest: releaseRequest,
            active: !waitingForDecision,
          ),
          const SizedBox(height: 22),
          PandoraSimpleCard(
            shadow: false,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _BuildTaskRow(
                  label: 'Understanding your request',
                  detail: receipt.status.whereWeAre,
                  state: _BuildTaskState.complete,
                ),
                _BuildTaskRow(
                  label: 'Designing the user experience',
                  detail: receipt.status.whatChanged,
                  state: _BuildTaskState.complete,
                ),
                _BuildTaskRow(
                  label: releaseRequest
                      ? 'Preparing the release'
                      : 'Building the core system',
                  detail: waitingForDecision
                      ? 'Work is paused until you approve the decision'
                      : receipt.status.whatIsHappeningNow,
                  state: waitingForDecision
                      ? _BuildTaskState.blocked
                      : _BuildTaskState.current,
                ),
                _BuildTaskRow(
                  label: 'Connecting business services',
                  detail: waitingForDecision
                      ? 'This starts only after you approve the decision'
                      : receipt.status.whatIWillDoNext,
                  state: _BuildTaskState.pending,
                ),
                const _BuildTaskRow(
                  label: 'Testing everything',
                  detail: 'Independent checks have not finished yet',
                  state: _BuildTaskState.pending,
                ),
                const _BuildTaskRow(
                  label: 'Verifying the result',
                  detail: 'Pandora will not claim completion before evidence exists',
                  state: _BuildTaskState.pending,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!releaseRequest)
            _PrototypePreviewCard(
              request: request,
              onOpen: () =>
                  _openPreview(context, FirstPreviewScreen(request: request)),
            ),
          if (releaseRequest)
            PandoraSimpleCard(
              shadow: false,
              backgroundColor: PandoraSimpleColors.greenWash,
              borderColor: const Color(0xFFCDE8D4),
              child: Row(
                children: [
                  const PandoraIconBadge(
                    icon: Icons.shield_outlined,
                    foreground: PandoraSimpleColors.green,
                    background: Colors.white,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      receipt.needsApproval
                          ? 'The release request is recorded and waiting in Needs You.'
                          : 'The release request is recorded. Activity and verified release proof show the current status.',
                      style: pandoraSimpleText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  PandoraSecondaryButton(
                    label: receipt.needsApproval
                        ? 'Needs You'
                        : 'Open activity',
                    onPressed: () => _openPreview(
                      context,
                      receipt.needsApproval
                          ? const ApprovalsScreen()
                          : const CommandScreen(
                              initialPrompt: 'Show the current verified release status and supporting proof.',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: PandoraSimpleColors.muted,
                size: 20,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  receipt.needsApproval
                      ? 'Pandora will notify you because a decision is already required.'
                      : 'Pandora will notify you when the next real decision is required.',
                  textAlign: TextAlign.center,
                  style: pandoraSimpleMutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrbitingBuildMark extends StatefulWidget {
  const _OrbitingBuildMark({
    required this.releaseRequest,
    required this.active,
  });

  final bool releaseRequest;
  final bool active;

  @override
  State<_OrbitingBuildMark> createState() => _OrbitingBuildMarkState();
}

class _OrbitingBuildMarkState extends State<_OrbitingBuildMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _OrbitingBuildMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) {
      return;
    }
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frozen = MediaQuery.of(context).disableAnimations || !widget.active;
    final mark = SizedBox(
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final size in <double>[245, 205, 165])
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: PandoraSimpleColors.red.withValues(
                    alpha: size == 245 ? .08 : .13,
                  ),
                ),
              ),
            ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  PandoraSimpleColors.red.withValues(alpha: .16),
                  Colors.transparent,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x35D40A24),
                  blurRadius: 50,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          const PandoraMark(size: 130, color: PandoraSimpleColors.red),
          _OrbitDot(
            controller: _controller,
            radius: 105,
            phase: 0,
            color: PandoraSimpleColors.purple,
            frozen: frozen,
          ),
          _OrbitDot(
            controller: _controller,
            radius: 105,
            phase: .34,
            color: PandoraSimpleColors.green,
            frozen: frozen,
          ),
          _OrbitDot(
            controller: _controller,
            radius: 105,
            phase: .67,
            color: PandoraSimpleColors.red,
            frozen: frozen,
          ),
        ],
      ),
    );
    return mark;
  }
}

class _OrbitDot extends StatelessWidget {
  const _OrbitDot({
    required this.controller,
    required this.radius,
    required this.phase,
    required this.color,
    required this.frozen,
  });

  final AnimationController controller;
  final double radius;
  final double phase;
  final Color color;
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    if (frozen) {
      return Transform.translate(offset: Offset(radius, 0), child: _dot());
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final turns = controller.value + phase;
        return Transform.rotate(
          angle: turns * 6.283185307179586,
          child: Transform.translate(offset: Offset(radius, 0), child: child),
        );
      },
      child: _dot(),
    );
  }

  Widget _dot() => Container(
    width: 15,
    height: 15,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 8)],
    ),
  );
}

enum _BuildTaskState { complete, current, pending, blocked }

class _BuildTaskRow extends StatelessWidget {
  const _BuildTaskRow({
    required this.label,
    required this.detail,
    required this.state,
    this.last = false,
  });

  final String label;
  final String detail;
  final _BuildTaskState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _BuildTaskState.complete => PandoraSimpleColors.green,
      _BuildTaskState.current => PandoraSimpleColors.red,
      _BuildTaskState.blocked => PandoraSimpleColors.amber,
      _BuildTaskState.pending => const Color(0xFFC3C1BD),
    };
    final icon = switch (state) {
      _BuildTaskState.complete => Icons.check_rounded,
      _BuildTaskState.current => Icons.sync_rounded,
      _BuildTaskState.blocked => Icons.priority_high_rounded,
      _BuildTaskState.pending => Icons.circle_outlined,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: .28),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: pandoraSimpleMutedText,
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

class _PrototypePreviewCard extends StatelessWidget {
  const _PrototypePreviewCard({required this.request, required this.onOpen});

  final String request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
    shadow: false,
    borderColor: const Color(0xFFE7C1C8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PandoraStatusPill(
              label: 'Prototype preview',
              icon: Icons.visibility_outlined,
              foreground: PandoraSimpleColors.purple,
              background: PandoraSimpleColors.purpleWash,
            ),
            const SizedBox(height: 12),
            const Text(
              'Preview the proposed experience',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              request,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a prototype. It is not live or production verified.',
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 14),
            PandoraPrimaryButton(
              label: 'Open prototype',
              icon: Icons.open_in_full_rounded,
              onPressed: onOpen,
            ),
          ],
        );
        final miniature = Container(
          width: 150,
          height: 180,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(28),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: const ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          Icons.ac_unit_rounded,
                          color: PandoraSimpleColors.red,
                          size: 19,
                        ),
                        Icon(Icons.menu_rounded, size: 17),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Book Your Aircon Service',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 7),
                    PandoraAirconHero(),
                  ],
                ),
              ),
            ),
          ),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              const SizedBox(height: 16),
              Center(child: miniature),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 20),
            miniature,
          ],
        );
      },
    ),
  );
}

enum _PreviewDevice {
  mobile('Mobile', Icons.phone_android_rounded, 332, 690),
  tablet('Tablet', Icons.tablet_mac_rounded, 520, 660),
  desktop('Desktop', Icons.desktop_windows_outlined, 620, 520);

  const _PreviewDevice(this.label, this.icon, this.width, this.height);
  final String label;
  final IconData icon;
  final double width;
  final double height;
}

class FirstPreviewScreen extends StatefulWidget {
  const FirstPreviewScreen({super.key, required this.request});

  final String request;

  @override
  State<FirstPreviewScreen> createState() => _FirstPreviewScreenState();
}

class _FirstPreviewScreenState extends State<FirstPreviewScreen> {
  _PreviewDevice _device = _PreviewDevice.mobile;

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
    header: PandoraOwnerHeader(
      title: 'Prototype',
      subtitle: widget.request,
      centerBrand: true,
      showBack: true,
      onBack: () => Navigator.of(context).maybePop(),
      onNotifications: () => _openPreview(context, const ApprovalsScreen()),
      onAvatar: () => _openPreview(context, const SettingsScreen()),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PandoraFlowStepper(
          steps: [
            PandoraFlowStep(label: 'Ask', state: PandoraFlowStepState.complete),
            PandoraFlowStep(
              label: 'Understand',
              state: PandoraFlowStepState.complete,
            ),
            PandoraFlowStep(
              label: 'Build',
              state: PandoraFlowStepState.complete,
            ),
            PandoraFlowStep(
              label: 'Review',
              state: PandoraFlowStepState.current,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          "Here's the prototype",
          style: TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Pandora created a reviewable prototype. It is not live and nothing will be released until the governed result is approved and verified.',
          style: pandoraSimpleMutedText,
        ),
        const SizedBox(height: 18),
        PandoraDeviceSelector<_PreviewDevice>(
          values: _PreviewDevice.values,
          selected: _device,
          labelBuilder: (value) => value.label,
          iconBuilder: (value) => value.icon,
          onSelected: (value) => setState(() => _device = value),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final preview = _ResponsivePreviewFrame(
              device: _device,
              child: _BookingPreview(
                interactive: false,
                onContinue: () => _openPreview(
                  context,
                  InteractivePreviewScreen(request: widget.request),
                ),
              ),
            );
            final side = _PreviewSideRail(request: widget.request);
            if (constraints.maxWidth < 640) {
              return Column(
                children: [preview, const SizedBox(height: 18), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: preview),
                const SizedBox(width: 18),
                Expanded(flex: 4, child: side),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final change = PandoraSecondaryButton(
              label: 'Needs changes',
              icon: Icons.edit_outlined,
              onPressed: () => _openPreview(
                context,
                CommandScreen(
                  initialPrompt:
                      'Change the booking preview for "${widget.request}". ',
                ),
              ),
              expanded: constraints.maxWidth < 520,
            );
            final approve = PandoraPrimaryButton(
              label: 'Prototype looks right',
              icon: Icons.check_rounded,
              onPressed: () => _openPreview(
                context,
                InteractivePreviewScreen(request: widget.request),
              ),
              expanded: constraints.maxWidth < 520,
            );
            if (constraints.maxWidth < 520) {
              return Column(
                children: [change, const SizedBox(height: 10), approve],
              );
            }
            return Row(
              children: [
                Expanded(child: change),
                const SizedBox(width: 12),
                Expanded(child: approve),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _ResponsivePreviewFrame extends StatelessWidget {
  const _ResponsivePreviewFrame({required this.device, required this.child});

  final _PreviewDevice device;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth;
      final targetWidth = device.width.clamp(260.0, available).toDouble();
      if (device == _PreviewDevice.mobile) {
        return Center(
          child: PandoraPhoneFrame(
            width: targetWidth,
            height: device.height,
            child: child,
          ),
        );
      }
      return Container(
        width: targetWidth,
        height: device.height,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(
            device == _PreviewDevice.tablet ? 30 : 18,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            device == _PreviewDevice.tablet ? 23 : 11,
          ),
          child: child,
        ),
      );
    },
  );
}

class _PreviewSideRail extends StatelessWidget {
  const _PreviewSideRail({required this.request});

  final String request;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PandoraSimpleCard(
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PandoraIconBadge(
              icon: Icons.shield_outlined,
              foreground: PandoraSimpleColors.blue,
              background: PandoraSimpleColors.blueWash,
              size: 48,
            ),
            const SizedBox(height: 13),
            const Text(
              'What the prototype demonstrates',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const _CapabilityLine('Customers can book online'),
            const _CapabilityLine('You receive booking notifications'),
            const _CapabilityLine('Bookings are managed in one place'),
            const _CapabilityLine('Works on mobile and desktop'),
            const SizedBox(height: 14),
            PandoraPrimaryButton(
              label: 'Open prototype',
              icon: Icons.open_in_full_rounded,
              onPressed: () => _openPreview(
                context,
                InteractivePreviewScreen(request: request),
              ),
              expanded: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      PandoraSimpleCard(
        shadow: false,
        backgroundColor: const Color(0xFFFFF8F8),
        borderColor: const Color(0xFFF0D1D6),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PandoraIconBadge(icon: Icons.tune_rounded, size: 46),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pandora can change anything',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Tell Pandora what feels wrong before approving the result.',
                    style: pandoraSimpleMutedText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: PandoraSimpleColors.green,
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(label, style: pandoraSimpleText)),
      ],
    ),
  );
}

class InteractivePreviewScreen extends StatefulWidget {
  const InteractivePreviewScreen({super.key, required this.request});

  final String request;

  @override
  State<InteractivePreviewScreen> createState() =>
      _InteractivePreviewScreenState();
}

class _InteractivePreviewScreenState extends State<InteractivePreviewScreen> {
  final TextEditingController _feedback = TextEditingController();
  final FocusNode _feedbackFocus = FocusNode();
  final IdempotencyKeyFactory _keys = IdempotencyKeyFactory();
  String _service = 'Aircon Cleaning';
  String _location = 'Makati City';
  DateTime? _date;
  TimeOfDay? _time;
  bool _submitting = false;
  bool _outcomeUnknown = false;
  String? _submissionKey;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    _feedbackFocus.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _date ?? now,
    );
    if (selected != null && mounted) {
      setState(() {
        _date = selected;
        _error = null;
      });
    }
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (selected != null && mounted) {
      setState(() {
        _time = selected;
        _error = null;
      });
    }
  }

  Future<void> _dictateFeedback() async {
    _feedbackFocus.requestFocus();
    final text = await PandoraNativeIo.dictate();
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input is unavailable right now.')),
      );
      return;
    }
    final spacer = _feedback.text.trim().isEmpty ? '' : ' ';
    _feedback.text = '${_feedback.text}$spacer$text';
    _feedback.selection = TextSelection.collapsed(
      offset: _feedback.text.length,
    );
  }

  Future<void> _attachFeedback() async {
    final attachment = await PandoraNativeIo.pickTextAttachment();
    if (!mounted) return;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No supported feedback file was selected.'),
        ),
      );
      return;
    }
    final spacer = _feedback.text.trim().isEmpty ? '' : '\n\n';
    _feedback.text = '${_feedback.text}$spacer${attachment.promptBlock}';
    _feedback.selection = TextSelection.collapsed(
      offset: _feedback.text.length,
    );
  }

  String _releaseIntent(BuildContext context) {
    final date = _date == null
        ? 'not selected'
        : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
    final time = _time?.format(context) ?? 'not selected';
    final feedback = _feedback.text.trim();
    return [
      'Continue to release the reviewed booking-system experience for: ${widget.request}',
      'Interactive preview verification:',
      '- Service: $_service',
      '- Location: $_location',
      '- Date: $date',
      '- Time: $time',
      if (feedback.isNotEmpty) '- Owner feedback: $feedback',
      'Do not bypass ProjectOS approval, exact-source verification, deployment evidence, rollback, or production-readback gates.',
    ].join('\n');
  }

  Future<void> _showBookingSummary() async {
    if (_date == null || _time == null) {
      setState(() {
        _error = 'Choose a date and time before continuing to details.';
      });
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PandoraSimpleColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Booking details',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _SummaryLine(label: 'Service', value: _service),
              _SummaryLine(
                label: 'Date',
                value: '${_date!.month}/${_date!.day}/${_date!.year}',
              ),
              _SummaryLine(label: 'Time', value: _time!.format(context)),
              _SummaryLine(label: 'Location', value: _location),
              const SizedBox(height: 18),
              PandoraPrimaryButton(
                label: 'Return to preview',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(),
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _continueToRelease() async {
    if (_date == null || _time == null) {
      setState(() {
        _error = 'Choose a date and time in the interactive preview before continuing.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    _submissionKey ??= _keys.create('preview-release');
    try {
      final receipt = await PandoraDependencies.of(context).repository.ask(
        message: _releaseIntent(context),
        idempotencyKey: _submissionKey,
      );
      if (!mounted) return;
      setState(() {
        _submissionKey = null;
        _outcomeUnknown = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BuildProgressScreen(
            receipt: receipt,
            request: 'Release the reviewed booking experience',
            releaseRequest: true,
          ),
        ),
      );
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = error.outcomeMayBeUnknown;
        _error = error.outcomeMayBeUnknown
            ? '${error.message} Pandora will not retry the release request. Check Activity first.'
            : error.message;
        if (!error.outcomeMayBeUnknown) _submissionKey = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = true;
        _error = 'Pandora could not confirm the release request. It will not retry the write. Check Activity first.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _requestChanges() {
    final feedback = _feedback.text.trim();
    _openPreview(
      context,
      CommandScreen(
        initialPrompt: feedback.isEmpty
            ? 'Change the interactive booking preview for "${widget.request}". '
            : 'Change the interactive booking preview for "${widget.request}" based on this owner feedback:\n\n$feedback',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
    header: PandoraOwnerHeader(
      title: 'Interactive preview',
      subtitle: widget.request,
      centerBrand: true,
      showBack: true,
      onBack: () => Navigator.of(context).maybePop(),
      onNotifications: () => _openPreview(context, const ApprovalsScreen()),
      onAvatar: () => _openPreview(context, const SettingsScreen()),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PandoraFlowStepper(
          steps: [
            PandoraFlowStep(label: 'Ask', state: PandoraFlowStepState.complete),
            PandoraFlowStep(
              label: 'Understand',
              state: PandoraFlowStepState.complete,
            ),
            PandoraFlowStep(
              label: 'Build',
              state: PandoraFlowStepState.complete,
            ),
            PandoraFlowStep(
              label: 'Review',
              state: PandoraFlowStepState.complete,
            ),
            PandoraFlowStep(
              label: 'Preview',
              state: PandoraFlowStepState.current,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Try your new system',
          style: TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'This is an interactive preview. Test it like a real customer before approving a release.',
          style: pandoraSimpleMutedText,
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final phone = Center(
              child: PandoraPhoneFrame(
                width: constraints.maxWidth < 430
                    ? constraints.maxWidth.clamp(286.0, 356.0).toDouble()
                    : 356,
                height: 760,
                child: _BookingPreview(
                  interactive: true,
                  service: _service,
                  location: _location,
                  date: _date,
                  time: _time,
                  onServiceChanged: (value) => setState(() => _service = value),
                  onLocationChanged: (value) =>
                      setState(() => _location = value),
                  onChooseDate: _chooseDate,
                  onChooseTime: _chooseTime,
                  onContinue: _showBookingSummary,
                ),
              ),
            );
            final side = _InteractiveSideRail(
              feedback: _feedback,
              feedbackFocus: _feedbackFocus,
              onDictate: _dictateFeedback,
              onAttach: _attachFeedback,
            );
            if (constraints.maxWidth < 650) {
              return Column(
                children: [phone, const SizedBox(height: 18), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: phone),
                const SizedBox(width: 18),
                Expanded(flex: 4, child: side),
              ],
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          PandoraSimpleCard(
            shadow: false,
            backgroundColor: const Color(0xFFFFF4F5),
            borderColor: const Color(0xFFF0C3CA),
            child: Text(
              _error!,
              style: const TextStyle(
                color: PandoraSimpleColors.deepRed,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final change = PandoraSecondaryButton(
              label: 'Needs changes',
              icon: Icons.edit_outlined,
              onPressed: _outcomeUnknown || _submitting
                  ? null
                  : _requestChanges,
              expanded: constraints.maxWidth < 520,
            );
            final approve = PandoraPrimaryButton(
              label: _submitting
                  ? 'Submitting safely…'
                  : 'Looks good, continue',
              icon: Icons.check_rounded,
              loading: _submitting,
              onPressed: _outcomeUnknown || _submitting
                  ? null
                  : _continueToRelease,
              expanded: constraints.maxWidth < 520,
            );
            if (constraints.maxWidth < 520) {
              return Column(
                children: [change, const SizedBox(height: 10), approve],
              );
            }
            return Row(
              children: [
                Expanded(child: change),
                const SizedBox(width: 12),
                Expanded(child: approve),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _InteractiveSideRail extends StatelessWidget {
  const _InteractiveSideRail({
    required this.feedback,
    required this.feedbackFocus,
    required this.onDictate,
    required this.onAttach,
  });

  final TextEditingController feedback;
  final FocusNode feedbackFocus;
  final VoidCallback onDictate;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PandoraSimpleCard(
        shadow: false,
        backgroundColor: const Color(0xFFFFF8F8),
        borderColor: const Color(0xFFF0D1D6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                PandoraIconBadge(
                  icon: Icons.record_voice_over_outlined,
                  size: 46,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Talk to Pandora while you test',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedback,
              focusNode: feedbackFocus,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText: 'Make the button larger…\nChange the colors…',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Speak feedback',
                  onPressed: onDictate,
                  icon: const Icon(Icons.mic_none_rounded),
                  color: PandoraSimpleColors.red,
                ),
                IconButton(
                  tooltip: 'Attach feedback',
                  onPressed: onAttach,
                  icon: const Icon(Icons.attach_file_rounded),
                  color: PandoraSimpleColors.red,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const PandoraSimpleCard(
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PandoraIconBadge(
                  icon: Icons.checklist_rounded,
                  foreground: PandoraSimpleColors.blue,
                  background: PandoraSimpleColors.blueWash,
                  size: 46,
                ),
                SizedBox(width: 12),
                Text(
                  'Key features',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            _CapabilityLine('Service selection'),
            _CapabilityLine('Date & time picker'),
            _CapabilityLine('Customer location'),
            _CapabilityLine('Booking confirmation'),
            _CapabilityLine('Mobile responsive'),
          ],
        ),
      ),
    ],
  );
}

class _BookingPreview extends StatelessWidget {
  const _BookingPreview({
    required this.interactive,
    required this.onContinue,
    this.service = 'Aircon Cleaning',
    this.location = 'Makati City',
    this.date,
    this.time,
    this.onServiceChanged,
    this.onLocationChanged,
    this.onChooseDate,
    this.onChooseTime,
  });

  final bool interactive;
  final String service;
  final String location;
  final DateTime? date;
  final TimeOfDay? time;
  final ValueChanged<String>? onServiceChanged;
  final ValueChanged<String>? onLocationChanged;
  final VoidCallback? onChooseDate;
  final VoidCallback? onChooseTime;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final dateLabel = date == null
        ? 'Select a date'
        : '${date!.month}/${date!.day}/${date!.year}';
    final timeLabel = time?.format(context) ?? 'Select a time';
    return ColoredBox(
      color: const Color(0xFFF7F4EF),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                PandoraMark(size: 30, color: PandoraSimpleColors.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CoolAir Services',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.menu_rounded, color: PandoraSimpleColors.ink),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Book Your Aircon Service',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 25,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Professional. Reliable. Done right.',
              style: TextStyle(color: PandoraSimpleColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const PandoraAirconHero(),
            const SizedBox(height: 18),
            const Text(
              'Choose a service',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (interactive)
              DropdownButtonFormField<String>(
                initialValue: service,
                items: const [
                  DropdownMenuItem(
                    value: 'Aircon Cleaning',
                    child: Text('Aircon Cleaning'),
                  ),
                  DropdownMenuItem(
                    value: 'Repair Service',
                    child: Text('Repair Service'),
                  ),
                  DropdownMenuItem(
                    value: 'Installation',
                    child: Text('Installation'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onServiceChanged?.call(value);
                },
              )
            else
              const _PreviewField(label: 'Aircon Cleaning'),
            const SizedBox(height: 13),
            const Text(
              'Choose date & time',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PreviewField(
                    label: dateLabel,
                    icon: Icons.calendar_today_outlined,
                    onTap: interactive ? onChooseDate : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PreviewField(
                    label: timeLabel,
                    icon: Icons.schedule_rounded,
                    onTap: interactive ? onChooseTime : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            const Text(
              'Your location',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (interactive)
              DropdownButtonFormField<String>(
                initialValue: location,
                items: const [
                  DropdownMenuItem(
                    value: 'Makati City',
                    child: Text('Makati City'),
                  ),
                  DropdownMenuItem(
                    value: 'Taguig City',
                    child: Text('Taguig City'),
                  ),
                  DropdownMenuItem(
                    value: 'Pasay City',
                    child: Text('Pasay City'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onLocationChanged?.call(value);
                },
              )
            else
              const _PreviewField(
                label: 'Makati City',
                icon: Icons.location_on_outlined,
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: PandoraSimpleColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                interactive ? 'Continue to details' : 'Try this preview',
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: PandoraSimpleColors.muted,
                ),
                SizedBox(width: 5),
                Text(
                  'Secure booking · No payment yet',
                  style: TextStyle(
                    color: PandoraSimpleColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      constraints: const BoxConstraints(minHeight: 51),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDEDCD8)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: PandoraSimpleColors.muted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 13,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: PandoraSimpleColors.muted,
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: body,
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: PandoraSimpleColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: PandoraSimpleColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

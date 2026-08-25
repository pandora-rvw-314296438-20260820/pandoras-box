import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../approvals/approvals_screen.dart';
import '../command/command_screen.dart';

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
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: PandoraPage(
        title: releaseRequest ? 'Release progress' : 'Build progress',
        subtitle: request,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraSurface(
              title: releaseRequest
                  ? 'Pandora is governing the release request'
                  : 'Pandora is turning intent into working software',
              subtitle: 'Only verified runtime state is shown. Submission is never presented as completion.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 650),
                    tween: Tween<double>(
                      begin: 0,
                      end: receipt.needsApproval ? .5 : .68,
                    ),
                    builder: (context, value, _) =>
                        LinearProgressIndicator(value: value),
                  ),
                  const SizedBox(height: PandoraSpacing.lg),
                  const _ProgressStage(
                    number: 1,
                    label: 'Ask',
                    detail: 'Request received',
                    complete: true,
                  ),
                  _ProgressStage(
                    number: 2,
                    label: 'Understand',
                    detail: receipt.status.whereWeAre,
                    complete: true,
                  ),
                  _ProgressStage(
                    number: 3,
                    label: 'Build',
                    detail: receipt.status.whatIsHappeningNow,
                    current: true,
                  ),
                  _ProgressStage(
                    number: 4,
                    label: 'Review',
                    detail: receipt.needsApproval
                        ? 'Owner decision required before protected execution'
                        : receipt.status.whatIWillDoNext,
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Detailed work state',
              child: Column(
                children: [
                  _DetailLine(
                    label: 'What changed',
                    value: receipt.status.whatChanged,
                  ),
                  _DetailLine(
                    label: 'What is done',
                    value: receipt.status.whatIsDone,
                  ),
                  _DetailLine(
                    label: 'What happens now',
                    value: receipt.status.whatIsHappeningNow,
                  ),
                  if (receipt.status.whatIsStoppingUs != null)
                    _DetailLine(
                      label: 'What is stopping us',
                      value: receipt.status.whatIsStoppingUs!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            const PandoraSurface(
              title: 'Background behavior',
              child: Text(
                'You can leave this screen. Governed execution runs server-side. Needs You and Activity are the source of truth when you return, and preview status never invents provider completion.',
              ),
            ),
            const SizedBox(height: PandoraSpacing.md),
            if (receipt.needsApproval)
              OutlinedButton.icon(
                onPressed: () => _openPreview(context, const ApprovalsScreen()),
                icon: const Icon(Icons.approval_outlined),
                label: const Text('Open Needs You'),
              ),
            if (!releaseRequest) ...[
              const SizedBox(height: PandoraSpacing.xs),
              FilledButton.icon(
                onPressed: () =>
                    _openPreview(context, FirstPreviewScreen(request: request)),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Open first preview'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressStage extends StatelessWidget {
  const _ProgressStage({
    required this.number,
    required this.label,
    required this.detail,
    this.complete = false,
    this.current = false,
  });

  final int number;
  final String label;
  final String detail;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PandoraSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: complete || current
              ? Theme.of(context).colorScheme.primaryContainer
              : context.pandoraPalette.subtleSurface,
          child: complete
              ? const Icon(Icons.check_rounded, size: 20)
              : Text('$number'),
        ),
        const SizedBox(width: PandoraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: PandoraSpacing.xxs),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: PandoraSpacing.sm),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

enum _PreviewDevice {
  mobile('Mobile', 390),
  tablet('Tablet', 760),
  desktop('Desktop', 1180);

  const _PreviewDevice(this.label, this.width);
  final String label;
  final double width;
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
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: 'First preview',
      subtitle: 'Review the experience before any launch decision.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_PreviewDevice>(
            segments: [
              for (final device in _PreviewDevice.values)
                ButtonSegment<_PreviewDevice>(
                  value: device,
                  label: Text(device.label),
                ),
            ],
            selected: {_device},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _device = selection.first),
          ),
          const SizedBox(height: PandoraSpacing.md),
          PandoraSurface(
            title: '${_device.label} preview',
            subtitle: 'A responsive booking experience from the approved Pandora master flow.',
            child: SizedBox(
              height: 430,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: _device.width,
                  height: 700,
                  child: const _BookingPreviewCard(interactive: false),
                ),
              ),
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
          const PandoraSurface(
            title: 'Included in this preview',
            child: Column(
              children: [
                _FeatureLine('Choose a service', true),
                _FeatureLine('Choose a date and time', true),
                _FeatureLine('Choose a location', true),
                _FeatureLine(
                  'Responsive mobile, tablet, and desktop layout',
                  true,
                ),
                _FeatureLine(
                  'Launch status',
                  false,
                  detail: 'Not released — owner review comes first',
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openPreview(
                    context,
                    CommandScreen(
                      initialPrompt:
                          'Change the booking preview for "${widget.request}". ',
                    ),
                  ),
                  child: const Text('Needs changes'),
                ),
              ),
              const SizedBox(width: PandoraSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => _openPreview(
                    context,
                    InteractivePreviewScreen(request: widget.request),
                  ),
                  child: const Text('Looks great'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine(this.label, this.ready, {this.detail});
  final String label;
  final bool ready;
  final String? detail;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
      color: ready ? context.pandoraPalette.verified : null,
    ),
    title: Text(label),
    subtitle: detail == null ? null : Text(detail!),
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
  String _service = 'Consultation';
  String _location = 'Main branch';
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
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (selected != null && mounted) setState(() => _time = selected);
  }

  Future<void> _dictateFeedback() async {
    _feedbackFocus.requestFocus();
    final text = await PandoraNativeIo.dictate();
    if (!mounted || text == null) return;
    final spacer = _feedback.text.trim().isEmpty ? '' : ' ';
    _feedback.text = '${_feedback.text}$spacer$text';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: 'Interactive preview',
      subtitle:
          'Use the booking flow exactly as a customer would before release.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BookingPreviewCard(
            interactive: true,
            service: _service,
            location: _location,
            date: _date,
            time: _time,
            onServiceChanged: (value) => setState(() => _service = value),
            onLocationChanged: (value) => setState(() => _location = value),
            onChooseDate: _chooseDate,
            onChooseTime: _chooseTime,
          ),
          const SizedBox(height: PandoraSpacing.md),
          const PandoraSurface(
            title: 'Feature verification',
            child: Column(
              children: [
                _FeatureLine('Service selection works', true),
                _FeatureLine('Date selection works', true),
                _FeatureLine('Time selection works', true),
                _FeatureLine('Location selection works', true),
                _FeatureLine(
                  'Protected release still requires governance',
                  true,
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
          PandoraSurface(
            title: 'Feedback',
            subtitle: 'Write or dictate changes. Feedback is included in the governed release request.',
            child: Column(
              children: [
                TextField(
                  controller: _feedback,
                  focusNode: _feedbackFocus,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Anything Pandora should adjust before release?',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _outcomeUnknown || _submitting
                        ? null
                        : _dictateFeedback,
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Voice feedback'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: PandoraSpacing.sm),
            Container(
              padding: const EdgeInsets.all(PandoraSpacing.md),
              decoration: BoxDecoration(
                color: context.pandoraPalette.subtleSurface,
                borderRadius: PandoraRadius.controlBorder,
                border: Border.all(color: context.pandoraPalette.outlineSoft),
              ),
              child: Text(_error!),
            ),
          ],
          const SizedBox(height: PandoraSpacing.md),
          FilledButton.icon(
            onPressed: _outcomeUnknown || _submitting
                ? null
                : _continueToRelease,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.rocket_launch_outlined),
            label: Text(
              _submitting ? 'Sending release request…' : 'Continue to release',
            ),
          ),
          const SizedBox(height: PandoraSpacing.xs),
          Text(
            'This sends a governed release request. It does not directly deploy or bypass Needs You.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BookingPreviewCard extends StatelessWidget {
  const _BookingPreviewCard({
    required this.interactive,
    this.service = 'Consultation',
    this.location = 'Main branch',
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

  @override
  Widget build(BuildContext context) {
    final dateLabel = date == null
        ? 'Choose date'
        : '${date!.month}/${date!.day}/${date!.year}';
    final timeLabel = time?.format(context) ?? 'Choose time';
    return PandoraSurface(
      title: 'Book an appointment',
      subtitle: 'Fast, clear, and mobile-first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (interactive)
            DropdownButtonFormField<String>(
              initialValue: service,
              decoration: const InputDecoration(labelText: 'Service'),
              items: const [
                DropdownMenuItem(
                  value: 'Consultation',
                  child: Text('Consultation'),
                ),
                DropdownMenuItem(
                  value: 'Premium service',
                  child: Text('Premium service'),
                ),
                DropdownMenuItem(value: 'Follow-up', child: Text('Follow-up')),
              ],
              onChanged: (value) {
                if (value != null) onServiceChanged?.call(value);
              },
            )
          else
            const _PreviewField(
              icon: Icons.design_services_outlined,
              label: 'Service',
              value: 'Consultation',
            ),
          const SizedBox(height: PandoraSpacing.sm),
          if (interactive)
            DropdownButtonFormField<String>(
              initialValue: location,
              decoration: const InputDecoration(labelText: 'Location'),
              items: const [
                DropdownMenuItem(
                  value: 'Main branch',
                  child: Text('Main branch'),
                ),
                DropdownMenuItem(value: 'Online', child: Text('Online')),
                DropdownMenuItem(
                  value: 'Client location',
                  child: Text('Client location'),
                ),
              ],
              onChanged: (value) {
                if (value != null) onLocationChanged?.call(value);
              },
            )
          else
            const _PreviewField(
              icon: Icons.place_outlined,
              label: 'Location',
              value: 'Main branch',
            ),
          const SizedBox(height: PandoraSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: interactive ? onChooseDate : null,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(dateLabel),
                ),
              ),
              const SizedBox(width: PandoraSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: interactive ? onChooseTime : null,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(timeLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
          FilledButton(
            onPressed: interactive ? () {} : null,
            child: const Text('Continue booking'),
          ),
          const SizedBox(height: PandoraSpacing.xs),
          Text(
            'No payment is taken in this preview.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PandoraSpacing.md),
    decoration: BoxDecoration(
      color: context.pandoraPalette.subtleSurface,
      borderRadius: PandoraRadius.controlBorder,
      border: Border.all(color: context.pandoraPalette.outlineSoft),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: PandoraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../core/design/pandora_tokens.dart';
import '../../core/local_ai/pandora_local_ai.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/status_badge.dart';

class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  PandoraLocalAiStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await PandoraLocalAi.instance.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _chooseModel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await PandoraLocalAi.instance.chooseModel();
      if (!mounted) return;
      if (selected != null) {
        setState(() => _status = selected);
        final warmed = await PandoraLocalAi.instance.warm();
        if (!mounted) return;
        if (!warmed) {
          setState(() {
            _error =
                'The model was imported, but Pandora could not warm it yet.';
          });
        } else {
          await _refresh();
        }
      }
    } on PandoraLocalAiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _warm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final warmed = await PandoraLocalAi.instance.warm();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!warmed) {
        _error = 'Pandora could not warm the selected local model.';
      }
    });
    await _refresh();
  }

  Future<void> _unload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await PandoraLocalAi.instance.unload();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Unknown size';
    final gib = bytes / (1024 * 1024 * 1024);
    return '${gib.toStringAsFixed(2)} GiB';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final supported = status?.supported ?? true;
    final configured = status?.configured ?? false;
    final loaded = status?.loaded ?? false;

    return PandoraPage(
      title: 'On-device AI',
      subtitle: 'Fast private inference for routine Pandora conversation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerBriefingHero(
            eyebrow: 'Local intelligence',
            title: loaded
                ? 'Local AI is warm'
                : configured
                ? 'Local model is ready to warm'
                : 'Choose your local model',
            message: loaded
                ? 'Routine chat can start on your phone and escalate to cloud intelligence only when needed.'
                : 'For this phone, Qwen2.5 3B Instruct Q4_K_M is the current benchmarked sweet spot.',
            icon: Icons.memory_rounded,
            tone: loaded
                ? PandoraStatusTone.verified
                : PandoraStatusTone.informative,
            statusLabel: loaded ? 'Ready' : 'Local-first setup',
          ),
          const SizedBox(height: PandoraSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(PandoraSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status?.modelName ?? 'No GGUF selected',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: PandoraSpacing.xs),
                  Text(
                    configured
                        ? '${_sizeLabel(status?.modelBytes)} · ${status?.engineState ?? 'not loaded'}'
                        : supported
                        ? 'Select the GGUF already downloaded on this phone.'
                        : 'Local inference is available on the Android build.',
                  ),
                  if (status?.modelSha256 != null) ...[
                    const SizedBox(height: PandoraSpacing.xs),
                    Text(
                      'SHA-256 ${status!.modelSha256}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: PandoraSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: PandoraSpacing.md),
          FilledButton.icon(
            onPressed: _busy || !supported ? null : _chooseModel,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_rounded),
            label: Text(configured ? 'Choose another GGUF' : 'Choose GGUF'),
          ),
          if (configured) ...[
            const SizedBox(height: PandoraSpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : loaded
                  ? _unload
                  : _warm,
              icon: Icon(
                loaded ? Icons.power_settings_new_rounded : Icons.bolt_rounded,
              ),
              label: Text(loaded ? 'Unload local model' : 'Warm local model'),
            ),
          ],
          const SizedBox(height: PandoraSpacing.lg),
          const Text(
            'The selected GGUF is copied into Pandora private app storage. '
            'Routine local chat stays on-device. Requests that require live '
            'data, connected services, external actions, projects, or '
            'attachments continue through Pandora cloud intelligence.',
          ),
        ],
      ),
    );
  }
}

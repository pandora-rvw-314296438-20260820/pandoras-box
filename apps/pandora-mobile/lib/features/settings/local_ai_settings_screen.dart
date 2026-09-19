import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/design/pandora_tokens.dart';
import '../../core/local_ai/pandora_local_ai.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/status_badge.dart';
import '../../pandora_config.dart';

class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  PandoraLocalAiStatus? _status;
  bool _busy = false;
  String? _error;
  Map<String, Object?>? _acceptanceChallenge;
  Map<String, Object?>? _pendingAcceptanceEvidence;
  Map<String, Object?>? _acceptanceReceipt;
  String? _acceptanceStatus;

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
    try {
      final warmed = await PandoraLocalAi.instance.warm();
      if (!mounted) return;
      if (!warmed) {
        setState(() {
          _error = 'Pandora could not warm the selected local model.';
        });
      }
      await _refresh();
    } on PandoraLocalAiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Map<String, Object?> _record(Object? raw) {
    if (raw is! Map) {
      throw const PandoraLocalAiException(
        'Pandora received invalid acceptance evidence.',
      );
    }
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) (entry.key as String): entry.value,
    };
  }

  Future<void> _runPhysicalAcceptance() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;

      if (_pendingAcceptanceEvidence != null &&
          _acceptanceChallenge != null) {
        final challenge = _acceptanceChallenge!;
        final receipt = _record(
          await client.rpc(
            'capture_phone_local_ai_acceptance',
            params: <String, Object?>{
              'p_challenge_id': challenge['challengeId'],
              'p_nonce': challenge['nonce'],
              'p_evidence': _pendingAcceptanceEvidence,
            },
          ),
        );
        if (!mounted) return;
        setState(() {
          _acceptanceReceipt = receipt;
          _pendingAcceptanceEvidence = null;
          _acceptanceChallenge = null;
          _acceptanceStatus =
              'VERIFIED · physical offline local inference receipt captured.';
        });
        await _refresh();
        return;
      }

      if (_acceptanceChallenge == null) {
        final challenge = _record(
          await client.rpc(
            'begin_phone_local_ai_acceptance',
            params: <String, Object?>{
              'p_organization_id': PandoraConfig.organizationId,
              'p_source_sha': PandoraConfig.sourceRevision,
            },
          ),
        );
        if (!mounted) return;
        setState(() {
          _acceptanceChallenge = challenge;
          _acceptanceStatus =
              'Challenge ready. Turn off Wi-Fi and mobile data, then run the offline test.';
        });
      }

      final challenge = _acceptanceChallenge!;
      final evidence = await PandoraLocalAi.instance.runAcceptance(
        sourceSha: PandoraConfig.sourceRevision,
        challengeNonce: challenge['nonce'].toString(),
        expectedApkSha256: challenge['expectedApkSha256'].toString(),
      );
      if (!mounted) return;
      setState(() {
        _pendingAcceptanceEvidence = evidence;
        _acceptanceStatus =
            'Offline local test passed. Reconnect to the internet, then submit the receipt.';
      });
    } on PandoraLocalAiException catch (error) {
      if (!mounted) return;
      final offlineRequired =
          error.message.toLowerCase().contains('wi-fi and mobile data');
      setState(() {
        if (offlineRequired && _acceptanceChallenge != null) {
          _acceptanceStatus =
              'Challenge ready. Turn off Wi-Fi and mobile data, then tap again.';
        } else {
          _error = error.message;
        }
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        if (_pendingAcceptanceEvidence != null) {
          _acceptanceStatus =
              'Receipt not submitted. Reconnect and tap again; the offline evidence is still pending.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora could not complete physical local-AI acceptance.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Unknown size';
    final gib = bytes / (1024 * 1024 * 1024);
    return '${gib.toStringAsFixed(2)} GiB';
  }

  String _bytesLabel(Object? raw) {
    final bytes = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    if (bytes == null || bytes <= 0) return 'n/a';
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2) + ' GiB';
  }

  String _metric(Object? raw, {int fractionDigits = 0}) {
    if (raw == null) return 'n/a';
    if (raw is num) return raw.toStringAsFixed(fractionDigits);
    return raw.toString();
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
                : 'Qwen2.5 3B Instruct Q4_K_M is the current primary local-model candidate; physical-phone benchmarking is still required.',
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
          if (status != null) ...[
            const SizedBox(height: PandoraSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(PandoraSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local AI diagnostics',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: PandoraSpacing.xs),
                    Text(
                      'Backend ' +
                          (status.diagnostics['runtimeBackendConfigured']?.toString() ?? 'unknown') +
                          ' · ABI ' +
                          (status.diagnostics['runtimeNativeAbi']?.toString() ?? 'unknown') +
                          ' · accelerator verified ' +
                          (status.diagnostics['acceleratorVerified'] == true ? 'yes' : 'no'),
                    ),
                    Text(
                      (status.diagnostics['manufacturer']?.toString() ?? '') +
                          ' ' +
                          (status.diagnostics['model']?.toString() ?? '') +
                          ' · Android ' +
                          (status.diagnostics['androidVersion']?.toString() ?? 'unknown') +
                          ' · SoC ' +
                          (status.diagnostics['socModel']?.toString() ?? 'not exposed'),
                    ),
                    Text(
                      'RAM ' +
                          _bytesLabel(status.diagnostics['availableRamBytes']) +
                          ' free / ' +
                          _bytesLabel(status.diagnostics['totalRamBytes']) +
                          ' total · storage ' +
                          _bytesLabel(status.diagnostics['availableStorageBytes']) +
                          ' free',
                    ),
                    Text(
                      'Thermal ' +
                          (status.diagnostics['thermalStatus']?.toString() ?? 'not exposed') +
                          ' · battery ' +
                          (status.diagnostics['batteryPercent']?.toString() ?? 'n/a') +
                          '% · charging ' +
                          (status.diagnostics['charging']?.toString() ?? 'n/a'),
                    ),
                    Text(
                      'Load ' +
                          _metric(status.diagnostics['lastModelLoadMs']) +
                          ' ms · TTFT ' +
                          _metric(status.diagnostics['lastTimeToFirstTokenMs']) +
                          ' ms · ' +
                          _metric(
                            status.diagnostics['tokensPerSecond'],
                            fractionDigits: 2,
                          ) +
                          ' token-events/s',
                    ),
                    Text(
                      'GPU used no · NPU used no · NNAPI used no · Vulkan exposed ' +
                          (status.diagnostics['vulkanFeatureExposed']?.toString() ?? 'unknown'),
                    ),
                    if (PandoraLocalAiRouter.lastDecision != null)
                      Text(
                        'Last routing reason: ' +
                            PandoraLocalAiRouter.lastDecision!.reason,
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_acceptanceStatus != null) ...[
            const SizedBox(height: PandoraSpacing.sm),
            Text(
              _acceptanceStatus!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_acceptanceReceipt != null)
              Text(
                'Receipt ' +
                    (_acceptanceReceipt!['receiptSha256']?.toString() ??
                        'captured'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
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
            const SizedBox(height: PandoraSpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : _runPhysicalAcceptance,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(
                _pendingAcceptanceEvidence != null
                    ? 'Submit physical acceptance'
                    : _acceptanceChallenge != null
                    ? 'Run offline acceptance'
                    : 'Prepare physical acceptance',
              ),
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

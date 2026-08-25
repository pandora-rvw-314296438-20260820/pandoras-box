import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../diagnostics/diagnostics_sanitizer.dart';

/// Owner-readable replacement for the raw Flutter error screen.
///
/// This never renders a stack trace, a provider payload, or any credential
/// material. The sanitized technical reference stays collapsed behind a
/// deliberate disclosure so the owner sees a calm, truthful explanation first.
class PandoraErrorFallback extends StatefulWidget {
  const PandoraErrorFallback({
    super.key,
    required this.surface,
    this.reference,
    this.onRetry,
  });

  /// Owner-facing name of what failed, for example `Portfolio Intelligence`.
  final String surface;

  /// Already-sanitized technical reference. Never a raw exception.
  final String? reference;

  final VoidCallback? onRetry;

  @override
  State<PandoraErrorFallback> createState() => _PandoraErrorFallbackState();
}

class _PandoraErrorFallbackState extends State<PandoraErrorFallback> {
  bool _showTechnical = false;

  @override
  Widget build(BuildContext context) {
    // This widget can be mounted by ErrorWidget.builder anywhere in the tree,
    // including above the app theme, so it must not assume any ancestor.
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final palette = dark ? PandoraPalette.graphite : PandoraPalette.porcelain;
    final onCanvas = dark ? const Color(0xFFE7E8EE) : const Color(0xFF1B1C21);
    final muted = dark ? const Color(0xFF9FA1AC) : const Color(0xFF5C5E68);
    final canGoBack = Navigator.maybeOf(context)?.canPop() ?? false;

    return Material(
      type: MaterialType.canvas,
      color: palette.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PandoraSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.report_gmailerrorred_rounded,
                    size: 36,
                    color: palette.attention,
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                  Text(
                    '${widget.surface} could not be displayed.',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: onCanvas,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.xs),
                  Text(
                    'Your project data is safe. Nothing was changed.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: PandoraSpacing.xl),
                  if (widget.onRetry != null) ...[
                    FilledButton(
                      onPressed: widget.onRetry,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: PandoraSpacing.sm),
                  ],
                  if (canGoBack)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Go back'),
                    ),
                  if (widget.reference != null) ...[
                    const SizedBox(height: PandoraSpacing.sm),
                    TextButton(
                      onPressed: () =>
                          setState(() => _showTechnical = !_showTechnical),
                      child: Text(
                        _showTechnical
                            ? 'Hide technical details'
                            : 'View technical details',
                      ),
                    ),
                    if (_showTechnical)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(PandoraSpacing.sm),
                        decoration: BoxDecoration(
                          color: palette.subtleSurface,
                          borderRadius: PandoraRadius.controlBorder,
                          border: Border.all(color: palette.outlineSoft),
                        ),
                        child: Text(
                          widget.reference!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Installs the application-level error strategy.
///
/// Replaces the raw red error screen with an owner-readable surface and routes
/// framework and asynchronous errors through the sanitizer before they are
/// recorded. Call once during bootstrap.
void installPandoraErrorHandling({
  required void Function(String summary) record,
}) {
  ErrorWidget.builder = (details) => PandoraErrorFallback(
    surface: 'This screen',
    reference: _reference(details.exception),
  );

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    record(_reference(details.exception));
    if (kDebugMode && previousOnError != null) {
      previousOnError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    record(_reference(error));
    return true;
  };
}

const _sanitizer = DiagnosticsSanitizer();

/// Produces a short, sanitized reference. Never a stack trace or raw payload.
String _reference(Object error) {
  final type = error.runtimeType.toString();
  final sanitized = _sanitizer.sanitizeText(error.toString());
  final trimmed = sanitized.length > 160
      ? '${sanitized.substring(0, 160)}…'
      : sanitized;
  return '$type: $trimmed';
}

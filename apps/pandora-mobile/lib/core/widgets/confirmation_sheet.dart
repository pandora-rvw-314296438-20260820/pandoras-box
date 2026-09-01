import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

Future<bool?> showPandoraConfirmation({
  required BuildContext context,
  required String title,
  required String consequence,
  required String confirmLabel,
  String cancelLabel = 'Go back',
  bool destructive = false,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          PandoraSpacing.xl,
          PandoraSpacing.sm,
          PandoraSpacing.xl,
          PandoraSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child:
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: PandoraSpacing.sm),
            Text(consequence, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: PandoraSpacing.xl),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: context.pandoraPalette.critical,
                      foregroundColor: context.pandoraPalette.onCritical,
                    )
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: PandoraSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
          ],
        ),
      ),
    );

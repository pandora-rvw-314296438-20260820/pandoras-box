import 'package:flutter/material.dart';

import 'pandora_auth.dart';

Future<bool> verifyCoreIdentity(BuildContext context, PandoraAuth? auth) async {
  if (auth is! ExtraIdentityVerificationSource) return false;
  final source = auth as ExtraIdentityVerificationSource;
  List<ExtraIdentityFactor> factors;
  try {
    factors = await source.verifiedExtraIdentityFactors();
  } catch (_) {
    return false;
  }
  if (!context.mounted || factors.isEmpty) return false;
  var code = '';
  var selected = factors.first.id;
  String? error;
  bool busy = false;
  final verified = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Verify your identity'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (factors.length > 1)
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              items: [
                for (final factor in factors)
                  DropdownMenuItem(value: factor.id, child: Text(factor.label)),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => selected = value ?? selected),
            ),
          TextField(
            onChanged: (value) => code = value,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
                labelText: 'Authenticator code', counterText: ''),
          ),
          if (error != null) Text(error!),
        ]),
        actions: [
          TextButton(
              onPressed:
                  busy ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await source.verifyExtraIdentity(
                          factorId: selected, code: code.trim());
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (_) {
                      if (dialogContext.mounted) {
                        setState(() {
                          busy = false;
                          error = 'The code could not be verified. Try again.';
                        });
                      }
                    }
                  },
            child: Text(busy ? 'Verifying…' : 'Verify'),
          ),
        ],
      ),
    ),
  );
  return verified == true;
}

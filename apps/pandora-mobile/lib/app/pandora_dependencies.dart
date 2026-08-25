import 'package:flutter/widgets.dart';

import '../core/data/pandora_repository.dart';
import '../core/diagnostics/diagnostics_store.dart';
import '../core/security/pandora_auth.dart';

class PandoraDependencies extends InheritedWidget {
  const PandoraDependencies({
    super.key,
    required this.auth,
    required this.repository,
    required this.diagnostics,
    required super.child,
  });

  final PandoraAuth auth;
  final PandoraRepository repository;
  final DiagnosticsStore diagnostics;

  static PandoraDependencies of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<PandoraDependencies>();
    assert(result != null, 'PandoraDependencies is missing above this widget.');
    return result!;
  }

  @override
  bool updateShouldNotify(PandoraDependencies oldWidget) =>
      auth != oldWidget.auth ||
      repository != oldWidget.repository ||
      diagnostics != oldWidget.diagnostics;
}

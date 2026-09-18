import 'package:flutter/foundation.dart';

class EnterpriseCommandDraftBus {
  EnterpriseCommandDraftBus._();

  static final EnterpriseCommandDraftBus shared = EnterpriseCommandDraftBus._();

  final ValueNotifier<String?> draft = ValueNotifier<String?>(null);

  void offer(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    draft.value = normalized;
  }

  void consume() {
    if (draft.value != null) draft.value = null;
  }
}

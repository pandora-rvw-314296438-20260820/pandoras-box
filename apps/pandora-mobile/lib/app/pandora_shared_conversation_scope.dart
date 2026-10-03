import 'package:flutter/widgets.dart';

import '../core/network/pandora_api_error.dart';

typedef PandoraSharedSubmit = Future<String?> Function(
  String prompt, {
  Map<String, String>? selectedObject,
});
typedef PandoraSharedOpenThread = Future<void> Function(String threadId);
typedef PandoraSharedBindContext = void Function(Map<String, Object?> context);
typedef PandoraSharedBindSelected = void Function(Map<String, String> selected);
typedef PandoraSharedReportFailure = void Function(
  String code, {
  Map<String, String>? selectedObject,
});

class PandoraSharedConversationScope extends InheritedWidget {
  const PandoraSharedConversationScope({
    super.key,
    required this.submitPrompt,
    required this.openThread,
    this.showConversation,
    required this.bindEnterpriseContext,
    required this.bindSelectedObject,
    required this.reportFailure,
    required super.child,
  });

  final PandoraSharedSubmit submitPrompt;
  final PandoraSharedOpenThread openThread;
  final VoidCallback? showConversation;
  final PandoraSharedBindContext bindEnterpriseContext;
  final PandoraSharedBindSelected bindSelectedObject;
  final PandoraSharedReportFailure reportFailure;

  static PandoraSharedConversationScope? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PandoraSharedConversationScope>();

  @override
  bool updateShouldNotify(PandoraSharedConversationScope oldWidget) =>
      submitPrompt != oldWidget.submitPrompt ||
      openThread != oldWidget.openThread ||
      showConversation != oldWidget.showConversation ||
      bindEnterpriseContext != oldWidget.bindEnterpriseContext ||
      bindSelectedObject != oldWidget.bindSelectedObject ||
      reportFailure != oldWidget.reportFailure;
}

String pandoraNaturalFailureMessage(String code) => switch (code) {
      'provider_unavailable' =>
        'That provider is unavailable right now. Your current work was not changed.',
      'network_interruption' =>
        'The connection was interrupted. Pandora did not assume the action completed.',
      'authentication_failed' =>
        'Your authorization needs attention before Pandora can continue.',
      'connection_expired' =>
        'This connection has expired. Reconnect it before trying again.',
      'ai_unavailable' =>
        'Pandora intelligence is temporarily unavailable. Your business page is still usable.',
      'partial_execution' =>
        'Part of the request may have completed. Check Activity before retrying.',
      'invalid_request' =>
        'Pandora could not use that request as written. Update it and try again.',
      _ =>
        'Pandora could not complete that request safely. Nothing else was changed.',
    };

String pandoraFailureCodeForApiError(
  PandoraApiError error, {
  bool providerOperation = false,
}) =>
    switch (error.kind) {
      PandoraApiErrorKind.invalidRequest => 'invalid_request',
      PandoraApiErrorKind.sessionExpired ||
      PandoraApiErrorKind.forbidden =>
        'authentication_failed',
      PandoraApiErrorKind.ambiguousMutation => 'partial_execution',
      PandoraApiErrorKind.unavailable =>
        providerOperation ? 'provider_unavailable' : 'network_interruption',
      PandoraApiErrorKind.notFound => 'connection_expired',
      PandoraApiErrorKind.conflict => 'connection_expired',
      PandoraApiErrorKind.rateLimited => 'provider_unavailable',
      PandoraApiErrorKind.contract => 'invalid_request',
    };

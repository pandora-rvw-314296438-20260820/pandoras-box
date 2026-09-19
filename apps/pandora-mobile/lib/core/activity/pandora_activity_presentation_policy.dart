import 'pandora_activity_projection.dart';

const _trivialTurns = <String>{
  'hi',
  'hello',
  'hey',
  'yo',
  'hi pandora',
  'hello pandora',
  'hey pandora',
  'good morning',
  'good afternoon',
  'good evening',
  'good night',
  'thanks',
  'thank you',
  'thx',
  'ok',
  'okay',
  'k',
  'cool',
  'great',
  'nice',
  'got it',
  'understood',
  'sure',
  'yes',
  'yup',
  'yep',
  'no',
  'nope',
  'bye',
  'goodbye',
  'how are you',
  'how are you doing',
  'whats up',
  'what s up',
};

const _continuationCommands = <String>{
  'do it',
  'go',
  'proceed',
  'continue',
  'finish it',
  'try again',
  'connect',
  'fix it',
  'run it',
  'deploy it',
  'build it',
};

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

bool pandoraIsTrivialConversationTurn(String value) =>
    _trivialTurns.contains(_normalize(value));
bool pandoraShouldRequestActivityTheatre(
  String prompt, {
  bool hasAttachment = false,
  bool hasSelectedCapability = false,
  bool hasProjectContext = false,
}) {
  if (pandoraIsTrivialConversationTurn(prompt)) return false;
  if (hasAttachment || hasSelectedCapability || hasProjectContext) return true;
  final normalized = _normalize(prompt);
  if (_continuationCommands.contains(normalized)) return true;
  if (prompt.trim().length >= 100) return true;
  return RegExp(
    r'\b(analy[sz]e|research|search|find|look up|compare|review|inspect|debug|fix|build|create|write|edit|update|change|redesign|deploy|test|verify|check|connect|install|configure|run|execute|send|call|book|schedule|plan|design|generate|implement|refactor|optimi[sz]e|investigate|diagnose|summari[sz]e|calculate|convert|monitor|watch|download|upload|remove|add|restore|repair)\b',
  ).hasMatch(normalized);
}

bool pandoraHasMeaningfulActivity(List<PandoraActivityProjection> events) =>
    events.any(_isMeaningfulActivity);

PandoraActivityProjection? pandoraLatestPresentableActivity(
  List<PandoraActivityProjection> events,
) {
  for (var index = events.length - 1; index >= 0; index -= 1) {
    final event = events[index];
    if (_isPresentableActivity(event)) return event;
  }
  return null;
}

bool _isMeaningfulActivity(PandoraActivityProjection event) {
  if (event.source.sourceType == 'tool' ||
      event.source.sourceType == 'device' ||
      event.source.sourceType == 'provider' ||
      event.source.sourceType == 'pandora') {
    return true;
  }
  final capability = event.capability?.trim().toLowerCase();
  if (capability != null &&
      capability.isNotEmpty &&
      capability != 'universal_chat' &&
      capability != 'chat') {
    return true;
  }
  if (event.evidenceRefs.any(
    (ref) =>
        ref.type == 'tool_receipt' ||
        ref.type == 'provider_receipt' ||
        ref.type == 'test_receipt' ||
        ref.type == 'artifact' ||
        ref.type == 'verification_receipt',
  )) {
    return true;
  }
  return switch (event.state) {
    PandoraActivityState.needsYou ||
    PandoraActivityState.retrying ||
    PandoraActivityState.fallback ||
    PandoraActivityState.verifying ||
    PandoraActivityState.paused ||
    PandoraActivityState.resuming ||
    PandoraActivityState.failed ||
    PandoraActivityState.cancelled =>
      true,
    _ => false,
  };
}

bool _isPresentableActivity(PandoraActivityProjection event) {
  if (_isMeaningfulActivity(event)) return true;
  final message = event.message.trim();
  if (message.isEmpty || _isGenericRuntimeMessage(message)) return false;
  return event.state == PandoraActivityState.understanding ||
      event.state == PandoraActivityState.planning ||
      event.state == PandoraActivityState.acting ||
      event.state == PandoraActivityState.checking;
}

bool _isGenericRuntimeMessage(String value) {
  final normalized = _normalize(value);
  return normalized == 'request accepted by pandora runtime' ||
      normalized ==
          'resolving the admitted request against pandora capability routes' ||
      normalized == 'request admitted to the intelligence turn' ||
      normalized == 'running the selected intelligence step' ||
      normalized == 'running selected intelligence step' ||
      normalized == 'understanding the request' ||
      normalized == 'planning the request' ||
      normalized == 'working on the request' ||
      normalized == 'checking the request';
}

String pandoraActivityPresentationText(PandoraActivityProjection event) {
  final message = event.message.trim();
  if (message.isNotEmpty && !_isGenericRuntimeMessage(message)) return message;
  return switch (event.state) {
    PandoraActivityState.understanding => 'Understanding what you asked…',
    PandoraActivityState.planning => 'Planning the next step…',
    PandoraActivityState.acting => 'Working on it…',
    PandoraActivityState.checking => 'Checking the result…',
    PandoraActivityState.needsYou => 'Waiting for your input…',
    PandoraActivityState.retrying => 'Trying a different route…',
    PandoraActivityState.fallback => 'Switching approach…',
    PandoraActivityState.verifying => 'Verifying the result…',
    PandoraActivityState.paused => 'Paused…',
    PandoraActivityState.resuming => 'Resuming…',
    PandoraActivityState.result => 'Done.',
    PandoraActivityState.failed => 'Something went wrong.',
    PandoraActivityState.cancelled => 'Cancelled.',
  };
}

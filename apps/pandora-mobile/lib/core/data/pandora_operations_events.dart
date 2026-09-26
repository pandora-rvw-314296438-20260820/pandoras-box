
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const canonicalOperationsOrganization = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const canonicalOperationsProject = 'ee282126-3f61-4058-8c92-2fedbfcecf1f';
final _uuid = RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$');
final _cursorPattern = RegExp(r'^(0|[1-9][0-9]{0,18})$');
void _require(bool condition) {
  if (!condition) throw const FormatException('Invalid Operations event evidence');
}
BigInt _cursor(Object? value) {
  _require(value is String && _cursorPattern.hasMatch(value));
  final number = BigInt.parse(value as String);
  _require(number <= BigInt.parse('9223372036854775807'));
  return number;
}

class PandoraOperationsSession {
  const PandoraOperationsSession(this.userId, this.accessToken);
  final String userId;
  final String accessToken;
}

class PandoraOperationsReadException implements Exception {
  const PandoraOperationsReadException({this.accessDenied = false});
  final bool accessDenied;
  @override
  String toString() => accessDenied
      ? 'Execution events are not available for this account.'
      : 'Execution events could not be refreshed.';
}

class PandoraOperationsEvent {
  const PandoraOperationsEvent({required this.id, required this.type,
    required this.key, required this.occurredAt, this.taskId, this.receiptRef});
  final String id;
  final String type;
  final String key;
  final DateTime occurredAt;
  final String? taskId;
  final String? receiptRef;
  bool get taskComplete => type == 'verification_accepted';
  String get label => const <String, String>{
    'tasks_ingested': 'Tasks added',
    'task_claimed': 'Task claimed',
    'dispatch_prepared': 'Worker dispatch prepared',
    'dispatch_started': 'Worker delivery started',
    'worker_trigger_queued': 'Worker trigger queued; acknowledgement pending',
    'worker_started': 'Worker execution acknowledged',
    'worker_acknowledged': 'Worker acknowledged',
    'resource_claimed': 'Task resources reserved',
    'resource_released': 'Task resource settlement recorded',
    'implementation_handed_off': 'Implementation handed to verification',
    'verification_accepted': 'Task verification accepted',
    'owner_pause': 'Operations paused',
    'owner_resume': 'Operations resumed',
    'owner_no_production': 'Production execution disabled',
    'owner_cancel_task': 'Task cancellation requested',
    'reconciliation_required': 'Execution outcome requires reconciliation',
    'inference_admitted': 'Inference request admitted',
    'inference_routed': 'Approved inference route selected',
    'inference_send_started': 'Provider request started',
    'inference_received': 'Provider response received; verification pending',
    'inference_failed': 'Provider attempt failed',
    'inference_reconciliation_required': 'Provider outcome requires reconciliation',
    'inference_verified': 'Inference output verified; task acceptance remains separate',
    'inference_cancel_requested': 'Inference cancellation requested',
    'inference_not_sent': 'Prepared provider request was not sent',
    'inference_preparation_recovered': 'Unsent inference preparation fenced and recovered',
    'inference_billing_reconciled': 'Provider billing reconciled',
  }[type] ?? 'Recorded Operations event';
  factory PandoraOperationsEvent.parse(Map<String, dynamic> value) {
    _cursor(value['id']);
    final type = value['type'];
    final key = value['key'];
    final occurred = value['occurredAt'];
    _require(type is String && RegExp(r'^[a-z][a-z0-9_]{0,99}$').hasMatch(type));
    _require(key is String && key.length <= 500);
    _require(occurred is String && occurred.length <= 64 && DateTime.tryParse(occurred) != null);
    for (final entry in <String, int>{'taskId': 180, 'receiptRef': 1000}.entries) {
      final field = value[entry.key];
      _require(field == null || (field is String && field.length <= entry.value));
    }
    return PandoraOperationsEvent(id: value['id'] as String, type: type as String,
      key: key as String, occurredAt: DateTime.parse(occurred as String),
      taskId: value['taskId'] as String?, receiptRef: value['receiptRef'] as String?);
  }
}

class PandoraOperationsPage {
  const PandoraOperationsPage({required this.events, required this.nextCursor,
    required this.hasMore, required this.observedAt});
  final List<PandoraOperationsEvent> events;
  final String nextCursor;
  final bool hasMore;
  final DateTime observedAt;
  factory PandoraOperationsPage.parse(Map<String, dynamic> value, {
    required String organizationId, required String projectId,
    required String after,
  }) {
    _require(value['schemaVersion'] == 'pandora-operations-events-v1' &&
      value['organizationId'] == organizationId && value['projectId'] == projectId &&
      value['authority'] == 'immutable_operations_events' && value['syntheticProgress'] == false);
    final raw = value['events'];
    final observed = value['observedAt'];
    _require(raw is List && raw.length <= 200 && value['hasMore'] is bool);
    _require(observed is String && observed.length <= 64 && DateTime.tryParse(observed) != null);
    final at = DateTime.parse(observed as String);
    // Display server time as reported. Device wall-clock skew is not an access denial.
    // The complete authenticated HTTP exchange still has a 12-second timeout.
    var previous = _cursor(after);
    final high = _cursor(value['highWatermark']);
    final events = <PandoraOperationsEvent>[];
    for (final item in raw as List) {
      _require(item is Map);
      final event = PandoraOperationsEvent.parse(Map<String, dynamic>.from(item as Map));
      final id = _cursor(event.id);
      _require(id > previous && id <= high);
      previous = id;
      events.add(event);
    }
    _require(_cursor(value['nextCursor']) == previous && previous <= high &&
      (value['hasMore'] == false || events.isNotEmpty));
    return PandoraOperationsPage(events: List.unmodifiable(events),
      nextCursor: value['nextCursor'] as String, hasMore: value['hasMore'] as bool, observedAt: at);
  }
}

class PandoraOperationsEventReader {
  PandoraOperationsEventReader({required this.organizationId, required this.readSession,
    http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  final String organizationId;
  final PandoraOperationsSession? Function() readSession;
  final http.Client Function() _clientFactory;
  final Set<http.Client> _clients = {};
  bool _disposed = false;
  bool get canonicalScope => organizationId == canonicalOperationsOrganization;
  String? get sessionKey => readSession()?.userId;
  void cancel() {
    for (final client in _clients.toList(growable: false)) { client.close(); }
    _clients.clear();
  }
  void dispose() { _disposed = true; cancel(); }
  Future<PandoraOperationsPage> read(String projectId, String after) async {
    final session = readSession();
    if (_disposed || session == null) throw const PandoraOperationsReadException(accessDenied: true);
    _require(_uuid.hasMatch(organizationId) && _uuid.hasMatch(projectId));
    _cursor(after);
    final client = _clientFactory();
    _clients.add(client);
    try {
      return await (() async {
        final request = http.Request('POST', Uri.parse('https://mcpmaster.vercel.app/api/operations-inference?operation=events'))
          ..followRedirects = false
          ..headers.addAll({'authorization': 'Bearer ${session.accessToken}',
            'content-type': 'application/json', 'accept': 'application/json'})
          ..body = jsonEncode({'organizationId': organizationId, 'projectId': projectId, 'after': after, 'limit': 200});
        final response = await client.send(request);
        if (response.statusCode == 401 || response.statusCode == 403) throw const PandoraOperationsReadException(accessDenied: true);
        if (response.statusCode != 200 || (response.contentLength ?? 0) > 262144) throw const PandoraOperationsReadException();
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (_disposed || readSession()?.userId != session.userId) throw const PandoraOperationsReadException(accessDenied: true);
          if (bytes.length + chunk.length > 262144) throw const PandoraOperationsReadException();
          bytes.addAll(chunk);
        }
        if (_disposed || readSession()?.userId != session.userId) throw const PandoraOperationsReadException(accessDenied: true);
        final value = jsonDecode(utf8.decode(bytes));
        _require(value is Map);
        return PandoraOperationsPage.parse(Map<String, dynamic>.from(value as Map),
          organizationId: organizationId, projectId: projectId, after: after);
      })().timeout(const Duration(seconds: 12));
    } finally { _clients.remove(client); client.close(); }
  }
}

class PandoraOperationsFeed extends ChangeNotifier {
  PandoraOperationsFeed({required this.readPage, required this.cancelRead});
  final Future<PandoraOperationsPage> Function(String, String) readPage;
  final VoidCallback cancelRead;
  String? _session;
  String? _project;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  bool hasMore = false;
  String cursor = '0';
  String? error;
  DateTime? observedAt;
  List<PandoraOperationsEvent> events = const [];
  void reset(String? session, String? project) {
    _generation++; cancelRead(); _session = session; _project = project;
    loading = false; hasMore = false; cursor = '0'; events = const []; error = null; observedAt = null;
    if (!_disposed) notifyListeners();
  }
  void updateSession(String? session, String? project) {
    if (_session == session && _project == project) return;
    reset(session, project);
  }
  void pause() { _generation++; cancelRead(); loading = false; if (!_disposed) notifyListeners(); }
  Future<void> refresh() async {
    if (_disposed || loading || _session == null || _project == null) return;
    final generation = _generation;
    loading = true; error = null; notifyListeners();
    try {
      final page = await readPage(_project!, cursor);
      if (_disposed || generation != _generation) return;
      final combined = [...events, ...page.events];
      events = List.unmodifiable(combined.skip(combined.length > 500 ? combined.length - 500 : 0));
      cursor = page.nextCursor; hasMore = page.hasMore; observedAt = page.observedAt;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      if (failure is PandoraOperationsReadException && failure.accessDenied) {
        events = const []; cursor = '0'; hasMore = false; observedAt = null;
        error = 'Execution events are not available for this account.';
      } else { error = 'Execution events could not be refreshed. Earlier records are retained.'; }
    } finally { if (!_disposed && generation == _generation) { loading = false; notifyListeners(); } }
  }
  @override
  void dispose() { _disposed = true; _generation++; cancelRead(); super.dispose(); }
}

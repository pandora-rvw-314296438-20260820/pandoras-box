class PlpChatFallback {
  const PlpChatFallback._();

  static String? deterministicReply({
    required String message,
    required Map<String, Object?>? enterpriseContext,
  }) {
    if (!_isPlpContext(enterpriseContext)) return null;
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty || !isReadOnlyTurn(message)) return null;

    final context = enterpriseContext!;
    final today = _map(context['today']);
    final source = _map(context['sourceHealth'] ?? context['source']);

    final occupancy = _percentage(today['occupancy_percent']);
    final occupied = _integer(today['occupied_rooms']);
    final rooms = _integer(today['rooms_total']);
    final available = _integer(today['rooms_available']);
    final arrivals = _integer(today['arrivals_today']);
    final departures = _integer(today['departures_today']);
    final sales = _money(today['sales_today_php']);
    final tasks = _integer(today['open_staff_tasks']);
    final conflicts = _integer(today['open_ota_conflicts']);

    final suffix =
        ' This is from the last synchronized PLP snapshot; Pandora did not refresh a provider during this turn.';

    if (normalized.contains('occupancy')) {
      if ([occupancy, occupied, rooms, available].contains('unavailable')) {
        return 'PLP occupancy: $occupancy; occupied rooms: $occupied; total rooms: $rooms; available rooms: $available.$suffix';
      }
      return 'PLP occupancy is ${occupancy}: ${occupied} of ${rooms} rooms occupied, with ${available} available.${suffix}';
    }
    if (normalized.contains('arrival') ||
        normalized.contains('checking in') ||
        normalized.contains('check in')) {
      if (arrivals == 'unavailable') {
        return 'PLP arrival data is unavailable in this snapshot.$suffix';
      }
      return 'PLP has ${arrivals} arrival${arrivals == '1' ? '' : 's'} today.${suffix}';
    }
    if (normalized.contains('departure') ||
        normalized.contains('checking out') ||
        normalized.contains('check out')) {
      if (departures == 'unavailable') {
        return 'PLP departure data is unavailable in this snapshot.$suffix';
      }
      return 'PLP has ${departures} departure${departures == '1' ? '' : 's'} today.${suffix}';
    }
    if (normalized.contains('revenue') ||
        normalized.contains('sales') ||
        normalized.contains('made today') ||
        normalized.contains('earnings')) {
      if (sales == 'unavailable') {
        return 'PLP sales data is unavailable; this snapshot has no valid sales total.$suffix';
      }
      return 'PLP sales today are ${sales}.${suffix}';
    }
    if (normalized.contains('ota') || normalized.contains('conflict')) {
      if (conflicts == 'unavailable') {
        return 'PLP OTA conflict data is unavailable in this snapshot.$suffix';
      }
      return 'PLP has ${conflicts} open OTA conflict${conflicts == '1' ? '' : 's'}.${suffix}';
    }
    if (normalized.contains('available room') ||
        (normalized.contains('room') && normalized.contains('available'))) {
      if ([available, rooms].contains('unavailable')) {
        return 'PLP room availability: $available; total rooms: $rooms.$suffix';
      }
      return 'PLP has ${available} of ${rooms} rooms available in the snapshot.${suffix}';
    }
    if (normalized.contains('task') ||
        normalized.contains('needs attention') ||
        normalized.contains('need my attention') ||
        normalized.contains('attention')) {
      if ([tasks, conflicts, arrivals, departures].contains('unavailable')) {
        return 'PLP attention snapshot: open staff tasks: $tasks; OTA conflicts: $conflicts; arrivals: $arrivals; departures: $departures.$suffix';
      }
      return 'PLP currently has ${tasks} open staff task${tasks == '1' ? '' : 's'} and ${conflicts} open OTA conflict${conflicts == '1' ? '' : 's'}. There are ${arrivals} arrival${arrivals == '1' ? '' : 's'} and ${departures} departure${departures == '1' ? '' : 's'} today.${suffix}';
    }
    if (normalized.contains('source') ||
        normalized.contains('connected') ||
        normalized.contains('provider status') ||
        normalized.contains('data live') ||
        normalized.contains('data current')) {
      final state = _text(source['state'], fallback: 'unknown');
      final detail = _text(source['message'], fallback: 'No provider status message');
      return 'PLP source state is ${state}. ${detail}.${suffix}';
    }
    if (normalized == 'today' ||
        normalized.contains('summarize') ||
        normalized.contains('summary') ||
        normalized.contains('brief me') ||
        normalized.contains("today's briefing") ||
        normalized.contains('today briefing') ||
        normalized.contains('resort summary') ||
        normalized.contains('business summary')) {
      if ([occupancy, arrivals, departures, sales, tasks, conflicts]
          .contains('unavailable')) {
        return 'PLP snapshot: occupancy: $occupancy; arrivals: $arrivals; departures: $departures; sales: $sales; open staff tasks: $tasks; OTA conflicts: $conflicts.$suffix';
      }
      return 'PLP today: ${occupancy} occupancy, ${arrivals} arrival${arrivals == '1' ? '' : 's'}, ${departures} departure${departures == '1' ? '' : 's'}, ${sales} in sales, ${tasks} open staff task${tasks == '1' ? '' : 's'}, and ${conflicts} open OTA conflict${conflicts == '1' ? '' : 's'}.${suffix}';
    }
    return null;
  }

  static bool isReadOnlyTurn(String message) {
    final value = message.trim().toLowerCase();
    if (value.isEmpty) return true;
    final imperative = RegExp(
      r'^(?:please\s+)?(?:create|add|assign|update|change|edit|delete|remove|cancel|book|reserve|send|call|message|email|publish|deploy|merge|approve|reject|pay|refund|charge|invite|grant|revoke|schedule|reschedule)\b',
    );
    final delegated = RegExp(
      r'\b(?:can|could|would|will)\s+you\s+(?:create|add|assign|update|change|edit|delete|remove|cancel|book|reserve|send|call|message|email|publish|deploy|merge|approve|reject|pay|refund|charge|invite|grant|revoke|schedule|reschedule)\b',
    );
    return !imperative.hasMatch(value) && !delegated.hasMatch(value);
  }

  static String continuityNotice({
    required bool actionLike,
  }) {
    if (actionLike) {
      return 'Pandora is preserving this request without repeating the action or claiming completion. Check Activity for any verified provider result before you send the same action again.';
    }
    return 'I kept this turn in the conversation and will use the next available intelligence route without claiming work that did not run. You can keep chatting.';
  }

  static bool _isPlpContext(Map<String, Object?>? context) {
    if (context == null || context.isEmpty) return false;
    final organization = _map(context['organization']);
    return _text(organization['propertySlug']) == 'plp-boracay';
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  static String _text(Object? value, {String fallback = 'unavailable'}) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static num? _finiteNumber(Object? value) {
    final parsed = value is num
        ? value
        : value is String
            ? num.tryParse(value.trim())
            : null;
    if (parsed == null || !parsed.isFinite || parsed.abs() > 9007199254740991) {
      return null;
    }
    return parsed;
  }

  static String _percentage(Object? value) {
    final parsed = _finiteNumber(value);
    if (parsed == null || parsed < 0 || parsed > 100) return 'unavailable';
    final text = parsed == parsed.roundToDouble()
        ? parsed.toInt().toString()
        : parsed.toString();
    return '$text%';
  }

  static String _integer(Object? value) {
    final parsed = _finiteNumber(value);
    if (parsed == null || parsed < 0 || parsed != parsed.roundToDouble()) {
      return 'unavailable';
    }
    return parsed.toInt().toString();
  }

  static String _money(Object? value) {
    final parsed = _finiteNumber(value);
    if (parsed == null) return 'unavailable';
    final rounded = parsed.round().abs().toString();
    final grouped = StringBuffer();
    for (var index = 0; index < rounded.length; index += 1) {
      if (index > 0 && (rounded.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(rounded[index]);
    }
    return '${parsed.isNegative ? '-' : ''}₱$grouped';
  }
}

class PandoraCalendarParseResult {
  const PandoraCalendarParseResult._({this.command, this.clarification});

  const PandoraCalendarParseResult.command(PandoraCalendarCommand value)
      : this._(command: value);

  const PandoraCalendarParseResult.clarification(String value)
      : this._(clarification: value);

  final PandoraCalendarCommand? command;
  final String? clarification;

  bool get isReady => command != null;
}

enum PandoraCalendarCommandKind {
  query,
  create,
  update,
  delete,
  reminder,
}

class PandoraCalendarCommand {
  const PandoraCalendarCommand({
    required this.kind,
    this.title,
    this.rangeStart,
    this.rangeEnd,
    this.start,
    this.end,
    this.oldMinuteOfDay,
    this.recurrenceRule,
    this.requireExactReminder = false,
  });

  final PandoraCalendarCommandKind kind;
  final String? title;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? start;
  final DateTime? end;
  final int? oldMinuteOfDay;
  final String? recurrenceRule;
  final bool requireExactReminder;

  static PandoraCalendarParseResult? tryParse(
    String raw, {
    required DateTime now,
  }) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();

    if (_looksLikeReminder(lower)) return _parseReminder(input, now);
    if (_looksLikeCalendarQuery(lower)) return _parseQuery(input, now);
    if (_looksLikeDelete(lower)) return _parseDelete(input, now);
    if (_looksLikeUpdate(lower)) return _parseUpdate(input, now);
    if (_looksLikeCreate(lower)) return _parseCreate(input, now);
    return null;
  }

  static bool _looksLikeReminder(String lower) =>
      RegExp(r'^(?:please\s+)?remind\s+me\b').hasMatch(lower);

  static bool _looksLikeCalendarQuery(String lower) =>
      lower.contains('calendar') &&
      RegExp(r'\b(what|show|list|check|events?|schedule|agenda)\b')
          .hasMatch(lower);

  static bool _looksLikeDelete(String lower) =>
      RegExp(r'^(?:please\s+)?(?:cancel|delete|remove)\b').hasMatch(lower) &&
      (lower.contains('calendar') ||
          lower.contains('event') ||
          _containsDateWord(lower));

  static bool _looksLikeUpdate(String lower) =>
      RegExp(r'^(?:please\s+)?(?:move|reschedule)\b').hasMatch(lower);

  static bool _looksLikeCreate(String lower) =>
      RegExp(r'^(?:please\s+)?(?:set|schedule|add|create)\b').hasMatch(lower) &&
      !RegExp(r'\b(reminder|alarm)\b').hasMatch(lower);

  static PandoraCalendarParseResult _parseQuery(String input, DateTime now) {
    final day = _resolveDay(input, now) ?? _dayStart(now);
    return PandoraCalendarParseResult.command(
      PandoraCalendarCommand(
        kind: PandoraCalendarCommandKind.query,
        rangeStart: day,
        rangeEnd: day.add(const Duration(days: 1)),
      ),
    );
  }

  static PandoraCalendarParseResult _parseReminder(String input, DateTime now) {
    final day = _resolveDay(input, now);
    if (day == null) {
      return const PandoraCalendarParseResult.clarification(
        'Which day should I remind you?',
      );
    }
    final time = _resolveSingleTime(
      input,
      contextText: input,
      allowContextInference: true,
    );
    if (time.ambiguous) {
      return PandoraCalendarParseResult.clarification(time.question!);
    }
    if (time.minuteOfDay == null) {
      return const PandoraCalendarParseResult.clarification(
        'What time should I remind you?',
      );
    }
    final trigger = _atMinute(day, time.minuteOfDay!);
    if (!trigger.isAfter(now.add(const Duration(seconds: 1)))) {
      return const PandoraCalendarParseResult.clarification(
        'That reminder time has already passed. What future time should I use?',
      );
    }
    var title = input
        .replaceFirst(
          RegExp(r'^(?:please\s+)?remind\s+me\b', caseSensitive: false),
          '',
        )
        .trim();
    title = _stripDateAndTimeTokens(title);
    title = title.replaceFirst(
      RegExp(r'^(?:to|about)\s+', caseSensitive: false),
      '',
    );
    title = title.trim();
    if (title.isEmpty) {
      return const PandoraCalendarParseResult.clarification(
        'What should I remind you about?',
      );
    }
    final exact =
        RegExp(r'\b(exactly|exact)\b', caseSensitive: false).hasMatch(input);
    return PandoraCalendarParseResult.command(
      PandoraCalendarCommand(
        kind: PandoraCalendarCommandKind.reminder,
        title: title,
        start: trigger,
        requireExactReminder: exact,
      ),
    );
  }

  static PandoraCalendarParseResult _parseCreate(String input, DateTime now) {
    final day = _resolveDay(input, now);
    if (day == null) {
      return const PandoraCalendarParseResult.clarification(
        'Which day should I put that on the calendar?',
      );
    }
    final time = _resolveSingleTime(
      input,
      contextText: input,
      allowContextInference: true,
    );
    if (time.ambiguous) {
      return PandoraCalendarParseResult.clarification(time.question!);
    }
    if (time.minuteOfDay == null) {
      return const PandoraCalendarParseResult.clarification(
        'What time should I schedule it?',
      );
    }
    final start = _atMinute(day, time.minuteOfDay!);
    final duration = _durationFromText(input) ?? const Duration(hours: 1);
    if (duration.inMinutes < 1 || duration.inHours > 24) {
      return const PandoraCalendarParseResult.clarification(
        'How long should the event last?',
      );
    }
    var title = input.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:set|schedule|add|create)\s+(?:a\s+)?(?:calendar\s+)?(?:event\s+)?',
        caseSensitive: false,
      ),
      '',
    );
    title = _stripDateAndTimeTokens(title);
    title = title.replaceAll(
      RegExp(
        r'\b(?:for)\s+\d+\s*(?:minutes?|mins?|hours?|hrs?)\b',
        caseSensitive: false,
      ),
      '',
    );
    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,:\s]+|[,:\s]+$'), '')
        .trim();
    if (title.isEmpty) {
      return const PandoraCalendarParseResult.clarification(
        'What should I call the calendar event?',
      );
    }
    return PandoraCalendarParseResult.command(
      PandoraCalendarCommand(
        kind: PandoraCalendarCommandKind.create,
        title: title,
        start: start,
        end: start.add(duration),
        recurrenceRule: _recurrenceRule(input),
      ),
    );
  }

  static PandoraCalendarParseResult _parseDelete(String input, DateTime now) {
    final day = _resolveDay(input, now) ?? _dayStart(now);
    var title = input.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:cancel|delete|remove)\s+(?:the\s+)?(?:calendar\s+)?(?:event\s+)?',
        caseSensitive: false,
      ),
      '',
    );
    title =
        _stripDateAndTimeTokens(title).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) {
      return const PandoraCalendarParseResult.clarification(
        'Which calendar event should I cancel?',
      );
    }
    return PandoraCalendarParseResult.command(
      PandoraCalendarCommand(
        kind: PandoraCalendarCommandKind.delete,
        title: _normalizeTitleNeedle(title),
        rangeStart: day,
        rangeEnd: day.add(const Duration(days: 1)),
      ),
    );
  }

  static PandoraCalendarParseResult _parseUpdate(String input, DateTime now) {
    final day = _resolveDay(input, now) ?? _dayStart(now);
    final times = _explicitTimes(input);
    final toTime = RegExp(
      r'\bto\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).firstMatch(input);
    int? newMinute;
    if (toTime != null) {
      newMinute = _minuteFromParts(
        toTime.group(1)!,
        toTime.group(2),
        toTime.group(3),
      );
    } else if (times.length == 1) {
      newMinute = times.single;
    }
    if (newMinute == null) {
      return const PandoraCalendarParseResult.clarification(
        'What new time should I use?',
      );
    }
    final oldMinute = times.length >= 2 ? times.first : null;
    var title = input.replaceFirst(
      RegExp(r'^(?:please\s+)?(?:move|reschedule)\s+', caseSensitive: false),
      '',
    );
    title = _stripDateAndTimeTokens(title);
    title = title
        .replaceAll(RegExp(r'\bto\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\bmy\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) title = 'meeting';
    return PandoraCalendarParseResult.command(
      PandoraCalendarCommand(
        kind: PandoraCalendarCommandKind.update,
        title: _normalizeTitleNeedle(title),
        rangeStart: day,
        rangeEnd: day.add(const Duration(days: 1)),
        start: _atMinute(day, newMinute),
        oldMinuteOfDay: oldMinute,
      ),
    );
  }

  static bool _containsDateWord(String lower) => RegExp(
        r'\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
      ).hasMatch(lower);

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime? _resolveDay(String input, DateTime now) {
    final lower = input.toLowerCase();
    final today = _dayStart(now);
    if (RegExp(r'\btoday\b').hasMatch(lower)) return today;
    if (RegExp(r'\btomorrow\b').hasMatch(lower)) {
      return today.add(const Duration(days: 1));
    }
    const weekdays = <String, int>{
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    for (final entry in weekdays.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) {
        var delta = (entry.value - today.weekday) % 7;
        if (delta == 0 && !lower.contains('today')) delta = 7;
        return today.add(Duration(days: delta));
      }
    }
    final iso = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b').firstMatch(lower);
    if (iso != null) {
      final year = int.parse(iso.group(1)!);
      final month = int.parse(iso.group(2)!);
      final day = int.parse(iso.group(3)!);
      final candidate = DateTime(year, month, day);
      if (candidate.year == year &&
          candidate.month == month &&
          candidate.day == day) {
        return candidate;
      }
    }
    return null;
  }

  static _ResolvedTime _resolveSingleTime(
    String input, {
    required String contextText,
    required bool allowContextInference,
  }) {
    final explicit = _explicitTimes(input);
    if (explicit.length == 1) return _ResolvedTime(explicit.single);
    if (explicit.length > 1) {
      return const _ResolvedTime.ambiguous(
        'I found more than one time. Which time should I use?',
      );
    }
    final bare = RegExp(
      r'\b(?:at|@)\s*(\d{1,2})(?::(\d{2}))?\b(?!\s*(?:am|pm))',
      caseSensitive: false,
    ).firstMatch(input);
    if (bare == null) return const _ResolvedTime(null);
    final hour = int.tryParse(bare.group(1) ?? '');
    final minute = int.tryParse(bare.group(2) ?? '0') ?? 0;
    if (hour == null || hour < 1 || hour > 12 || minute > 59) {
      return const _ResolvedTime.ambiguous('What time should I use?');
    }
    if (!allowContextInference) {
      return _ResolvedTime.ambiguous('Is that $hour AM or $hour PM?');
    }
    final context = contextText.toLowerCase();
    final inferredPm =
        RegExp(r'\b(lunch|afternoon|dinner|evening)\b').hasMatch(context);
    final inferredAm = RegExp(r'\b(breakfast|morning)\b').hasMatch(context);
    if (!inferredPm && !inferredAm) {
      return _ResolvedTime.ambiguous('Is that $hour AM or $hour PM?');
    }
    final normalizedHour =
        inferredPm ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour);
    return _ResolvedTime(normalizedHour * 60 + minute);
  }

  static List<int> _explicitTimes(String input) {
    final matches = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).allMatches(input);
    return matches
        .map(
          (match) => _minuteFromParts(
            match.group(1)!,
            match.group(2),
            match.group(3),
          ),
        )
        .whereType<int>()
        .toList(growable: false);
  }

  static int? _minuteFromParts(
    String hourText,
    String? minuteText,
    String? meridiem,
  ) {
    var hour = int.tryParse(hourText);
    final minute = int.tryParse(minuteText ?? '0') ?? -1;
    if (hour == null || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
      return null;
    }
    final token = meridiem?.toLowerCase();
    if (token == 'pm' && hour != 12) hour += 12;
    if (token == 'am' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  static DateTime _atMinute(DateTime day, int minuteOfDay) => DateTime(
        day.year,
        day.month,
        day.day,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );

  static Duration? _durationFromText(String input) {
    final match = RegExp(
      r'\bfor\s+(\d{1,3})\s*(minutes?|mins?|hours?|hrs?)\b',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final amount = int.tryParse(match.group(1) ?? '');
    if (amount == null || amount < 1) return null;
    final unit = (match.group(2) ?? '').toLowerCase();
    return unit.startsWith('h')
        ? Duration(hours: amount)
        : Duration(minutes: amount);
  }

  static String? _recurrenceRule(String input) {
    final lower = input.toLowerCase();
    if (RegExp(r'\bevery\s+day\b').hasMatch(lower) ||
        RegExp(r'\bdaily\b').hasMatch(lower)) {
      return 'FREQ=DAILY';
    }
    if (RegExp(r'\bevery\s+week\b').hasMatch(lower) ||
        RegExp(r'\bweekly\b').hasMatch(lower)) {
      return 'FREQ=WEEKLY';
    }
    const weekdays = <String, String>{
      'monday': 'MO',
      'tuesday': 'TU',
      'wednesday': 'WE',
      'thursday': 'TH',
      'friday': 'FR',
      'saturday': 'SA',
      'sunday': 'SU',
    };
    for (final entry in weekdays.entries) {
      if (RegExp('\\bevery\\s+${entry.key}\\b').hasMatch(lower)) {
        return 'FREQ=WEEKLY;BYDAY=${entry.value}';
      }
    }
    if (RegExp(r'\bmonthly\b|\bevery\s+month\b').hasMatch(lower)) {
      return 'FREQ=MONTHLY';
    }
    if (RegExp(r'\byearly\b|\bevery\s+year\b').hasMatch(lower)) {
      return 'FREQ=YEARLY';
    }
    return null;
  }

  static String _stripDateAndTimeTokens(String input) {
    var value = input;
    value = value.replaceAll(
      RegExp(
        r'\b(?:on\s+)?(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(
      RegExp(r'\b20\d{2}-\d{2}-\d{2}\b', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\b(?:at|@|to)?\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\b(?:at|@)\s*\d{1,2}(?::\d{2})?\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\b(?:every\s+(?:day|week|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|daily|weekly|monthly|yearly)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeTitleNeedle(String value) => value
      .replaceAll(
        RegExp(r'^(?:the\s+|my\s+)', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'\b(?:calendar|event)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ResolvedTime {
  const _ResolvedTime(this.minuteOfDay)
      : ambiguous = false,
        question = null;

  const _ResolvedTime.ambiguous(this.question)
      : minuteOfDay = null,
        ambiguous = true;

  final int? minuteOfDay;
  final bool ambiguous;
  final String? question;
}

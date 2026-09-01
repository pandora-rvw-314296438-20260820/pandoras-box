import 'dart:convert';

import 'live_build_event.dart';

enum LiveBuildStage {
  starting,
  writing,
  sourceReady,
  building,
  checking,
  correcting,
  previewReady,
  needsYou,
  completed,
  problem,
}

class LiveBuildFileSummary {
  const LiveBuildFileSummary({
    required this.path,
    required this.byteCount,
    required this.lineCount,
    required this.completed,
    required this.lastSequence,
  });

  final String path;
  final int byteCount;
  final int lineCount;
  final bool completed;
  final int lastSequence;
}

class LiveBuildTheatreState {
  const LiveBuildTheatreState({
    required this.streamId,
    required this.latestSequence,
    required this.stage,
    required this.activeFile,
    required this.visibleCode,
    required this.files,
    required this.uniqueFileCount,
    required this.completedFileCount,
    required this.sourceByteCount,
    required this.sourceLineCount,
    required this.generationComplete,
    required this.historyGapDueToRetention,
    required this.sourceHistoryComplete,
    required this.previewReady,
    required this.failed,
    required this.needsYou,
    required this.reportedFileCount,
    required this.reportedSourceByteCount,
    required this.reportedSourceLineCount,
  });

  factory LiveBuildTheatreState.empty({
    bool historyGapDueToRetention = false,
  }) =>
      LiveBuildTheatreState(
        streamId: null,
        latestSequence: 0,
        stage: LiveBuildStage.starting,
        activeFile: null,
        visibleCode: '',
        files: const <LiveBuildFileSummary>[],
        uniqueFileCount: 0,
        completedFileCount: 0,
        sourceByteCount: 0,
        sourceLineCount: 0,
        generationComplete: false,
        historyGapDueToRetention: historyGapDueToRetention,
        sourceHistoryComplete: false,
        previewReady: false,
        failed: false,
        needsYou: false,
        reportedFileCount: null,
        reportedSourceByteCount: null,
        reportedSourceLineCount: null,
      );

  final String? streamId;
  final int latestSequence;
  final LiveBuildStage stage;
  final String? activeFile;
  final String visibleCode;
  final List<LiveBuildFileSummary> files;
  final int uniqueFileCount;
  final int completedFileCount;
  final int sourceByteCount;
  final int sourceLineCount;
  final bool generationComplete;
  final bool historyGapDueToRetention;
  final bool sourceHistoryComplete;
  final bool previewReady;
  final bool failed;
  final bool needsYou;
  final int? reportedFileCount;
  final int? reportedSourceByteCount;
  final int? reportedSourceLineCount;

  /// The code surface must exist if and only if this is true.
  bool get hasVisibleRealSource => visibleCode.isNotEmpty;

  bool get locallyCompleteSourceMetrics =>
      generationComplete && sourceHistoryComplete && !historyGapDueToRetention;

  String get statusLabel {
    switch (stage) {
      case LiveBuildStage.starting:
        return 'Pandora is starting the build';
      case LiveBuildStage.writing:
        return activeFile == null ? 'Pandora is coding' : 'Writing $activeFile';
      case LiveBuildStage.sourceReady:
        return 'Source ready';
      case LiveBuildStage.building:
        return 'Building the application';
      case LiveBuildStage.checking:
        return 'Checking the application';
      case LiveBuildStage.correcting:
        return 'Correcting the application';
      case LiveBuildStage.previewReady:
        return 'Preview ready';
      case LiveBuildStage.needsYou:
        return 'Needs You';
      case LiveBuildStage.completed:
        return 'Ready';
      case LiveBuildStage.problem:
        return 'Problem';
    }
  }
}

class LiveBuildTheatreReducer {
  const LiveBuildTheatreReducer({
    this.maxVisibleSourceChars = 65536,
    this.maxTrackedFiles = 2048,
  })  : assert(maxVisibleSourceChars > 0),
        assert(maxTrackedFiles > 0);

  final int maxVisibleSourceChars;
  final int maxTrackedFiles;

  LiveBuildTheatreState reduce(
    Iterable<LiveBuildEvent> input, {
    bool historyGapDueToRetention = false,
    bool sourceHistoryComplete = false,
  }) {
    final events = input.toList(growable: false)
      ..sort((left, right) {
        final streamOrder = left.streamId.compareTo(right.streamId);
        if (streamOrder != 0) return streamOrder;
        return left.sequence.compareTo(right.sequence);
      });

    if (events.isEmpty) {
      return LiveBuildTheatreState.empty(
        historyGapDueToRetention: historyGapDueToRetention,
      );
    }

    final streamId = events.first.streamId;
    if (events.any((event) => event.streamId != streamId)) {
      throw const FormatException(
        'Mixed live build streams are not renderable.',
      );
    }

    final files = <String, _MutableFileState>{};
    final orderedFiles = <String>[];
    var latestSequence = 0;
    var stage = LiveBuildStage.starting;
    String? activeFile;
    var visibleCode = '';
    var generationComplete = false;
    var previewReady = false;
    var failed = false;
    var needsYou = false;
    int? reportedFileCount;
    int? reportedSourceByteCount;
    int? reportedSourceLineCount;

    for (final event in events) {
      if (event.sequence <= latestSequence) {
        // Replay + live overlap is expected. Sequence is the stable dedupe key.
        continue;
      }
      latestSequence = event.sequence;

      switch (event.kind) {
        case LiveBuildEventKind.buildAdmitted:
        case LiveBuildEventKind.streamStarted:
          stage = LiveBuildStage.starting;
          break;
        case LiveBuildEventKind.fileStarted:
          final path = event.filePath;
          if (path == null || path.isEmpty) break;
          final file = _fileFor(files, orderedFiles, path, event.sequence);
          file.reset(event.sequence);
          activeFile = path;
          visibleCode = '';
          stage = LiveBuildStage.writing;
          break;
        case LiveBuildEventKind.codeChunk:
          final path = event.filePath;
          final chunk = event.contentChunk;
          if (path == null || path.isEmpty || chunk == null || chunk.isEmpty) {
            break;
          }
          final file = _fileFor(files, orderedFiles, path, event.sequence);
          file.append(chunk, event.sequence);
          activeFile = path;
          if (file.displayTail.length > maxVisibleSourceChars) {
            file.displayTail = file.displayTail.substring(
              file.displayTail.length - maxVisibleSourceChars,
            );
          }
          visibleCode = file.displayTail;
          stage = LiveBuildStage.writing;
          break;
        case LiveBuildEventKind.fileCompleted:
          final path = event.filePath;
          if (path == null || path.isEmpty) break;
          final file = _fileFor(files, orderedFiles, path, event.sequence);
          file.completed = true;
          file.lastSequence = event.sequence;
          break;
        case LiveBuildEventKind.generationCompleted:
          generationComplete = true;
          stage = LiveBuildStage.sourceReady;
          reportedFileCount = _payloadInt(event.safePayload, const <String>[
            'fileCount',
            'file_count',
          ]);
          reportedSourceByteCount = _payloadInt(
            event.safePayload,
            const <String>[
              'sourceByteCount',
              'sourceBytes',
              'byteCount',
              'source_byte_count',
            ],
          );
          reportedSourceLineCount = _payloadInt(
            event.safePayload,
            const <String>['sourceLineCount', 'lineCount', 'source_line_count'],
          );
          break;
        case LiveBuildEventKind.buildJobCreated:
          stage = LiveBuildStage.building;
          break;
        case LiveBuildEventKind.jobState:
        case LiveBuildEventKind.buildStep:
          stage = _stageFromPayload(event.safePayload, fallback: stage);
          final status = _payloadText(event.safePayload, 'status');
          if (status == 'failed') {
            failed = true;
            stage = LiveBuildStage.problem;
          }
          break;
        case LiveBuildEventKind.verification:
          stage = LiveBuildStage.checking;
          break;
        case LiveBuildEventKind.previewReady:
          previewReady = true;
          stage = LiveBuildStage.previewReady;
          break;
        case LiveBuildEventKind.needsYou:
          needsYou = true;
          stage = LiveBuildStage.needsYou;
          break;
        case LiveBuildEventKind.buildCompleted:
          stage = LiveBuildStage.completed;
          break;
        case LiveBuildEventKind.buildFailed:
        case LiveBuildEventKind.streamError:
          failed = true;
          stage = LiveBuildStage.problem;
          break;
        case LiveBuildEventKind.unknown:
          // Optional future protocol events must not crash the live theatre.
          break;
      }
    }

    var sourceByteCount = 0;
    var sourceLineCount = 0;
    var completedFileCount = 0;
    final summaries = <LiveBuildFileSummary>[];
    for (final path in orderedFiles) {
      final file = files[path]!;
      sourceByteCount += file.byteCount;
      sourceLineCount += file.lineCount;
      if (file.completed) completedFileCount += 1;
      summaries.add(
        LiveBuildFileSummary(
          path: path,
          byteCount: file.byteCount,
          lineCount: file.lineCount,
          completed: file.completed,
          lastSequence: file.lastSequence,
        ),
      );
    }
    summaries.sort(
      (left, right) => right.lastSequence.compareTo(left.lastSequence),
    );

    return LiveBuildTheatreState(
      streamId: streamId,
      latestSequence: latestSequence,
      stage: stage,
      activeFile: activeFile,
      visibleCode: visibleCode,
      files: List<LiveBuildFileSummary>.unmodifiable(summaries),
      uniqueFileCount: files.length,
      completedFileCount: completedFileCount,
      sourceByteCount: sourceByteCount,
      sourceLineCount: sourceLineCount,
      generationComplete: generationComplete,
      historyGapDueToRetention: historyGapDueToRetention,
      sourceHistoryComplete: sourceHistoryComplete,
      previewReady: previewReady,
      failed: failed,
      needsYou: needsYou,
      reportedFileCount: reportedFileCount,
      reportedSourceByteCount: reportedSourceByteCount,
      reportedSourceLineCount: reportedSourceLineCount,
    );
  }

  _MutableFileState _fileFor(
    Map<String, _MutableFileState> files,
    List<String> orderedFiles,
    String path,
    int sequence,
  ) {
    final existing = files[path];
    if (existing != null) return existing;
    if (files.length >= maxTrackedFiles) {
      throw const FormatException('Live build file metadata limit exceeded.');
    }
    final created = _MutableFileState(lastSequence: sequence);
    files[path] = created;
    orderedFiles.add(path);
    return created;
  }
}

class _MutableFileState {
  _MutableFileState({required this.lastSequence});

  int byteCount = 0;
  int newlineCount = 0;
  bool hasSource = false;
  bool completed = false;
  int lastSequence;
  String displayTail = '';

  int get lineCount => hasSource ? newlineCount + 1 : 0;

  void reset(int sequence) {
    byteCount = 0;
    newlineCount = 0;
    hasSource = false;
    completed = false;
    lastSequence = sequence;
    displayTail = '';
  }

  void append(String chunk, int sequence) {
    byteCount += utf8.encode(chunk).length;
    newlineCount += '\n'.allMatches(chunk).length;
    hasSource = true;
    completed = false;
    lastSequence = sequence;
    displayTail += chunk;
  }
}

LiveBuildStage _stageFromPayload(
  Map<String, Object?> payload, {
  required LiveBuildStage fallback,
}) {
  final stage = (_payloadText(payload, 'stage') ??
          _payloadText(payload, 'stepKind') ??
          _payloadText(payload, 'step_kind') ??
          '')
      .toLowerCase();
  if (stage.contains('repair') || stage.contains('correct')) {
    return LiveBuildStage.correcting;
  }
  if (stage.contains('verify') ||
      stage.contains('check') ||
      stage.contains('test')) {
    return LiveBuildStage.checking;
  }
  if (stage.contains('preview_ready')) return LiveBuildStage.previewReady;
  if (stage.contains('preview')) return LiveBuildStage.building;
  if (stage.contains('build') ||
      stage.contains('compile') ||
      stage.contains('package') ||
      stage.contains('depend')) {
    return LiveBuildStage.building;
  }
  return fallback;
}

String? _payloadText(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int? _payloadInt(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

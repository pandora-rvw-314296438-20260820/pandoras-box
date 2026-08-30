import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/core/widgets/pandora_mark.dart';
import 'package:pandora_mobile/features/activity/activity_screen.dart';
import 'package:pandora_mobile/features/approvals/approvals_screen.dart';
import 'package:pandora_mobile/features/command/command_screen.dart';
import 'package:pandora_mobile/features/connections/connections_screen.dart';
import 'package:pandora_mobile/features/home/home_screen.dart';
import 'package:pandora_mobile/features/intelligence/owner_intelligence_screen.dart';
import 'package:pandora_mobile/features/projects/project_detail_screen.dart';
import 'package:pandora_mobile/features/projects/projects_screen.dart';
import 'package:pandora_mobile/features/safety/safety_screen.dart';
import 'package:pandora_mobile/features/settings/settings_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

const _surfaceKey = ValueKey<String>('owner-screen-evidence');
const _phoneSize = Size(390, 844);
const _compactPhoneSize = Size(320, 800);
const _renderFrames = <Duration>[
  Duration.zero,
  Duration(milliseconds: 50),
  Duration(milliseconds: 200),
  Duration(milliseconds: 500),
];

// The committed production-screen baselines were captured by exact workflow
// run 32248881113, which started at this instant. Production widgets correctly
// render owner-relative time from DateTime.now(), so fixed fixture timestamps
// would otherwise drift by one day whenever CI crosses a calendar boundary.
// Rebase only the test fixture timeline into the reviewed temporal window. The
// production clock, widgets, PNG baselines, comparator, and tolerances remain
// untouched.
final DateTime _reviewedVisualReference = DateTime.utc(2026, 8, 19, 11, 42, 6);
final DateTime _visualRunReference = DateTime.now().toUtc();
final Duration _fixtureTimelineOffset = _visualRunReference.difference(
  _reviewedVisualReference,
);
final RegExp _fixtureTimestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$',
);

Object? _shiftFixtureTimeline(Object? value) {
  if (value is String && _fixtureTimestampPattern.hasMatch(value)) {
    return DateTime.parse(value)
        .toUtc()
        .add(_fixtureTimelineOffset)
        .toIso8601String();
  }
  if (value is List<Object?>) {
    return value.map(_shiftFixtureTimeline).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    return value.map<String, Object?>(
      (key, item) => MapEntry(key, _shiftFixtureTimeline(item)),
    );
  }
  return value;
}

const _visualFontFamily = 'Roboto';
const _visualIconFontFamily = 'MaterialIcons';
bool _visualFontLoaded = false;

Future<void> _loadVisualFont() async {
  if (_visualFontLoaded) return;
  final separator = Platform.pathSeparator;
  final roots = <String>{};
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    roots.add(configuredRoot);
  }
  var cursor = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 12; depth++) {
    roots.add(cursor.path);
    final parent = cursor.parent;
    if (parent.path == cursor.path) break;
    cursor = parent;
  }
  File? font;
  File? iconFont;
  for (final root in roots) {
    final materialFonts =
        '$root${separator}bin${separator}cache${separator}artifacts'
        '${separator}material_fonts';
    final textCandidate = File('$materialFonts${separator}Roboto-Regular.ttf');
    final iconCandidate = File(
      '$materialFonts${separator}MaterialIcons-Regular.otf',
    );
    if (font == null && textCandidate.existsSync()) {
      font = textCandidate;
    }
    if (iconFont == null && iconCandidate.existsSync()) {
      iconFont = iconCandidate;
    }
    if (font != null && iconFont != null) break;
  }
  if (font == null || iconFont == null) {
    throw StateError(
      'Pinned Flutter SDK Roboto and Material Icons fonts were not found; '
      'readable visual evidence cannot be generated.',
    );
  }
  final bytes = await font.readAsBytes();
  final iconBytes = await iconFont.readAsBytes();
  final loader = FontLoader(_visualFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  final iconLoader = FontLoader(_visualIconFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
  await Future.wait([loader.load(), iconLoader.load()]);
  _visualFontLoaded = true;
}

Widget _withVisualFont(Widget child) => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: _visualFontFamily),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: _visualFontFamily,
            ),
          ),
          child: child,
        );
      },
    );

Future<void> _waitForRenderedPandoraMark(
  WidgetTester tester,
  String caseName,
) async {
  final markFinder = find.byType(PandoraMark);
  if (markFinder.evaluate().isEmpty) return;

  // The canonical Pandora spiral is an asset-backed alpha mask. Precache it
  // so golden capture always contains the reviewed mark pixels.
  await precacheImage(
    const AssetImage(PandoraMark.assetPath),
    tester.element(markFinder.first),
  );
  await tester.pump();
  if (markFinder.evaluate().isEmpty) {
    throw TestFailure('$caseName did not render the Pandora app icon.');
  }
}

class _VisualCase {
  const _VisualCase({
    required this.name,
    required this.build,
    this.themeMode = ThemeMode.light,
    this.logicalSize = _phoneSize,
    this.textScaler = TextScaler.noScaling,
    this.failing = false,
    this.pending = false,
  });

  final String name;
  final Widget Function() build;
  final ThemeMode themeMode;
  final Size logicalSize;
  final TextScaler textScaler;
  final bool failing;
  final bool pending;
}

class _FixtureRepository implements PandoraRepository {
  _FixtureRepository({this.failing = false, this.pending = false});

  final bool failing;
  final bool pending;
  Completer<RepositorySnapshot<HomeSummary>>? _pendingHome;
  static final DateTime _verifiedAt = DateTime.utc(
    2026,
    8,
    14,
    1,
  ).add(_fixtureTimelineOffset);
  static final DateTime _staleAfter = DateTime.utc(
    2030,
    8,
    14,
    1,
  ).add(_fixtureTimelineOffset);

  Object? _read(String name) {
    final file = File('test/fixtures/owner_api/$name');
    return _shiftFixtureTimeline(jsonDecode(file.readAsStringSync()));
  }

  void _guard() {
    if (failing) {
      throw const PandoraRepositoryException(
        kind: PandoraApiErrorKind.unavailable,
        message: 'Pandora cannot currently reach this provider.',
        code: 'provider_unavailable',
      );
    }
  }

  RepositorySnapshot<T> _snapshot<T>(T data) => RepositorySnapshot<T>(
        data: data,
        source: RepositorySource.network,
        fetchedAt: _verifiedAt,
        verifiedAt: _verifiedAt,
        staleAfter: _staleAfter,
        requestId: 'visual-evidence-fixture',
      );

  List<T> _list<T>(String name, T Function(Object?) parse) =>
      asJsonList(_read(name)).map(parse).toList(growable: false);

  void completePendingHome() {
    final completer = _pendingHome;
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      _snapshot(HomeSummary.fromJson(asJsonMap(_read('home.json')))),
    );
  }

  @override
  Future<RepositorySnapshot<HomeSummary>> home() async {
    if (pending) {
      _pendingHome ??= Completer<RepositorySnapshot<HomeSummary>>();
      return _pendingHome!.future;
    }
    _guard();
    return _snapshot(HomeSummary.fromJson(asJsonMap(_read('home.json'))));
  }

  @override
  Future<RepositorySnapshot<List<ProjectSummary>>> projects({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(
      _list<ProjectSummary>('projects.json', ProjectSummary.fromJson),
    );
  }

  @override
  Future<RepositorySnapshot<ProjectDetail>> project(
    String id, {
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(ProjectDetail.fromJson(_read('project.json')));
  }

  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(
      _list<ConnectionSummary>('connections.json', ConnectionSummary.fromJson),
    );
  }

  @override
  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals() async {
    _guard();
    return _snapshot(
      _list<ApprovalSummary>('approvals.json', ApprovalSummary.fromJson),
    );
  }

  @override
  Future<RepositorySnapshot<List<AuditEvent>>> activity({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(_list<AuditEvent>('activity.json', AuditEvent.fromJson));
  }

  @override
  Future<RepositorySnapshot<SafetyOverview>> safety() async {
    _guard();
    return _snapshot(SafetyOverview.fromJson(_read('safety.json')));
  }

  @override
  Future<RepositorySnapshot<List<ActionDefinition>>> actions() async {
    _guard();
    return _snapshot(
      _list<ActionDefinition>('actions.json', ActionDefinition.fromJson),
    );
  }

  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError('Visual evidence never performs mutations.');

  @override
  Future<IntakeReceipt> runAction({
    required String actionId,
    String? projectId,
    String? message,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError('Visual evidence never performs mutations.');

  @override
  Future<IntakeReceipt> verifyExactSource({
    required String projectId,
    required String exactSha,
    required WorkerJobClass jobClass,
    int? maxRuntimeSeconds,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError('Visual evidence never performs mutations.');

  @override
  Future<WorkerExecutionStatus> workerExecution({required String planId}) =>
      throw UnimplementedError('Visual evidence never reads worker plans.');

  @override
  Future<ApprovalDecisionResult> decideApproval({
    required String approvalId,
    required ApprovalDecision decision,
    String reason = '',
  }) =>
      throw UnimplementedError('Visual evidence never performs mutations.');

  @override
  void clearReadOnlyCache() {}

  @override
  void dispose() {
    completePendingHome();
  }
}

Future<void> _captureScreen(WidgetTester tester, _VisualCase visual) async {
  if (!_visualFontLoaded) {
    await tester.runAsync(_loadVisualFont);
  }
  await setTestSurface(tester, logicalSize: visual.logicalSize);
  final repository = _FixtureRepository(
    failing: visual.failing,
    pending: visual.pending,
  );
  Object? frameworkException;
  late final File output;
  try {
    await tester.pumpWidget(
      PandoraDependencies(
        auth: const FakeAuth(),
        repository: repository,
        diagnostics: DiagnosticsStore(),
        child: testApp(
          themeMode: visual.themeMode,
          textScaler: visual.textScaler,
          child: _withVisualFont(
            RepaintBoundary(key: _surfaceKey, child: visual.build()),
          ),
        ),
      ),
    );

    // Keep repository microtasks and visual state changes inside the finite
    // widget-test clock. The Pandora apple is vector-painted synchronously, so
    // no asset decode can hide later CI stages behind an unbounded settle.
    for (final frame in _renderFrames) {
      await tester.pump(frame);
    }
    await _waitForRenderedPandoraMark(tester, visual.name);
    frameworkException = tester.takeException();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_surfaceKey),
    );
    // Raster readback is real asynchronous engine work rather than a fake-clock
    // animation. Isolate only that bounded operation with runAsync; asset
    // precaching and state progression remain in the widget-test clock.
    final pngBytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return bytes?.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    });
    expect(pngBytes, isNotNull);

    output = File('build/owner-screen-evidence/${visual.name}.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(pngBytes!);
    expect(output.lengthSync(), greaterThan(0));

    final baseline = File('test/goldens/owner_screens/${visual.name}.png');
    // The checked-in PNGs are rendered and compared on the pinned Ubuntu CI
    // runner. Windows uses different font rasterization, so it still exercises
    // and captures every production widget but does not make a false byte-level
    // comparison against Linux pixels.
    if (baseline.existsSync() && !Platform.isWindows) {
      await expectLater(
        find.byKey(_surfaceKey),
        matchesGoldenFile('owner_screens/${visual.name}.png'),
      );
    }
  } finally {
    repository.completePendingHome();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  if (frameworkException != null) {
    if (output.existsSync()) {
      final failure = File('test/failures/owner_screens/${visual.name}.png');
      failure.parent.createSync(recursive: true);
      output.copySync(failure.path);
    }
    if (frameworkException is FlutterError) {
      debugPrint(frameworkException.toStringDeep());
    }
  }
  expect(
    frameworkException,
    isNull,
    reason: '${visual.name} raised a framework exception.',
  );
}

void main() {
  test('visual fixture timeline stays inside reviewed day buckets', () {
    expect(
      _visualRunReference.difference(_FixtureRepository._verifiedAt).inDays,
      5,
    );
    final approval = ApprovalSummary.fromJson(
      asJsonList(_FixtureRepository()._read('approvals.json')).single,
    );
    expect(approval.expiresAt!.difference(_visualRunReference).inDays, 1455);
  });

  final screens = <_VisualCase>[
    _VisualCase(
      name: 'home_attention_porcelain_390x844',
      build: () => const HomeScreen(),
    ),
    _VisualCase(
      name: 'home_degraded_graphite_390x844',
      build: () => const HomeScreen(),
      themeMode: ThemeMode.dark,
      failing: true,
    ),
    _VisualCase(
      name: 'home_loading_porcelain_390x844',
      build: () => const HomeScreen(),
      pending: true,
    ),
    _VisualCase(
      name: 'home_attention_porcelain_320x800',
      build: () => const HomeScreen(),
      logicalSize: _compactPhoneSize,
    ),
    _VisualCase(
      name: 'projects_list_porcelain_390x844',
      build: () => const ProjectsScreen(),
    ),
    _VisualCase(
      name: 'project_detail_porcelain_390x844',
      build: () => const ProjectDetailScreen(project: fixtureProject),
    ),
    _VisualCase(
      name: 'activity_populated_porcelain_390x844',
      build: () => const ActivityScreen(),
    ),
    _VisualCase(
      name: 'approvals_high_risk_porcelain_390x844',
      build: () => const ApprovalsScreen(),
    ),
    _VisualCase(
      name: 'approvals_high_risk_1_6x_text_390x844',
      build: () => const ApprovalsScreen(),
      textScaler: TextScaler.linear(1.6),
    ),
    _VisualCase(
      name: 'command_initial_porcelain_390x844',
      build: () => const CommandScreen(),
    ),
    _VisualCase(
      name: 'connections_healthy_porcelain_390x844',
      build: () => const ConnectionsScreen(),
    ),
    _VisualCase(
      name: 'connections_degraded_graphite_390x844',
      build: () => const ConnectionsScreen(),
      themeMode: ThemeMode.dark,
      failing: true,
    ),
    _VisualCase(
      name: 'memory_approved_porcelain_390x844',
      build: () => const OwnerIntelligenceScreen(
        initialSection: OwnerIntelligenceSection.memory,
      ),
    ),
    _VisualCase(
      name: 'safety_protected_porcelain_390x844',
      build: () => const SafetyScreen(),
    ),
    _VisualCase(
      name: 'settings_porcelain_390x844',
      build: () => const SettingsScreen(),
    ),
  ];

  for (final visual in screens) {
    testWidgets(
      'captures ${visual.name}',
      (tester) => _captureScreen(tester, visual),
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

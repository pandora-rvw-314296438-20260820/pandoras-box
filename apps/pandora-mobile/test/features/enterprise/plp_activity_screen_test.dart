import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_activity_screen.dart';

void main() {
  Map<String, Object?> businessFixture() => <String, Object?>{
        'schemaVersion': 'plp.business-activity.v1',
        'containsMockData': true,
        'items': <Object?>[
          <String, Object?>{
            'id': 'business-1',
            'audience': 'all',
            'category': 'payments',
            'title': 'Verified payment recorded',
            'summary': 'Payment activity is reflected in resort sales.',
            'sourceLabel': 'PLP runtime',
            'occurredAt': DateTime.now().toUtc().toIso8601String(),
            'isMock': false,
          },
          <String, Object?>{
            'id': 'task-1',
            'audience': 'team',
            'category': 'housekeeping',
            'title': 'Housekeeping completed',
            'summary': 'Ocean Villa prepared and ready',
            'sourceLabel': 'qa_staff',
            'occurredAt': DateTime.now()
                .subtract(const Duration(minutes: 22))
                .toUtc()
                .toIso8601String(),
            'isMock': true,
          },
          <String, Object?>{
            'id': 'booking-1',
            'audience': 'guests',
            'category': 'booking',
            'title': 'Booking confirmed',
            'summary': 'Guest · Villa 3 · PLP-001',
            'sourceLabel': 'PLP runtime',
            'occurredAt': DateTime.now()
                .subtract(const Duration(hours: 3))
                .toUtc()
                .toIso8601String(),
            'isMock': false,
          },
        ],
      };

  Map<String, Object?> logsFixture({
    required bool hasMore,
    required int? nextBeforeId,
    required List<Map<String, Object?>> items,
  }) =>
      <String, Object?>{
        'schemaVersion': 'plp.pandora-activity-logs.v1',
        'items': items,
        'hasMore': hasMore,
        'nextBeforeId': nextBeforeId,
      };

  testWidgets('renders PLP recent activity at narrow phone width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PlpActivityScreen(
          onOpenNavigation: () {},
          businessLoader: () async => businessFixture(),
          logLoader: ({beforeId, query}) async => logsFixture(
            hasMore: false,
            nextBeforeId: null,
            items: const <Map<String, Object?>>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plp-activity-light-page')),
      findsOneWidget,
    );
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Verified payment recorded'), findsOneWidget);
    expect(find.text('Housekeeping completed'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-activity-tab-team')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Housekeeping completed'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-activity-tab-guests')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Housekeeping completed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity Logs tab shows Pandora actions and loads more',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlpActivityScreen(
          onOpenNavigation: () {},
          businessLoader: () async => businessFixture(),
          logLoader: ({beforeId, query}) async {
            calls += 1;
            if (beforeId == null) {
              return logsFixture(
                hasMore: true,
                nextBeforeId: 40,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 50,
                    'eventType':
                        'pandora_control_plane.pandora_build_jobs.update',
                    'actorType': 'system',
                    'actorLabel': 'Pandora',
                    'resourceType': 'pandora_build_jobs',
                    'resourceId': 'build-1',
                    'requestId': 'request-1',
                    'status': 'completed',
                    'occurredAt': DateTime.now()
                        .subtract(const Duration(minutes: 8))
                        .toUtc()
                        .toIso8601String(),
                  },
                ],
              );
            }
            return logsFixture(
              hasMore: false,
              nextBeforeId: null,
              items: <Map<String, Object?>>[
                <String, Object?>{
                  'id': 39,
                  'eventType':
                      'pandora_control_plane.pandora_project_versions.insert',
                  'actorType': 'system',
                  'actorLabel': 'Pandora',
                  'resourceType': 'pandora_project_versions',
                  'resourceId': 'version-1',
                  'requestId': 'request-2',
                  'status': 'completed',
                  'occurredAt': DateTime.now()
                      .subtract(const Duration(hours: 2))
                      .toUtc()
                      .toIso8601String(),
                },
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-activity-tab-activity-logs')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build jobs updated'), findsOneWidget);
    expect(find.textContaining('Pandora · Build jobs'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('plp-activity-load-more-logs')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-activity-load-more-logs')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project versions created'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}

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
    required String? nextBeforeAt,
    required String? nextBeforeJobId,
    required int? nextBeforeSequence,
    required List<Map<String, Object?>> items,
  }) =>
      <String, Object?>{
        'schemaVersion': 'plp.pandora-activity-logs.v2',
        'items': items,
        'hasMore': hasMore,
        'nextBeforeAt': nextBeforeAt,
        'nextBeforeJobId': nextBeforeJobId,
        'nextBeforeSequence': nextBeforeSequence,
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
          logLoader: ({
            beforeAt,
            beforeJobId,
            beforeSequence,
            query,
          }) async =>
              logsFixture(
            hasMore: false,
            nextBeforeAt: null,
            nextBeforeJobId: null,
            nextBeforeSequence: null,
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
          logLoader: ({
            beforeAt,
            beforeJobId,
            beforeSequence,
            query,
          }) async {
            calls += 1;
            if (beforeAt == null) {
              return logsFixture(
                hasMore: true,
                nextBeforeAt: DateTime.now()
                    .subtract(const Duration(minutes: 8))
                    .toUtc()
                    .toIso8601String(),
                nextBeforeJobId: '11111111-1111-4111-8111-111111111111',
                nextBeforeSequence: 8,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'event-50',
                    'jobId': '11111111-1111-4111-8111-111111111111',
                    'sequence': 12,
                    'state': 'result',
                    'status': 'result',
                    'message': 'Response persisted and verified for this turn.',
                    'domain': 'chat',
                    'capability': 'intelligence.chat',
                    'sourceType': 'runtime',
                    'actorLabel': 'Pandora',
                    'requestId': 'request-1',
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
              nextBeforeAt: null,
              nextBeforeJobId: null,
              nextBeforeSequence: null,
              items: <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'event-39',
                  'jobId': '22222222-2222-4222-8222-222222222222',
                  'sequence': 3,
                  'state': 'acting',
                  'status': 'acting',
                  'message': 'Publishing the verified release candidate.',
                  'domain': 'plp-enterprise-release',
                  'capability': 'engineering',
                  'sourceType': 'provider',
                  'actorLabel': 'Pandora',
                  'requestId': 'request-2',
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

    expect(
      find.text('Response persisted and verified for this turn.'),
      findsOneWidget,
    );
    expect(find.textContaining('Pandora · Intelligence · chat'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('plp-activity-load-more-logs')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-activity-load-more-logs')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publishing the verified release candidate.'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}

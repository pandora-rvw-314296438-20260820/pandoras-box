import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_operational_screens.dart';

void main() {
  Map<String, Object?> fixture() => <String, Object?>{
        'resortCommandCenter': const <String, Object?>{
          'rooms': <Object?>[
            <String, Object?>{
              'id': 'room-1',
              'name': 'Sunset Suite',
              'state': 'departure',
              'capacity': 4,
              'bedrooms': 2,
              'nightlyRatePhp': 18000,
            },
          ],
          'stays': <Object?>[
            <String, Object?>{
              'id': 'stay-1',
              'fullName': 'Maria Santos',
              'accommodationName': 'Sunset Suite',
              'checkIn': '2026-10-01',
              'checkOut': '2026-10-03',
              'status': 'confirmed',
            },
          ],
          'experienceSignals': <Object?>[],
          'finance': <String, Object?>{
            'bookedValue30dPhp': 250000,
            'outstandingBalancePhp': 20000,
            'paidValue30dPhp': 230000,
          },
        },
        'resortOperations': const <String, Object?>{
          'workItems': <Object?>[
            <String, Object?>{
              'id': 'task-1',
              'title': 'Prepare Sunset Suite',
              'category': 'housekeeping',
              'priority': 'medium',
              'status': 'in_progress',
              'bookingReference': 'PLP-101',
              'actor': 'Housekeeping',
              'note': 'Turnover before arrival.',
              'isTestData': false,
            },
          ],
          'channelConflicts': <Object?>[],
        },
      };

  testWidgets('housekeeping opens as a proper operational workspace', (tester) async {
    String? openedKind;
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortOperationalScreen(
          moduleId: 'housekeeping',
          bootstrap: fixture(),
          onBack: () {},
          onRefresh: () {},
          onOpenRecord: (kind, record) => openedKind = kind,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plp-module-housekeeping')), findsOneWidget);
    expect(find.text('HOUSEKEEPING QUEUE'), findsOneWidget);
    expect(find.text('Prepare Sunset Suite'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-module-new-task')), findsOneWidget);
    expect(find.textContaining('Ask Pandora'), findsNothing);

    await tester.tap(find.text('Prepare Sunset Suite'));
    await tester.pump();
    expect(openedKind, 'work');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rates renders the actual rate board instead of a chat command', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlpResortOperationalScreen(
          moduleId: 'rates',
          bootstrap: fixture(),
          onBack: () {},
          onRefresh: () {},
          onOpenRecord: (_, __) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RATE BOARD'), findsOneWidget);
    expect(find.text('Sunset Suite'), findsOneWidget);
    expect(find.textContaining('₱18,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-module-new-task')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

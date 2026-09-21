import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_guests_screen.dart';

void main() {
  Map<String, Object?> fixture() => <String, Object?>{
        'organization': <String, Object?>{
          'propertyName': 'PLP Boracay',
        },
        'guestExperience': <String, Object?>{
          'businessDate': '2026-09-21',
          'inHouse': <Object?>[
            <String, Object?>{
              'id': 'guest-1',
              'fullName': 'QA Maria Santos',
              'bookingReference': 'MOCK-PLP-001',
              'accommodationName': 'Grand Ocean Villa',
              'stayDays': 3,
              'dayOfStay': 3,
              'displayStatus': 'In-house',
              'specialRequest':
                  '[MOCK QA] Airport pickup and welcome setup.',
              'isMock': true,
            },
          ],
          'arrivals': <Object?>[],
          'departing': <Object?>[],
          'attention': <Object?>[
            <String, Object?>{
              'id': 'task-1',
              'title': 'Confirm airport transfer',
              'note': '[MOCK QA] Transfer details awaiting confirmation.',
              'priority': 'high',
              'category': 'arrival',
              'status': 'open',
            },
          ],
        },
      };

  testWidgets('renders the light PLP guest experience at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: PlpGuestsScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plp-guests-light-page')),
      findsOneWidget,
    );
    expect(find.text('Guests'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('plp-guests-editorial-hero')),
      findsOneWidget,
    );
    expect(find.text('GUEST EXPERIENCE'), findsOneWidget);
    expect(
      find.text('Personal stays.\nThoughtful service.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey<String>('plp-guests-light-page')),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();

    expect(find.text('QA Maria Santos'), findsOneWidget);
    expect(find.text('Grand Ocean Villa · Day 3 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requests filter exposes real attention projection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: PlpGuestsScreen(
          bootstrap: fixture(),
          onOpenNavigation: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('plp-guests-filter-requests')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plp-guests-attention')),
      findsOneWidget,
    );
    expect(find.text('Confirm airport transfer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

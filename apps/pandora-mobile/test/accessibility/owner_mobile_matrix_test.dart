import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';
import 'package:pandora_mobile/core/widgets/content_state.dart';
import 'package:pandora_mobile/core/widgets/owner_experience.dart';
import 'package:pandora_mobile/core/widgets/status_badge.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets(
    'owner surfaces remain readable at required Android widths and text scales',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const widths = <double>[320, 360, 390, 412, 430];
      const scales = <double>[1, 1.3, 2];

      for (final width in widths) {
        tester.view.physicalSize = Size(width, 1600);
        for (final scale in scales) {
          await tester.pumpWidget(
            testApp(
              textScaler: TextScaler.linear(scale),
              child: const Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(PandoraSpacing.md),
                    child: _OwnerMatrixFixture(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'layout failed at ${width}px and ${scale}x text',
          );
        }
      }
    },
  );

  testWidgets(
    'loading to loaded to partial-data transition keeps usable content',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(320, 900));

      await tester.pumpWidget(
        testApp(
          child: const Scaffold(
            body: SafeArea(child: ContentSkeleton(lines: 7)),
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        testApp(
          child: const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(child: _OwnerMatrixFixture()),
            ),
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No verified work is running.'), findsOneWidget);

      await tester.pumpWidget(
        testApp(
          child: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DegradedContentNotice(
                      message:
                          'Showing the previous usable owner view while fresh verification is unavailable.',
                      onRetry: () {},
                    ),
                    const _OwnerMatrixFixture(),
                  ],
                ),
              ),
            ),
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No verified work is running.'), findsOneWidget);
    },
  );
}

class _OwnerMatrixFixture extends StatelessWidget {
  const _OwnerMatrixFixture();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OwnerBriefingHero(
            eyebrow: 'Owner briefing',
            title:
                'A very long project name remains readable during verification changes',
            message:
                'Pandora preserves the previous usable result while a long verification message refreshes in the background without collapsing the mobile layout.',
            icon: Icons.auto_awesome_rounded,
            statusLabel: '2 of 5 verified · Tested missing',
          ),
          const SizedBox(height: PandoraSpacing.md),
          const OwnerMetricGrid(
            metrics: [
              OwnerMetric(
                label: 'Owner decisions that genuinely require action',
                value: '0',
                icon: Icons.approval_outlined,
              ),
              OwnerMetric(
                label: 'Working now with verified execution evidence',
                value: '0',
                icon: Icons.play_circle_outline_rounded,
              ),
              OwnerMetric(
                label: 'Portfolio attention with verified blockers',
                value: '6',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
          OwnerSectionHeading(
            title: 'Recommended next action with long explanatory text',
            subtitle:
                'The trailing control must stack instead of squeezing this copy into a one-character column.',
            trailing: FilledButton.tonal(
              onPressed: _noop,
              child: const Text('Prepare this exact action'),
            ),
          ),
          const SizedBox(height: PandoraSpacing.sm),
          const OwnerSignal(
            label: 'Current execution',
            value: 'No verified work is running.',
            icon: Icons.pause_circle_outline_rounded,
          ),
          const SizedBox(height: PandoraSpacing.sm),
          const OwnerSignal(
            label: 'Long verification detail',
            value:
                'Deployment has not been checked. The last verified source exists, but current production behavior remains unknown until fresh evidence is returned.',
            icon: Icons.verified_outlined,
            tone: PandoraStatusTone.attention,
          ),
        ],
      );
}

void _noop() {}

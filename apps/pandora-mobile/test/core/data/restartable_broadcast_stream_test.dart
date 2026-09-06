import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/restartable_broadcast_stream.dart';

void main() {
  testWidgets(
    'listener replacement opens a fresh single-subscription source era',
    (tester) async {
      final sources = <StreamController<int>>[];
      var sourceFactoryCalls = 0;

      Stream<int> sourceFactory() {
        sourceFactoryCalls += 1;
        final source = StreamController<int>(sync: true);
        sources.add(source);
        return source.stream;
      }

      final shared = restartableBroadcastStream<int>(sourceFactory);

      Widget host({required bool mounted}) => MaterialApp(
            home: mounted
                ? StreamBuilder<int>(
                    stream: shared,
                    initialData: 0,
                    builder: (context, snapshot) => Text(
                      '${snapshot.data ?? -1}',
                      textDirection: TextDirection.ltr,
                    ),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(host(mounted: true));
      expect(sourceFactoryCalls, 1);
      expect(shared.isBroadcast, isTrue);

      sources.single.add(21);
      await tester.pump();
      expect(find.text('21'), findsOneWidget);

      await tester.pumpWidget(host(mounted: false));
      await tester.pump();

      await tester.pumpWidget(host(mounted: true));
      await tester.pump();
      expect(sourceFactoryCalls, 2);
      expect(sources, hasLength(2));

      sources.last.add(22);
      await tester.pump();
      expect(find.text('22'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(mounted: false));
      await tester.pump();
      for (final source in sources) {
        await source.close();
      }
    },
  );

  test('concurrent listeners share one authoritative source era', () async {
    var sourceListenCount = 0;
    final source = StreamController<int>(
      sync: true,
      onListen: () => sourceListenCount += 1,
    );
    final shared = restartableBroadcastStream<int>(() => source.stream);
    final firstValues = <int>[];
    final secondValues = <int>[];

    final first = shared.listen(firstValues.add);
    final second = shared.listen(secondValues.add);
    source.add(7);

    expect(sourceListenCount, 1);
    expect(firstValues, <int>[7]);
    expect(secondValues, <int>[7]);

    await first.cancel();
    await second.cancel();
    await source.close();
  });
}

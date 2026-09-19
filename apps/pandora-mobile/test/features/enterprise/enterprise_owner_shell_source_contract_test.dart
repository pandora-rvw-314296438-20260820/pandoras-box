import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/app/pandora_chat_shell.dart').readAsStringSync();
  });

  test('Enterprise owner shell hides generic chat chrome', () {
    expect(source, contains('final enterpriseActive = selectedIndex >= 8;'));
    expect(source, contains("if (!enterpriseActive) ...["));
    expect(source, contains("'Recent chats'"));
    expect(source, contains("'pandora-new-chat'"));
    expect(source, contains("'pandora-search-chats'"));
  });

  test('Enterprise owner shell removes developer navigation from owner menu',
      () {
    expect(source,
        contains('const ownerIndexes = <int>[8, 23, 28, 24, 9, 25, 26, 27, 21];'));
    expect(source, isNot(contains('System / Developer')));
    expect(source, isNot(contains('Privileged technical surfaces')));
    expect(source, contains("'PROPERTY OPERATIONS'"));
    expect(source, contains("'POWERED BY PANDORA'"));
    expect(source, contains("width: _index >= 8 ? 248 : 264"));
    expect(source, contains("'Operations'"));
    expect(source, contains("'Guests'"));
    expect(source, contains("'Revenue'"));
    expect(source, contains("'Vision Intelligence'"));
  });
}
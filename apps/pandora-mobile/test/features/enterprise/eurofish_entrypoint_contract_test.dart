import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business 1 boots Euro-Fish as the visible workspace', () {
    final shell = File('lib/app/pandora_chat_shell.dart').readAsStringSync();
    final eurofish = File(
      'lib/features/enterprise/eurofish_enterprise_screen.dart',
    ).readAsStringSync();

    expect(shell, contains('final Set<int> _visited = <int>{9};'));
    expect(shell, contains('int _index = 9;'));
    expect(shell, contains('9 => const EurofishEnterpriseScreen()'));
    expect(
      shell,
      contains(
        'for (final index in const <int>[9, 0, 8, 1, 2, 4, 5, 6, 7, 3])',
      ),
    );
    expect(eurofish, contains('1064 Euro-Fish Trading'));
    expect(eurofish, contains('Ask Pandora to work on this page…'));
  });
}

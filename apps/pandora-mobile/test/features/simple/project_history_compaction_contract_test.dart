import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history keeps a persistent return-to-live control', () {
    final source = File('lib/features/simple/project_history_screen.dart')
        .readAsStringSync();

    expect(source, contains("label: const Text('Return to live')"));
    expect(source, contains('Navigator.of(context).maybePop()'));
  });

  test('proposal and completed build history are compact by default', () {
    final source = File('lib/features/simple/project_history_screen.dart')
        .readAsStringSync();

    expect(source, contains("'View plan'"));
    expect(source, contains('latestProposalId'));
    expect(source, contains('collapseProposal:'));
    expect(source, contains('item.isProposal && item.id != latestProposalId'));
    expect(
      source,
      contains(
        '_expanded = widget.item.isProposal && !widget.collapseProposal',
      ),
    );
    expect(source, contains("'View build evidence'"));
    expect(source, contains('_completedBuildSummary(item)'));
    for (final metric in const [
      'buildNumber',
      'durationMs',
      'fileCount',
      'lineCount',
      'checksTotal',
      'checksPassed',
      'checksFailed',
      'checksBlocked',
    ]) {
      expect(source, contains("payloadInt('$metric')"));
    }
  });
}

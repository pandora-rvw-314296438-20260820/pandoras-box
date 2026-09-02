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
    expect(
      source,
      contains(
        'collapseProposal: item.isProposal && item.id != latestProposalId',
      ),
    );
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

  test('source generation persists file and line metrics on exact version', () {
    final source = File(
      '../../supabase/functions/pandora-project-source-generator/index.ts',
    ).readAsStringSync();

    expect(source, contains('const sourceFileCount = files.length;'));
    expect(source, contains('const sourceLineCount = files.reduce'));
    expect(source, contains('fileCount: sourceFileCount'));
    expect(source, contains('lineCount: sourceLineCount'));
    expect(source, contains('.eq("id", projectVersionId)'));
  });

  test(
    'conversation projection exposes only durable build summary metrics',
    () {
      final source = File(
        '../../supabase/migrations/20260902181500_pandora_history_compaction_metrics_v1.sql',
      ).readAsStringSync();

      for (final metric in const [
        "'buildNumber'",
        "'durationMs'",
        "'fileCount'",
        "'lineCount'",
        "'checksTotal'",
        "'checksPassed'",
        "'checksFailed'",
        "'checksBlocked'",
      ]) {
        expect(source, contains(metric));
      }
      expect(source, contains('pv.build_job_id = j.id'));
      expect(
        source,
        contains('vc.verification_run_id = v.verification_run_id'),
      );
    },
  );
}

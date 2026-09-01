
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact diff is bound to verified baseline and candidate source bundles', () {
    final source =
        File('lib/features/simple/project_experience_v2.dart').readAsStringSync();

    expect(source, contains("import 'project_exact_source_diff.dart';"));
    expect(source, contains('ProjectExactSourceDiff? _lastChangeDiff;'));
    expect(source, contains('ProjectExactSourceDiff.fromExactPreviewBundles('));
    expect(source, contains('projection.currentVerified'));
    expect(source, contains('projection.currentVersionId != baselineVersionId'));
    expect(source, contains('projection.candidateVersionId != candidateVersionId'));
    expect(source, contains('changeDiff: _lastChangeDiff'));
  });

  test('workspace exposes compact exact changes without raw source', () {
    final view = File('lib/features/simple/project_workspace_v2_view.dart')
        .readAsStringSync();

    expect(view, contains('changeDiff'));
    expect(view, contains('View changes'));
    expect(view, contains('_ExactSourceDiffSheet'));
    expect(view, contains('diff.compactSummary'));
    expect(view, isNot(contains('dataBase64')));
  });
}

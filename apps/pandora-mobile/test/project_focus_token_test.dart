import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_focus_token.dart';

void main() {
  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('FocusToken rejects stale visible version and artifact lineage', () {
    final token = ProjectFocusToken.create(
      projectId: 'project-1',
      versionId: 'version-1',
      artifactDigest: digest,
      semanticId: 'hero.book-now',
      selector: 'button#book-now',
      role: 'button',
      accessibleName: 'Book now',
      route: '/',
      sourceFile: 'index.html',
      sourceLine: 42,
      bounds: const ProjectFocusBounds(x: 10, y: 20, width: 120, height: 44),
    );

    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
      ),
      isTrue,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-2',
        artifactDigest: digest,
      ),
      isFalse,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      isFalse,
    );
    expect(token.intentContext, contains('semantic_id=hero.book-now'));
    expect(token.intentContext, contains('source=index.html:42'));
  });

  test('FocusToken rejects invalid artifact digests', () {
    expect(
      () => ProjectFocusToken.create(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: 'invalid',
        semanticId: 'hero',
        selector: '#hero',
        role: '',
        accessibleName: '',
        route: '/',
        sourceFile: 'index.html',
      ),
      throwsFormatException,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_focus_token.dart';

void main() {
  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final issued = DateTime.utc(2026, 9, 1);
  final expires = issued.add(const Duration(minutes: 10));

  ProjectFocusToken makeToken() => ProjectFocusToken.create(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        semanticId: 'hero.book-now',
        componentId: 'booking.hero',
        selector: 'button#book-now',
        role: 'button',
        accessibleName: 'Book now',
        route: '/',
        sourceFile: 'index.html',
        sourceLine: 42,
        bounds: const ProjectFocusBounds(
          x: 10,
          y: 20,
          width: 120,
          height: 44,
        ),
        issuedAt: issued,
        expiresAt: expires,
      );

  test('FocusToken serializes component identity and expiry', () {
    final token = makeToken();
    final json = token.toJson();

    expect(ProjectFocusToken.schemaVersion, 2);
    expect(json['componentId'], 'booking.hero');
    expect(json['issuedAt'], issued.toIso8601String());
    expect(json['expiresAt'], expires.toIso8601String());
    expect(token.intentContext, contains('component_id=booking.hero'));
    expect(token.intentContext, contains('semantic_id=hero.book-now'));
    expect(token.intentContext, contains('source=index.html:42'));
  });

  test('FocusToken rejects stale version, artifact and expiry', () {
    final token = makeToken();

    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        now: issued.add(const Duration(minutes: 9)),
      ),
      isTrue,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-2',
        artifactDigest: digest,
        now: issued,
      ),
      isFalse,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        now: issued,
      ),
      isFalse,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        now: expires,
      ),
      isFalse,
    );
  });

  test('FocusToken rejects invalid artifact digests and expiry windows', () {
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
        issuedAt: issued,
        expiresAt: expires,
      ),
      throwsFormatException,
    );
    expect(
      () => ProjectFocusToken.create(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        semanticId: 'hero',
        selector: '#hero',
        role: '',
        accessibleName: '',
        route: '/',
        sourceFile: 'index.html',
        issuedAt: issued,
        expiresAt: issued,
      ),
      throwsFormatException,
    );
  });
}

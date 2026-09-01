import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_focus_token.dart';

void main() {
  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final issuedAt = DateTime.utc(2026, 9, 1, 0, 0);
  final expiresAt = issuedAt.add(ProjectFocusToken.defaultTtl);

  test('FocusToken rejects stale visible version and artifact lineage', () {
    final token = ProjectFocusToken.create(
      projectId: 'project-1',
      versionId: 'version-1',
      artifactDigest: digest,
      componentId: 'checkout.book-now',
      semanticId: 'hero.book-now',
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
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        at: issuedAt,
      ),
      isTrue,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-2',
        artifactDigest: digest,
        at: issuedAt,
      ),
      isFalse,
    );
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        at: issuedAt,
      ),
      isFalse,
    );
    expect(token.intentContext, contains('component_id=checkout.book-now'));
    expect(token.intentContext, contains('semantic_id=hero.book-now'));
    expect(token.intentContext, contains('source=index.html:42'));
  });

  test('FocusToken expires exactly at its bounded expiry', () {
    final token = ProjectFocusToken.create(
      projectId: 'project-1',
      versionId: 'version-1',
      artifactDigest: digest,
      componentId: 'hero.book-now',
      semanticId: 'hero.book-now',
      selector: 'button#book-now',
      role: 'button',
      accessibleName: 'Book now',
      route: '/',
      sourceFile: 'index.html',
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    expect(
        token.isExpired(
            at: expiresAt.subtract(const Duration(microseconds: 1))),
        isFalse);
    expect(token.isExpired(at: expiresAt), isTrue);
    expect(
      token.matchesVisible(
        projectId: 'project-1',
        versionId: 'version-1',
        artifactDigest: digest,
        at: expiresAt,
      ),
      isFalse,
    );
  });

  test('FocusToken v2 serializes component identity and bounded lifetime', () {
    final token = ProjectFocusToken.create(
      projectId: 'project-1',
      versionId: 'version-1',
      artifactDigest: digest,
      componentId: 'pricing.primary-cta',
      semanticId: 'pricing.cta',
      selector: '[data-pandora-id="pricing.cta"]',
      role: 'button',
      accessibleName: 'Start now',
      route: '/pricing',
      sourceFile: 'src/pricing.html',
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    expect(ProjectFocusToken.schemaVersion, 2);
    expect(token.componentId, 'pricing.primary-cta');
    expect(token.toJson()['componentId'], 'pricing.primary-cta');
    expect(token.toJson()['issuedAt'], issuedAt.toIso8601String());
    expect(token.toJson()['expiresAt'], expiresAt.toIso8601String());
  });

  test('FocusToken derives component identity when explicit id is absent', () {
    final token = ProjectFocusToken.create(
      projectId: 'project-1',
      versionId: 'version-1',
      artifactDigest: digest,
      semanticId: 'hero.book-now',
      selector: 'button#book-now',
      role: '',
      accessibleName: '',
      route: '/',
      sourceFile: 'index.html',
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    expect(token.componentId, 'hero.book-now');
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
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      ),
      throwsFormatException,
    );
  });

  test('FocusToken rejects non-positive and overlong lifetimes', () {
    ProjectFocusToken createWithExpiry(DateTime expiry) =>
        ProjectFocusToken.create(
          projectId: 'project-1',
          versionId: 'version-1',
          artifactDigest: digest,
          semanticId: 'hero',
          selector: '#hero',
          role: '',
          accessibleName: '',
          route: '/',
          sourceFile: 'index.html',
          issuedAt: issuedAt,
          expiresAt: expiry,
        );

    expect(() => createWithExpiry(issuedAt), throwsFormatException);
    expect(
      () => createWithExpiry(
        issuedAt.add(ProjectFocusToken.defaultTtl + const Duration(seconds: 1)),
      ),
      throwsFormatException,
    );
  });
}

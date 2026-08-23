import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_sanitizer.dart';

void main() {
  const sanitizer = DiagnosticsSanitizer();

  test('recursively removes credentials, identity values, and query data', () {
    final sanitized = sanitizer.sanitize(<String, Object?>{
      'headers': <String, Object?>{
        'Authorization': 'Bearer header.payload.signature',
        'Cookie': 'session=private',
        'X-Request-Id': 'request-safe-1',
      },
      'nested': <Object?>[
        <String, Object?>{
          'service_${'role'}_key': 'sb_${'secret'}_private',
          'note': 'Contact owner@example.com using Bearer abc.def.ghi',
        },
      ],
      'url': 'https://example.invalid/path?access_token=private&email=private',
    }) as Map<String, Object?>;

    final encoded = sanitized.toString();
    expect(encoded, contains('request-safe-1'));
    expect(encoded, isNot(contains('session=private')));
    expect(encoded, isNot(contains('sb_${'secret'}_private')));
    expect(encoded, isNot(contains('owner@example.com')));
    expect(encoded, isNot(contains('access_token=private')));
    expect(encoded, contains(DiagnosticsSanitizer.redacted));
  });

  test('bounds nested depth, list count, map count, and string length', () {
    const bounded = DiagnosticsSanitizer(
      maxDepth: 2,
      maxMapEntries: 1,
      maxListItems: 1,
      maxStringLength: 8,
    );
    final sanitized = bounded.sanitize(<String, Object?>{
      'first': <String, Object?>{
        'nested': <String, Object?>{'tooDeep': true},
      },
      'second': 'discarded',
    });

    expect(sanitized.toString(), contains(DiagnosticsSanitizer.truncated));
  });

  test('removes query data from URLs embedded in prose', () {
    final sanitized = sanitizer.sanitizeText(
      'Retry https://example.invalid/path?token=private&owner=owner@example.com now.',
    );

    expect(sanitized, contains('https://example.invalid/path?redacted'));
    expect(sanitized, isNot(contains('token=private')));
    expect(sanitized, isNot(contains('owner@example.com')));
  });
}

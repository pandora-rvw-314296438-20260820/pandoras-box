import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/simple_publish_eligibility.dart';

void main() {
  const candidate = 'version-candidate';

  String? evaluate({
    String? projectedCandidateVersionId = candidate,
    bool projectionCanPublish = true,
    bool candidateVerified = true,
    bool candidateIsVisible = true,
    String? runtimeCandidateVersionId = candidate,
    String? verificationVersionId = candidate,
    bool runtimePublishEligible = true,
  }) {
    return simplePublishEligibleVersion(
      projectedCandidateVersionId: projectedCandidateVersionId,
      projectionCanPublish: projectionCanPublish,
      candidateVerified: candidateVerified,
      candidateIsVisible: candidateIsVisible,
      runtimeCandidateVersionId: runtimeCandidateVersionId,
      verificationVersionId: verificationVersionId,
      runtimePublishEligible: runtimePublishEligible,
    );
  }

  test('returns the exact candidate only when every authority agrees', () {
    expect(evaluate(), candidate);
  });

  test('fails closed when projection or visible candidate is not eligible', () {
    expect(evaluate(projectionCanPublish: false), isNull);
    expect(evaluate(candidateVerified: false), isNull);
    expect(evaluate(candidateIsVisible: false), isNull);
    expect(evaluate(projectedCandidateVersionId: null), isNull);
  });

  test('fails closed when runtime candidate identity drifts', () {
    expect(evaluate(runtimeCandidateVersionId: 'another-version'), isNull);
    expect(evaluate(runtimeCandidateVersionId: null), isNull);
  });

  test('fails closed unless runtime verification is publish eligible for candidate', () {
    expect(evaluate(runtimePublishEligible: false), isNull);
    expect(evaluate(verificationVersionId: 'another-version'), isNull);
    expect(evaluate(verificationVersionId: null), isNull);
  });

  test('normalizes harmless surrounding whitespace but not identity changes', () {
    expect(
      evaluate(
        projectedCandidateVersionId: '  $candidate  ',
        runtimeCandidateVersionId: ' $candidate ',
        verificationVersionId: '$candidate  ',
      ),
      candidate,
    );
  });
}

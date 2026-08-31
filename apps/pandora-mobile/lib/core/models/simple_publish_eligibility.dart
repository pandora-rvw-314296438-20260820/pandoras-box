String? simplePublishEligibleVersion({
  required String? projectedCandidateVersionId,
  required bool projectionCanPublish,
  required bool candidateVerified,
  required bool candidateIsVisible,
  required String? runtimeCandidateVersionId,
  required String? verificationVersionId,
  required bool runtimePublishEligible,
}) {
  String? normalized(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  final candidateVersionId = normalized(projectedCandidateVersionId);
  if (candidateVersionId == null ||
      !projectionCanPublish ||
      !candidateVerified ||
      !candidateIsVisible) {
    return null;
  }

  if (normalized(runtimeCandidateVersionId) != candidateVersionId ||
      !runtimePublishEligible ||
      normalized(verificationVersionId) != candidateVersionId) {
    return null;
  }

  return candidateVersionId;
}

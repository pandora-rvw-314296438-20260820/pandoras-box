/// Canonical Simple Mode status vocabulary, aligned with control-tower #491.
///
/// Simple surfaces may only present these five labels. Theatre stage rails
/// (Understanding / Building / Preview Ready / …) are separate and must not
/// leak into Simple status badges.
abstract final class PandoraSimpleStatus {
  static const working = 'Working';
  static const ready = 'Ready';
  static const live = 'Live';
  static const needsYou = 'Needs You';
  static const problem = 'Problem';

  static const Set<String> all = {working, ready, live, needsYou, problem};

  /// Map arbitrary wire / legacy status text into the Simple vocabulary.
  static String fromWire(String? value) {
    final status = (value ?? '').trim().toUpperCase().replaceAll('_', ' ');
    if (status.isEmpty) return working;
    if (status == 'LIVE') return live;
    if (const {
      'COMPLETE',
      'COMPLETED',
      'READY',
      'DONE',
      'PREVIEW READY',
      'REVIEW',
    }.contains(status)) {
      return ready;
    }
    if (const {
      'NEEDS YOU',
      'NEEDSYOU',
      'APPROVAL',
      'APPROVAL REQUIRED',
    }.contains(status)) {
      return needsYou;
    }
    if (const {
      'PARTIAL',
      'BLOCKED',
      'UNAVAILABLE',
      'FAILED',
      'ERROR',
      'PROBLEM',
      'STOPPED',
    }.contains(status)) {
      return problem;
    }
    if (const {
      'ACTIVE',
      'IN-PROGRESS',
      'IN PROGRESS',
      'WORKING',
      'QUEUED-QUALIFICATION',
      'NOW',
      'BUILDING',
      'CHECKING',
      'PREPARING',
      'STARTING',
      'PLANNED',
      'NOT-STARTED',
      'NOT STARTED',
      'LATER',
      'DRAFT',
      'UNDERSTANDING',
      'DESIGNING',
      'CONNECTING',
      'PUBLISHING',
      'DEPLOYING',
    }.contains(status)) {
      return working;
    }
    if (status.contains('NEED')) return needsYou;
    if (status.contains('LIVE')) return live;
    if (status.contains('READY') || status.contains('REVIEW')) return ready;
    if (status.contains('BLOCK') ||
        status.contains('FAIL') ||
        status.contains('ERROR') ||
        status.contains('PROBLEM')) {
      return problem;
    }
    return working;
  }
}

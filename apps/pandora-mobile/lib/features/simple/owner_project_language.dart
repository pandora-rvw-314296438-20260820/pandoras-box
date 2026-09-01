import '../../core/models/project_journey_models.dart';

enum PandoraOwnerBuildStage {
  understanding,
  designing,
  building,
  connecting,
  checking,
  fixing,
  preparingPreview,
  previewReady,
}

class PandoraOwnerBuildStageCopy {
  const PandoraOwnerBuildStageCopy(this.label, this.detail);

  final String label;
  final String detail;
}

PandoraOwnerBuildStageCopy pandoraOwnerBuildStageCopy(
  PandoraOwnerBuildStage stage,
) {
  switch (stage) {
    case PandoraOwnerBuildStage.understanding:
      return const PandoraOwnerBuildStageCopy(
        'Understanding your project',
        'Pandora is confirming the result you asked for.',
      );
    case PandoraOwnerBuildStage.designing:
      return const PandoraOwnerBuildStageCopy(
        'Designing the experience',
        'Pandora is shaping the experience around your goal.',
      );
    case PandoraOwnerBuildStage.building:
      return const PandoraOwnerBuildStageCopy(
        'Building your project',
        'Pandora is creating the working version.',
      );
    case PandoraOwnerBuildStage.connecting:
      return const PandoraOwnerBuildStageCopy(
        'Connecting everything',
        'Pandora is joining the parts your project needs.',
      );
    case PandoraOwnerBuildStage.checking:
      return const PandoraOwnerBuildStageCopy(
        'Checking the result',
        'Pandora is checking this version before the next step.',
      );
    case PandoraOwnerBuildStage.fixing:
      return const PandoraOwnerBuildStageCopy(
        'Fixing something',
        'Pandora found something to fix and is working on it.',
      );
    case PandoraOwnerBuildStage.preparingPreview:
      return const PandoraOwnerBuildStageCopy(
        'Preparing your preview',
        'Pandora is making this version available for you to inspect.',
      );
    case PandoraOwnerBuildStage.previewReady:
      return const PandoraOwnerBuildStageCopy(
        'Preview ready',
        'Your latest live preview is ready to open.',
      );
  }
}

PandoraOwnerBuildStage pandoraOwnerBuildStage(ProjectRuntimeSnapshot snapshot) {
  final project = snapshot.project;
  final previewStatus = snapshot.preview?.status.toLowerCase() ?? '';
  final signal = <String>[
    project.stage,
    project.runtimeStatus,
    previewStatus,
  ].join(' ').toLowerCase();

  if (_containsAny(signal, const [
    'repair',
    'fixing',
    'failed',
    'blocked',
    'needs_attention',
    'error',
  ])) {
    return PandoraOwnerBuildStage.fixing;
  }

  if (pandoraHasLivePreview(snapshot)) {
    return PandoraOwnerBuildStage.previewReady;
  }

  if (snapshot.preview != null ||
      _containsAny(signal, const ['preview', 'deploying', 'pending'])) {
    return PandoraOwnerBuildStage.preparingPreview;
  }

  if (_containsAny(signal, const [
    'verification',
    'verifying',
    'checking',
    'testing',
    'tests',
  ])) {
    return PandoraOwnerBuildStage.checking;
  }

  if (_containsAny(signal, const ['integration', 'connecting', 'database'])) {
    return PandoraOwnerBuildStage.connecting;
  }

  if (_containsAny(signal, const [
    'building',
    'generation',
    'generating',
    'workspace',
    'updating',
  ])) {
    return PandoraOwnerBuildStage.building;
  }

  if (_containsAny(signal, const ['designing', 'planning', 'architecture'])) {
    return PandoraOwnerBuildStage.designing;
  }

  return PandoraOwnerBuildStage.understanding;
}

bool pandoraHasLivePreview(ProjectRuntimeSnapshot snapshot) {
  final url = snapshot.preview?.url ?? snapshot.project.previewUrl;
  final status = snapshot.preview?.status.toLowerCase() ?? '';
  final failed = _containsAny(status, const ['failed', 'error', 'canceled']);
  return url != null && url.trim().isNotEmpty && !failed;
}

bool pandoraBuildAppearsInFlight(ProjectRuntimeSnapshot snapshot) {
  final values = <String>[
    snapshot.project.stage,
    snapshot.project.runtimeStatus,
    snapshot.preview?.status ?? '',
  ];
  final signal = values.join(' ').toLowerCase();
  return _containsAny(signal, const [
    'building',
    'working',
    'pending',
    'queued',
    'deploying',
    'checking',
    'verifying',
    'repairing',
    'updating',
  ]);
}

String pandoraOwnerProjectState(CustomerProject project) {
  final signal = <String>[
    project.stage,
    project.runtimeStatus,
  ].join(' ').toLowerCase();

  if (project.liveUrl != null && project.liveUrl!.trim().isNotEmpty) {
    return 'Live';
  }
  if (_containsAny(signal, const ['blocked', 'failed', 'error'])) {
    return 'Blocked';
  }
  if (_containsAny(signal, const ['needs_you', 'approval_required'])) {
    return 'Needs You';
  }
  if (project.previewUrl != null && project.previewUrl!.trim().isNotEmpty) {
    return 'Preview ready';
  }
  if (_containsAny(signal, const ['verification', 'verifying', 'checking'])) {
    return 'Checking';
  }
  if (_containsAny(signal, const ['building', 'working', 'updating'])) {
    return 'Building';
  }
  if (_containsAny(signal, const ['understanding', 'spec'])) {
    return 'Understanding';
  }
  return 'Draft';
}

String pandoraOwnerFailureMessage(String? internalState) {
  final state = (internalState ?? '').toLowerCase();
  if (state.contains('verification')) {
    return 'Pandora is still checking this version.';
  }
  if (state.contains('approval') || state.contains('policy')) {
    return 'Pandora needs your approval.';
  }
  if (state.contains('migration') || state.contains('data')) {
    return 'Pandora found a data change that needs review.';
  }
  if (state.contains('deploy') || state.contains('publish')) {
    return 'Pandora couldn’t make this version live yet.';
  }
  return 'Pandora found something to fix.';
}

bool _containsAny(String value, List<String> needles) {
  for (final needle in needles) {
    if (value.contains(needle)) {
      return true;
    }
  }
  return false;
}

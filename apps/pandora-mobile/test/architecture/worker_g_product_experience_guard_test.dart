import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Simple V2 keeps only the three customer navigation surfaces', () {
    final shell = File('lib/app/pandora_shell.dart').readAsStringSync();
    for (final declaration in const [
      "_Destination('Home'",
      "_Destination('Work'",
      "'Needs You'",
    ]) {
      expect(shell, contains(declaration));
    }
    expect(shell, isNot(contains("'Ask Pandora'")));
    expect(shell, isNot(contains("_Destination('More'")));
    expect(shell, isNot(contains('emphasized: true')));
  });

  test('Home is intent-first and does not expose domain management', () {
    final source =
        File('lib/features/simple/simple_home_screen.dart').readAsStringSync();
    expect(source, contains('What do you want'));
    expect(source, contains('to make happen?'));
    expect(source, contains("'Your projects'"));
    expect(source, contains("'Needs you'"));
    expect(source, isNot(contains("title: 'Domains'")));
    expect(source, isNot(contains('DomainsScreen')));
  });

  test('project creation no longer requires a project type decision', () {
    final source = File('lib/features/simple/project_create_experience.dart')
        .readAsStringSync();
    expect(source, contains('ProjectBuildKind.helpMeDecide'));
    expect(source, contains("intentKind: 'create'"));
    expect(source, isNot(contains('_kindStep')));
    expect(source, isNot(contains('Choose the closest starting point')));
  });

  test('object-first build experience uses durable runtime truth', () {
    final source = File('lib/features/simple/project_experience_v2.dart')
        .readAsStringSync();
    final view = File('lib/features/simple/project_workspace_v2_view.dart')
        .readAsStringSync();
    expect(source, contains('experience.runtime(widget.project.id)'));
    expect(source, contains('requestBuild('));
    expect(source, contains('createPreview('));
    expect(source, contains('openPreviewBundle'));
    expect(source, contains('submitChange('));
    expect(source, contains('projectExperienceRepository'));
    expect(source, contains('_projection?.canPublish == true'));
    expect(source, isNot(contains('.projectRuntime;')));
    expect(source, isNot(contains('.projectExperience;')));
    expect(source, isNot(contains('.projectExperienceProjection;')));
    expect(source, contains('_projection?.candidateVersionId != null'));
    expect(source, contains('projection.productionVersionId == versionId'));
    expect(source, contains('ProjectWorkspaceV2View('));
    expect(source, isNot(contains('PandoraV2IntentSurface(')));
    expect(view, contains('PandoraEmbeddedPreview'));
    expect(view, contains("'Designing'"));
    expect(view, contains("'Building'"));
    expect(view, contains("'Checking'"));
    expect(view, contains("'Verified change'"));
    expect(source, contains('_tryIntelligenceTurn'));
    expect(source, contains('_flowTimeout'));
    expect(source, contains('_previewRetryLimit'));
    expect(view, contains('_ExactPreviewLoadingSurface'));
    expect(view, contains('selectionEnabled: selectionMode'));
    expect(view, contains('_SelectionContextCapsule'));
    expect(view, contains('Tell Pandora what to change…'));
    expect(source, contains('Your request is saved'));
    expect(source, isNot(contains('CURRENT OBJECT')));
    expect(source, isNot(contains('Your first version is ready')));
    expect(source, isNot(contains('AnimationController(')));
    expect(source, isNot(contains('Watch your project take shape')));
    expect(view, contains('class ProjectWorkspaceV2View'));
    expect(view, contains('ProjectChangePhase'));
  });

  test('workspace uses a native snapping Pandora composer sheet', () {
    final view = File('lib/features/simple/project_workspace_v2_view.dart')
        .readAsStringSync();
    expect(view, contains('DraggableScrollableSheet('));
    expect(view, contains('initialChildSize: .18'));
    expect(view, contains('minChildSize: .18'));
    expect(view, contains('maxChildSize: .64'));
    expect(view, contains('snapSizes: const [.38]'));
    expect(view, contains('class _PandoraComposerSheet'));
    expect(view, contains('controller: scrollController'));
    expect(view, contains('PandoraV2IntentSurface('));
  });

  test('canonical Pandora mark cannot be recolored red by callers', () {
    final source =
        File('lib/core/widgets/pandora_mark.dart').readAsStringSync();
    expect(
      source,
      contains(
        '8a35b74baec47b960a42bb74587f9c531d6cbf8d45f16061836a9e63f00efcc5',
      ),
    );
    expect(source, contains('const Color(0xFF171717)'));
    expect(source, isNot(contains('final effectiveColor = color ??')));
  });

  test('Simple V2 owner copy does not name infrastructure providers', () {
    final sources = <String>[
      File('lib/features/simple/simple_home_screen.dart').readAsStringSync(),
      File('lib/features/simple/project_create_experience.dart')
          .readAsStringSync(),
      File('lib/features/simple/projects_screen.dart').readAsStringSync(),
    ].join('\n');
    for (final forbidden in const [
      'Vercel',
      'GitHub',
      'GitLab',
      'Gemini',
      'GPT',
    ]) {
      expect(sources, isNot(contains(forbidden)));
    }
  });

  test('project change compilation retries instead of silently stalling', () {
    final source =
        File('lib/core/data/project_experience_api.dart').readAsStringSync();
    expect(source, contains("'pandora-project-spec-compiler'"));
    expect(source, contains('Duration(seconds: 8)'));
    expect(source, contains('Duration(seconds: 12)'));
    expect(source, contains('_lastCompilationRequest.remove(sourceIntentId)'));
  });

  test('developer diagnostics authorization has a bounded loading state', () {
    final source = File(
      'lib/features/diagnostics/developer_diagnostics_screen.dart',
    ).readAsStringSync();
    expect(source, contains('_authorizationRequestTimeout'));
    expect(source, contains("'Checking owner access'"));
    expect(source, contains('repository.home().timeout('));
  });
}

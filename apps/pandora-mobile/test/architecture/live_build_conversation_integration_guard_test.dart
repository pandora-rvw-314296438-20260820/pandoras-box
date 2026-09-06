import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'build conversation uses durable lifecycle plus authoritative theatre evidence',
    () {
      final source = File('lib/features/simple/project_build_conversation.dart')
          .readAsStringSync();

      expect(source, contains('watchResilientBuildStream('));
      expect(source, contains('watchExperience(widget.project.id)'));
      expect(
        source,
        contains('ProjectBuildStreamTheatreProjection.fromSnapshot('),
      );
      expect(source, contains('LiveBuildTheatre('));
      expect(source, contains('ownerStatusLabel: experience?.statusLabel'));
      expect(source, contains('ownerMessage: experience?.publicMessage'));
      expect(source, contains('Pandora is preparing the working result.'));
      expect(source, isNot(contains('Current durable stage')));
      expect(source, isNot(contains('Expired source is not recreated')));
      expect(source, isNot(contains('class _BuildConversationView')));
      expect(source, isNot(contains('class _LiveBuildMessage')));
    },
  );

  test(
    'conversation uses durable review state without inferring readiness from candidate identity',
    () {
      final source = File('lib/features/simple/project_build_conversation.dart')
          .readAsStringSync();

      expect(
        source,
        contains('experience?.state == ProjectExperienceState.review'),
      );
      expect(source, contains('theatre.previewReady'));
      expect(source, isNot(contains('buildStart.projectVersionId')));
      expect(source, isNot(contains('projectVersionId != null')));
    },
  );
}

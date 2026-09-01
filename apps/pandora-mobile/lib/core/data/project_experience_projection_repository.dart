import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/project_experience_projection.dart';

class ProjectExperienceProjectionException implements Exception {
  const ProjectExperienceProjectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ProjectExperienceProjectionRepository {
  Future<ProjectExperienceProjection> load(String projectId);

  Stream<ProjectExperienceProjection> watch(String projectId);
}

class SupabaseProjectExperienceProjectionRepository
    implements ProjectExperienceProjectionRepository {
  SupabaseProjectExperienceProjectionRepository({
    required SupabaseClient client,
    required String organizationId,
  })  : _client = client,
        _organizationId = _requiredIdentifier(
          organizationId,
          name: 'organizationId',
        );

  static const _table = 'pandora_project_experience_projection';

  final SupabaseClient _client;
  final String _organizationId;

  @override
  Future<ProjectExperienceProjection> load(String projectId) async {
    final id = _requiredIdentifier(projectId, name: 'projectId');
    final row = await _client
        .from(_table)
        .select()
        .eq('organization_id', _organizationId)
        .eq('project_id', id)
        .maybeSingle();

    if (row == null) {
      throw const ProjectExperienceProjectionException(
        'Pandora cannot determine this project state right now.',
      );
    }

    return _decode(row);
  }

  @override
  Stream<ProjectExperienceProjection> watch(String projectId) {
    final id = _requiredIdentifier(projectId, name: 'projectId');
    return _client
        .from(_table)
        .stream(primaryKey: const <String>['organization_id', 'project_id'])
        .eq('project_id', id)
        .map((rows) {
          if (rows.isEmpty) {
            throw const ProjectExperienceProjectionException(
              'Pandora cannot determine this project state right now.',
            );
          }
          if (rows.length != 1) {
            throw const ProjectExperienceProjectionException(
              'Pandora returned an ambiguous project state.',
            );
          }
          final projection = _decode(rows.single);
          if (projection.organizationId != _organizationId ||
              projection.projectId != id) {
            throw const ProjectExperienceProjectionException(
              'Pandora returned a project state outside the requested scope.',
            );
          }
          return projection;
        })
        .distinct(
          (previous, next) =>
              previous.transitionSequence == next.transitionSequence &&
              previous.updatedAt == next.updatedAt,
        );
  }

  static ProjectExperienceProjection _decode(Map<String, dynamic> row) {
    try {
      return ProjectExperienceProjection.fromJson(
        Map<String, Object?>.from(row),
      );
    } on FormatException {
      throw const ProjectExperienceProjectionException(
        'Pandora returned an invalid project state.',
      );
    }
  }

  static String _requiredIdentifier(String value, {required String name}) {
    final text = value.trim();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(text)) {
      throw ArgumentError.value(value, name, 'Must be a UUID.');
    }
    return text.toLowerCase();
  }
}

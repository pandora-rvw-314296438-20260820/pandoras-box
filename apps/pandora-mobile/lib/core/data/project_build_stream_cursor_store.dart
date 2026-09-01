import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ProjectBuildStreamCursorStore {
  Future<int> read({
    required String userId,
    required String organizationId,
    required String projectId,
    required String streamId,
  });

  Future<void> write({
    required String userId,
    required String organizationId,
    required String projectId,
    required String streamId,
    required int sequence,
  });
}

class SharedPreferencesProjectBuildStreamCursorStore
    implements ProjectBuildStreamCursorStore {
  const SharedPreferencesProjectBuildStreamCursorStore();

  static const String _prefix = 'pandora.build-stream.cursor.v2';

  String _key({
    required String userId,
    required String organizationId,
    required String projectId,
    required String streamId,
  }) => '$_prefix:$userId:$organizationId:$projectId:$streamId';

  @override
  Future<int> read({
    required String userId,
    required String organizationId,
    required String projectId,
    required String streamId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getInt(
          _key(
            userId: userId,
            organizationId: organizationId,
            projectId: projectId,
            streamId: streamId,
          ),
        ) ??
        0;
    return value < 0 ? 0 : value;
  }

  @override
  Future<void> write({
    required String userId,
    required String organizationId,
    required String projectId,
    required String streamId,
    required int sequence,
  }) async {
    if (sequence < 1) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _key(
      userId: userId,
      organizationId: organizationId,
      projectId: projectId,
      streamId: streamId,
    );
    final current = prefs.getInt(key) ?? 0;
    if (sequence > current) {
      await prefs.setInt(key, sequence);
    }
  }
}

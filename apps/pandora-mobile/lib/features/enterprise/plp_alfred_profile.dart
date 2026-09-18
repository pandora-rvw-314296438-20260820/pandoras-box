class PlpAlfredProfile {
  const PlpAlfredProfile._();

  static const String personaId = 'plp_alfred_v1';
  static const String assistantLabel = 'Alfred';
  static const String tenantSlug = 'plp-boracay';
  static const String assistantRole =
      'Private Chief of Staff & Resort Intelligence';

  static Map<String, Object?> enterpriseContext({
    required String surface,
    required String route,
    required List<String> capabilities,
    required String identityScope,
    String? projectId,
    Map<String, String>? selectedObject,
  }) => <String, Object?>{
    'surface': surface,
    'route': route,
    if (projectId != null) 'projectId': projectId,
    if (selectedObject != null) 'selectedObject': selectedObject,
    'capabilities': capabilities,
    'identityScope': identityScope,
    'tenantSlug': tenantSlug,
    'personaId': personaId,
    'assistantRole': assistantRole,
  };
}

import 'package:flutter/widgets.dart';

class EnterprisePageContext {
  const EnterprisePageContext({
    required this.surface,
    required this.route,
    required this.capabilities,
    required this.identityScope,
    this.projectId,
    this.selectedObject,
    this.actorRole,
  });

  final String surface;
  final String route;
  final String? projectId;
  final Map<String, String>? selectedObject;
  final String? actorRole;
  final List<String> capabilities;
  final String identityScope;

  Map<String, Object?> toWire() => <String, Object?>{
        'surface': surface,
        'route': route,
        if (projectId != null) 'projectId': projectId,
        if (selectedObject != null) 'selectedObject': selectedObject,
        if (actorRole != null) 'actorRole': actorRole,
        'capabilities': capabilities,
        'identityScope': identityScope,
      };
  EnterprisePageContext copyWith({
    String? projectId,
    Map<String, String>? selectedObject,
    String? actorRole,
  }) =>
      EnterprisePageContext(
        surface: surface,
        route: route,
        projectId: projectId ?? this.projectId,
        selectedObject: selectedObject ?? this.selectedObject,
        actorRole: actorRole ?? this.actorRole,
        capabilities: capabilities,
        identityScope: identityScope,
      );
}

class EnterprisePageContextScope extends InheritedWidget {
  const EnterprisePageContextScope({
    super.key,
    required this.pageContext,
    required super.child,
  });

  final EnterprisePageContext pageContext;

  static EnterprisePageContext of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EnterprisePageContextScope>();
    assert(scope != null, 'EnterprisePageContextScope is missing.');
    return scope!.pageContext;
  }

  static EnterprisePageContext? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<EnterprisePageContextScope>()
      ?.pageContext;

  @override
  bool updateShouldNotify(EnterprisePageContextScope oldWidget) =>
      pageContext.surface != oldWidget.pageContext.surface ||
      pageContext.route != oldWidget.pageContext.route ||
      pageContext.projectId != oldWidget.pageContext.projectId ||
      pageContext.actorRole != oldWidget.pageContext.actorRole ||
      pageContext.identityScope != oldWidget.pageContext.identityScope ||
      pageContext.selectedObject != oldWidget.pageContext.selectedObject ||
      pageContext.capabilities != oldWidget.pageContext.capabilities;
}

import 'package:flutter/material.dart';

import '../enterprise/enterprise_app_users_screen.dart';
import '../enterprise/enterprise_live_screen.dart';
import '../enterprise/enterprise_vision_screen.dart';
import 'plp_overview_screen.dart';

class EnterpriseSectionScreen extends StatelessWidget {
  const EnterpriseSectionScreen({
    super.key,
    required this.surface,
    required this.title,
    required this.description,
    required this.icon,
    this.items = const <String>[],
    this.onSelectionChanged,
  });

  final String surface;
  final String title;
  final String description;
  final IconData icon;
  final List<String> items;
  final ValueChanged<Map<String, String>?>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    if (surface == 'enterprise_overview') {
      return PlpOverviewScreen(description: description);
    }
    if (surface == 'enterprise_app_users') {
      return EnterpriseAppUsersScreen(
        onSelectionChanged: onSelectionChanged,
      );
    }
    if (surface == 'enterprise_vision') {
      return const EnterpriseVisionScreen();
    }
    return EnterpriseLiveScreen(
      surface: surface,
      title: title,
      description: description,
      icon: icon,
      onSelectionChanged: onSelectionChanged,
    );
  }
}

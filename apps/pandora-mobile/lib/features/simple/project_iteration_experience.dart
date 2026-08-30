import 'package:flutter/material.dart';

import '../../core/models/project_journey_models.dart';
import 'project_conversation_screen.dart';

class ProjectIterationExperienceScreen extends StatelessWidget {
  const ProjectIterationExperienceScreen({
    super.key,
    required this.project,
  });

  final CustomerProject project;

  @override
  Widget build(BuildContext context) => ProjectConversationScreen(
        project: project,
        mode: ProjectConversationMode.iteration,
        onBuildConfirmed: (conversationContext) {
          Navigator.of(conversationContext).pop(true);
        },
      );
}

import 'package:flutter/material.dart';

class OperationsRoomRole {
  const OperationsRoomRole({
    required this.id,
    required this.name,
    required this.title,
    required this.icon,
    this.core = false,
  });

  final String id;
  final String name;
  final String title;
  final IconData icon;
  final bool core;
}

const operationsRoomRoles = <OperationsRoomRole>[
  OperationsRoomRole(
    id: 'athena',
    name: 'ATHENA',
    title: 'Chief of Staff',
    icon: Icons.account_balance_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'apollo',
    name: 'APOLLO',
    title: 'Product & UX',
    icon: Icons.auto_awesome_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'hermes',
    name: 'HERMES',
    title: 'Source & Project',
    icon: Icons.account_tree_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'hephaestus',
    name: 'HEPHAESTUS',
    title: 'Engineering & Infrastructure',
    icon: Icons.handyman_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'artemis',
    name: 'ARTEMIS',
    title: 'QA, Verification & Release',
    icon: Icons.verified_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'themis',
    name: 'THEMIS',
    title: 'Security & Governance',
    icon: Icons.shield_rounded,
    core: true,
  ),
  OperationsRoomRole(
    id: 'mnemosyne',
    name: 'MNEMOSYNE',
    title: 'Memory & Intelligence',
    icon: Icons.memory_rounded,
  ),
  OperationsRoomRole(
    id: 'hestia',
    name: 'HESTIA',
    title: 'Reliability & Continuity',
    icon: Icons.home_work_rounded,
  ),
  OperationsRoomRole(
    id: 'iris',
    name: 'IRIS',
    title: 'Communications & Integrations',
    icon: Icons.send_rounded,
  ),
  OperationsRoomRole(
    id: 'asclepius',
    name: 'ASCLEPIUS',
    title: 'Diagnostics & Recovery',
    icon: Icons.health_and_safety_rounded,
  ),
  OperationsRoomRole(
    id: 'nike',
    name: 'NIKE',
    title: 'Analytics & Outcomes',
    icon: Icons.query_stats_rounded,
  ),
  OperationsRoomRole(
    id: 'hecate',
    name: 'HECATE',
    title: 'Models, Routing & Automation',
    icon: Icons.alt_route_rounded,
  ),
  OperationsRoomRole(
    id: 'prometheus',
    name: 'PROMETHEUS',
    title: 'Research & Innovation',
    icon: Icons.science_rounded,
  ),
  OperationsRoomRole(
    id: 'demeter',
    name: 'DEMETER',
    title: 'Data & Knowledge',
    icon: Icons.storage_rounded,
  ),
];

const operationsRoomCoreRoleNames = <String>{
  'ATHENA',
  'APOLLO',
  'HERMES',
  'HEPHAESTUS',
  'ARTEMIS',
  'THEMIS',
};

OperationsRoomRole operationsRoomRole(String name) {
  final upper = name.toUpperCase();
  for (final role in operationsRoomRoles) {
    if (role.name == upper) return role;
  }
  return operationsRoomRoles.first;
}

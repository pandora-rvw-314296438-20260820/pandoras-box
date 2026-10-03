
import 'package:flutter/material.dart';

import 'plp_enterprise_shell.dart';

/// Pandora Admin's locked PLP Enterprise visual baseline.
///
/// This is intentionally a separate Admin entry point that renders the current
/// PLP Enterprise shell unchanged. PLP itself is not modified. The wrapper does
/// not duplicate Supabase, realtime, navigation, or chat state and adds no
/// background work while Admin is not mounted.
class PandoraAdminShell extends StatelessWidget {
  const PandoraAdminShell({
    super.key,
    this.bootstrapOverride,
    this.embeddedRouteSlug,
    this.organizationId,
    this.propertyId,
  });

  final Map<String, Object?>? bootstrapOverride;
  final String? embeddedRouteSlug;
  final String? organizationId;
  final String? propertyId;

  @override
  Widget build(BuildContext context) => PlpEnterpriseShell(
        bootstrapOverride: bootstrapOverride,
        embeddedRouteSlug: embeddedRouteSlug,
        organizationId: organizationId,
        propertyId: propertyId,
      );
}

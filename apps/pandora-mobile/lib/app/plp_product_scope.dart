import '../core/data/pandora_core_api.dart';

/// How the PLP Enterprise product should open.
///
/// Customer workspace is the existing resort shell. Owner mode is only chosen
/// when the signed-in Core snapshot names an operator role. Missing data is
/// not treated as access.
enum PlpProductScope { customerWorkspace, pandoraOwner }

const plpOperatorRoles = <String>{'owner', 'admin', 'operator'};

PlpProductScope plpProductScopeFromSnapshot(PandoraCoreRecord? snapshot) {
  if (snapshot == null || snapshot.isEmpty) {
    return PlpProductScope.customerWorkspace;
  }
  final operator = coreRecord(snapshot['operator']);
  final role = coreText(operator['role'], '').toLowerCase();
  if (!plpOperatorRoles.contains(role)) {
    return PlpProductScope.customerWorkspace;
  }
  return PlpProductScope.pandoraOwner;
}

/// Failures that mean this session is not a Pandora operator. The resort
/// workspace stays available. Transport failures are not an access decision.
bool plpCoreFailureIsCustomerScope(PandoraCoreFailure failure) =>
    const {'ACCESS_DENIED', 'SIGN_IN_REQUIRED', 'SCOPE_MISMATCH'}
        .contains(failure.code);

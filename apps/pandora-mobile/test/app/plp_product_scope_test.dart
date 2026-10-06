import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_product_scope.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';

void main() {
  test('missing snapshot stays in the customer workspace', () {
    expect(plpProductScopeFromSnapshot(null),
        PlpProductScope.customerWorkspace);
    expect(plpProductScopeFromSnapshot(<String, dynamic>{}),
        PlpProductScope.customerWorkspace);
    expect(
      plpProductScopeFromSnapshot(<String, dynamic>{
        'operator': <String, dynamic>{},
      }),
      PlpProductScope.customerWorkspace,
    );
  });

  test('viewer and member roles do not open Pandora owner mode', () {
    for (final role in ['viewer', 'member', 'guest', '']) {
      expect(
        plpProductScopeFromSnapshot(<String, dynamic>{
          'operator': <String, dynamic>{'role': role},
        }),
        PlpProductScope.customerWorkspace,
        reason: role,
      );
    }
  });

  test('owner, admin, and operator snapshots open Pandora owner mode', () {
    for (final role in ['owner', 'admin', 'operator', 'Owner']) {
      expect(
        plpProductScopeFromSnapshot(<String, dynamic>{
          'operator': <String, dynamic>{'role': role},
        }),
        PlpProductScope.pandoraOwner,
        reason: role,
      );
    }
  });

  test('access failures stay customer scope and transport failures do not', () {
    expect(
      plpCoreFailureIsCustomerScope(
        const PandoraCoreFailure('ACCESS_DENIED', 'no'),
      ),
      isTrue,
    );
    expect(
      plpCoreFailureIsCustomerScope(
        const PandoraCoreFailure('UNAVAILABLE', 'offline'),
      ),
      isFalse,
    );
  });
}

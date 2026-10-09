import 'dart:async';

import '../../core/analytics/owner_analytics.dart';
import '../../core/data/plp_paypal_billing_api.dart' show plpCheckoutOrigins;

export '../../core/data/plp_paypal_billing_api.dart' show plpCheckoutOrigins;

const _allowedPlans = <String>{
  'launch',
  'professional',
};

const _allowedReasons = <String>{
  'paypal_cancel',
  'pending_timeout',
  'open_failed',
  'paypal_unavailable',
  'identity_required',
  'already_active',
  'server_error',
  'network',
};

typedef PlpCheckoutEventSink = void Function(
  OwnerAnalyticsEvent event, {
  String? origin,
  String? plan,
  String? reason,
  int? attempt,
  Duration? sinceView,
});

/// Default PLP checkout analytics sink.
///
/// Privacy guarantee:
/// Only values from fixed allowlists are sent.
/// - origin must be in [plpCheckoutOrigins] (otherwise dropped).
/// - plan must be in {'launch', 'professional'} (otherwise dropped).
/// - reason must be in {'paypal_cancel', 'pending_timeout', 'open_failed',
///   'paypal_unavailable', 'identity_required', 'already_active',
///   'server_error', 'network'} (otherwise defaulted to 'server_error').
///
/// Never send organization id, user id, email, subscription id, URLs, or amounts.
void plpCheckoutAnalytics(
  OwnerAnalyticsEvent event, {
  String? origin,
  String? plan,
  String? reason,
  int? attempt,
  Duration? sinceView,
}) {
  final safeOrigin =
      origin != null && plpCheckoutOrigins.contains(origin) ? origin : null;
  final safePlan =
      plan != null && _allowedPlans.contains(plan) ? plan : null;
  final safeReason = reason != null
      ? (_allowedReasons.contains(reason) ? reason : 'server_error')
      : null;

  unawaited(
    OwnerAnalytics.shared.capture(
      event,
      capability: safeOrigin,
      status: safePlan,
      errorCode: safeReason,
      attempt: attempt,
      duration: sinceView,
    ),
  );
}

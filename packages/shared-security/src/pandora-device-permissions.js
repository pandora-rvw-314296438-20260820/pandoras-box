"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PERMISSION_AUTHORITY_MODES = exports.PERMISSION_GATE_DECISIONS = exports.PERMISSION_GATE_SCHEMA_VERSION = void 0;
exports.evaluateDevicePermissionGate = evaluateDevicePermissionGate;
exports.permissionDecisionNeedsYou = permissionDecisionNeedsYou;

exports.PERMISSION_GATE_SCHEMA_VERSION = "pandora-device-permission-gate-v1";
exports.PERMISSION_AUTHORITY_MODES = Object.freeze([
  "public_app",
  "runtime_permission",
  "android_role",
  "device_owner",
  "development_only",
  "policy_denied"
]);
exports.PERMISSION_GATE_DECISIONS = Object.freeze([
  "allow",
  "needs_user_action",
  "deny"
]);

function normalize(value) {
  return String(value ?? "").trim().toLowerCase();
}

function decision(input, decisionValue, reasonCode, options = {}) {
  const capabilityId = String(input.capabilityId ?? "").trim();
  return {
    schemaVersion: exports.PERMISSION_GATE_SCHEMA_VERSION,
    capabilityId,
    authority: normalize(input.authority),
    decision: decisionValue,
    reasonCode,
    userActionRequired: decisionValue === "needs_user_action",
    userActionSurface: options.userActionSurface ?? null,
    permissionPromptAllowed: options.permissionPromptAllowed === true,
    revocationControlSurface: options.revocationControlSurface ?? null,
    mustRecheckBeforeUse: true,
    cachedGrantAccepted: false,
    automaticRetryAllowed: false,
    explanation: options.explanation ?? "Pandora permission policy denied this capability."
  };
}

function evaluateDevicePermissionGate(input = {}) {
  const capabilityId = String(input.capabilityId ?? "").trim();
  const authority = normalize(input.authority);
  if (!capabilityId) {
    return decision(input, "deny", "capability_id_required", {
      explanation: "Pandora cannot evaluate a permission boundary without a capability identifier."
    });
  }
  if (!exports.PERMISSION_AUTHORITY_MODES.includes(authority)) {
    return decision(input, "deny", "unknown_permission_authority", {
      explanation: "Pandora does not recognize the authority required by this capability."
    });
  }
  if (authority === "policy_denied") {
    return decision(input, "deny", "capability_policy_denied", {
      explanation: "Pandora policy permanently denies this capability."
    });
  }
  if (authority === "development_only") {
    return decision(input, "deny", "development_authority_not_runtime", {
      explanation: "Development-only authority cannot be used during normal Pandora operation."
    });
  }
  if (input.trustedRuntimeState !== true) {
    return decision(input, "deny", "permission_state_untrusted", {
      explanation: "Pandora must verify current Android authority from trusted runtime state before using this capability."
    });
  }
  if (input.policyAllowsCapability !== true) {
    return decision(input, "deny", "capability_not_authorized", {
      explanation: "Current Pandora policy does not authorize this capability."
    });
  }
  if (input.implementationAvailable !== true) {
    return decision(input, "deny", "capability_not_implemented", {
      explanation: "This capability is not available on the current Pandora Device implementation."
    });
  }

  if (authority === "public_app") {
    return decision(input, "allow", "public_app_authority_satisfied", {
      explanation: "This capability uses public app authority and needs no additional Android permission."
    });
  }

  if (authority === "runtime_permission") {
    if (input.permissionStateFresh !== true) {
      return decision(input, "deny", "runtime_permission_state_not_fresh", {
        revocationControlSurface: "app_details",
        explanation: "Pandora must re-read the current Android runtime permission before using this capability."
      });
    }
    if (input.manifestDeclared !== true) {
      return decision(input, "deny", "runtime_permission_not_declared", {
        revocationControlSurface: "app_details",
        explanation: "Pandora does not declare the Android permission required for this capability and will not broaden permissions automatically."
      });
    }
    if (input.permissionGranted !== true) {
      const promptAllowed =
        input.userInitiatedPermissionRequest === true &&
        input.permissionPromptAvailable === true;
      return decision(input, "needs_user_action", "runtime_permission_required", {
        userActionSurface: promptAllowed ? "runtime_permission_dialog" : "app_details",
        permissionPromptAllowed: promptAllowed,
        revocationControlSurface: "app_details",
        explanation: "Android permission is required for this capability. Denying or revoking it keeps the capability unavailable until you explicitly grant it."
      });
    }
    return decision(input, "allow", "runtime_permission_granted", {
      revocationControlSurface: "app_details",
      explanation: "Android currently reports the required runtime permission as granted."
    });
  }

  if (authority === "android_role") {
    if (input.roleStateFresh !== true) {
      return decision(input, "deny", "android_role_state_not_fresh", {
        explanation: "Pandora must re-read the current Android role state before using this capability."
      });
    }
    if (input.roleAvailable !== true) {
      return decision(input, "deny", "android_role_unavailable", {
        explanation: "Android reports that the required role is unavailable on this device."
      });
    }
    if (input.roleHeld !== true) {
      return decision(input, "needs_user_action", "android_role_required", {
        userActionSurface: "android_role_settings",
        explanation: "This capability requires an Android role that only you can grant or change."
      });
    }
    return decision(input, "allow", "android_role_held", {
      explanation: "Android currently reports that Pandora holds the required role."
    });
  }

  if (input.deviceOwnerStateFresh !== true) {
    return decision(input, "deny", "device_owner_state_not_fresh", {
      explanation: "Pandora must re-read Device Owner state before using this capability."
    });
  }
  if (input.deviceOwnerProvisioned !== true) {
    return decision(input, "deny", "device_owner_not_provisioned", {
      explanation: "This capability requires Device Owner authority that is not provisioned on this installation."
    });
  }
  return decision(input, "allow", "device_owner_authority_satisfied", {
    explanation: "Current Android state confirms the required Device Owner authority."
  });
}

function permissionDecisionNeedsYou(result) {
  if (!result || result.decision !== "needs_user_action") return null;
  return {
    state: "needs_you",
    capabilityId: result.capabilityId,
    reasonCode: result.reasonCode,
    explanation: result.explanation,
    userActionSurface: result.userActionSurface,
    permissionPromptAllowed: result.permissionPromptAllowed === true,
    revocationControlSurface: result.revocationControlSurface ?? null,
    retryAfterUserAction: true,
    automaticRetryAllowed: false
  };
}

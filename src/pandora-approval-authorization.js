"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.PANDORA_APPROVER_ROLES = void 0;
exports.canApprovePandoraPlan = canApprovePandoraPlan;
exports.pandoraApproverAttribution = pandoraApproverAttribution;

exports.PANDORA_APPROVER_ROLES = Object.freeze(new Set(["owner", "admin"]));

function canApprovePandoraPlan(actor) {
    return Boolean(actor && exports.PANDORA_APPROVER_ROLES.has(actor.membership?.role));
}

function pandoraApproverAttribution(actor) {
    if (!canApprovePandoraPlan(actor) || !actor.identity?.userId) {
        throw new Error("Plan approval requires a Pandora owner or admin session");
    }
    return `supabase:${actor.identity.userId}`;
}

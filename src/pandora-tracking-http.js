"use strict";

const crypto = require("node:crypto");
const express = require("express");

const CLICK_ID_RE = /^pdc_[0-9a-f]{32}$/;
const API_KEY_RE = /^ptk_[0-9a-f]{64}$/i;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EVENT_NAME_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const PROVIDER_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ALLOWED_QUERY_KEYS = new Set([
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "fbclid",
  "gclid",
  "ttclid",
  "msclkid",
  "sub1",
  "sub2",
  "sub3",
  "sub4",
  "sub5",
]);
const PLATFORM_CLICK_KEYS = ["fbclid", "gclid", "ttclid", "msclkid"];
const CONVERSION_TYPES = new Set(["lead", "qualified_lead", "booking", "sale", "refund"]);

class TrackingError extends Error {
  constructor(status, code, details = null) {
    super(code);
    this.name = "TrackingError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function createClickId() {
  return "pdc_" + crypto.randomBytes(16).toString("hex");
}

function stringValue(value, maxLength = 512) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, maxLength) : null;
}

function sanitizeMetadata(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const output = {};
  for (const [rawKey, rawValue] of Object.entries(value).slice(0, 40)) {
    const key = String(rawKey).slice(0, 80);
    if (typeof rawValue === "string") output[key] = rawValue.slice(0, 1000);
    else if (typeof rawValue === "number" && Number.isFinite(rawValue)) output[key] = rawValue;
    else if (typeof rawValue === "boolean" || rawValue === null) output[key] = rawValue;
  }
  return output;
}

function sanitizeIncomingQuery(query) {
  const output = {};
  if (!query || typeof query !== "object") return output;
  for (const [key, rawValue] of Object.entries(query)) {
    if (!ALLOWED_QUERY_KEYS.has(key)) continue;
    const candidate = Array.isArray(rawValue) ? rawValue[0] : rawValue;
    if (candidate === undefined || candidate === null) continue;
    output[key] = String(candidate).slice(0, 1000);
  }
  return output;
}

function buildDestinationUrl(destinationUrl, queryParams, campaign, clickId) {
  const target = new URL(destinationUrl);
  if (target.protocol !== "https:") throw new TrackingError(500, "campaign_destination_invalid");
  for (const [key, value] of Object.entries(queryParams || {})) {
    if (!target.searchParams.has(key)) target.searchParams.set(key, value);
  }
  const defaults = {
    utm_source: campaign.source,
    utm_medium: campaign.medium,
    utm_campaign: campaign.campaign,
    utm_content: campaign.content,
    utm_term: campaign.term,
  };
  for (const [key, value] of Object.entries(defaults)) {
    if (value && !target.searchParams.has(key)) target.searchParams.set(key, value);
  }
  target.searchParams.set("pcid", clickId);
  return target.toString();
}

function parseBearerKey(headerValue) {
  const match = String(headerValue || "").match(/^Bearer\s+(ptk_[0-9a-f]{64})$/i);
  return match ? match[1] : null;
}

function parseNumber(value, field, { integer = false } = {}) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || (integer && !Number.isInteger(parsed))) {
    throw new TrackingError(400, field + "_invalid");
  }
  return parsed;
}

function parseCurrency(value, required = false) {
  if (value === undefined || value === null || value === "") {
    if (required) throw new TrackingError(400, "currency_required");
    return null;
  }
  const currency = String(value).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new TrackingError(400, "currency_invalid");
  return currency;
}

function parseOccurredAt(value) {
  if (!value) return new Date().toISOString();
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) throw new TrackingError(400, "occurred_at_invalid");
  return date.toISOString();
}

function queryString(parameters) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(parameters)) {
    if (value !== undefined && value !== null) search.set(key, String(value));
  }
  return search.toString();
}

function createRestClient(environment, fetchFn) {
  const baseUrl = String(environment.SUPABASE_URL || environment.NEXT_PUBLIC_SUPABASE_URL || "").replace(/\/+$/, "");
  const serviceKey = String(environment.SUPABASE_SERVICE_ROLE_KEY || environment.SUPABASE_SECRET_KEY || "");
  if (!baseUrl || !serviceKey) throw new TrackingError(503, "tracking_backend_unconfigured");

  async function request(resource, options = {}) {
    const response = await fetchFn(baseUrl + "/rest/v1/" + resource, {
      method: options.method || "GET",
      headers: {
        apikey: serviceKey,
        authorization: "Bearer " + serviceKey,
        accept: "application/json",
        ...(options.body === undefined ? {} : { "content-type": "application/json" }),
        ...(options.prefer ? { prefer: options.prefer } : {}),
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    const raw = await response.text();
    let payload = null;
    if (raw) {
      try {
        payload = JSON.parse(raw);
      } catch {
        payload = null;
      }
    }
    if (!response.ok) {
      throw new TrackingError(response.status, "tracking_storage_error", {
        providerCode: payload && typeof payload.code === "string" ? payload.code : null,
      });
    }
    return payload;
  }

  return { request, serviceKey };
}

function sendJson(res, status, body, cors = false) {
  res.status(status);
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("X-Content-Type-Options", "nosniff");
  if (cors) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "content-type");
    res.set("Access-Control-Allow-Methods", "POST,OPTIONS");
  }
  return res.json(body);
}

function trackingFailure(res, error, cors = false) {
  const status = error instanceof TrackingError ? error.status : 500;
  const code = error instanceof TrackingError ? error.code : "tracking_request_failed";
  return sendJson(res, status, { ok: false, error: code }, cors);
}

function firstRow(payload) {
  return Array.isArray(payload) && payload.length ? payload[0] : null;
}

function createPandoraTrackingRouter(options = {}) {
  const router = express.Router();
  const environment = options.environment || process.env;
  const fetchFn = options.fetchFn || globalThis.fetch;
  if (typeof fetchFn !== "function") throw new Error("fetch is required");
  const rest = createRestClient(environment, fetchFn);
  const hashPepper = String(environment.PANDORA_TRACKING_HASH_PEPPER || rest.serviceKey);

  async function authenticate(req, requiredScope) {
    const rawKey = parseBearerKey(req.get("authorization"));
    if (!rawKey) throw new TrackingError(401, "unauthorized");
    const keyHash = sha256(rawKey);
    const resource = "pandora_tracking_api_keys?" + queryString({
      select: "id,tenant_id,scopes,status,expires_at",
      key_hash: "eq." + keyHash,
      status: "eq.active",
      limit: 1,
    });
    const record = firstRow(await rest.request(resource));
    if (!record) throw new TrackingError(401, "unauthorized");
    if (record.expires_at && new Date(record.expires_at).getTime() <= Date.now()) {
      throw new TrackingError(401, "unauthorized");
    }
    const scopes = Array.isArray(record.scopes) ? record.scopes : [];
    if (!scopes.includes("*") && !scopes.includes(requiredScope)) {
      throw new TrackingError(403, "scope_denied");
    }
    await rest.request("pandora_tracking_api_keys?" + queryString({ id: "eq." + record.id }), {
      method: "PATCH",
      body: { last_used_at: new Date().toISOString() },
      prefer: "return=minimal",
    });
    return { tenantId: record.tenant_id };
  }

  async function campaignForTenant(tenantId, campaignId) {
    if (!campaignId) return null;
    if (!UUID_RE.test(campaignId)) throw new TrackingError(400, "campaign_id_invalid");
    const resource = "pandora_tracking_campaigns?" + queryString({
      select: "id",
      tenant_id: "eq." + tenantId,
      id: "eq." + campaignId,
      limit: 1,
    });
    const record = firstRow(await rest.request(resource));
    if (!record) throw new TrackingError(404, "campaign_not_found");
    return record.id;
  }

  router.get("/api/tracking/health", async (_req, res) => {
    try {
      const payload = await rest.request("pandora_tracking_releases?" + queryString({
        select: "version,source_base_sha,provider_state,source_state,deployed_at",
        order: "deployed_at.desc",
        limit: 1,
      }));
      return sendJson(res, 200, {
        ok: true,
        service: "pandora-tracking",
        release: firstRow(payload),
      });
    } catch (error) {
      return trackingFailure(res, error);
    }
  });

  router.get("/t/:slug", async (req, res) => {
    try {
      const slug = String(req.params.slug || "");
      if (!/^[a-z0-9][a-z0-9-]{2,95}$/.test(slug)) {
        throw new TrackingError(404, "campaign_not_found");
      }
      const campaignResource = "pandora_tracking_campaigns?" + queryString({
        select: "id,tenant_id,destination_url,source,medium,campaign,content,term,status",
        slug: "eq." + slug,
        status: "eq.active",
        limit: 1,
      });
      const campaign = firstRow(await rest.request(campaignResource));
      if (!campaign) throw new TrackingError(404, "campaign_not_found");

      const tenant = firstRow(await rest.request("pandora_tracking_tenants?" + queryString({
        select: "status",
        id: "eq." + campaign.tenant_id,
        limit: 1,
      })));
      if (!tenant || tenant.status !== "active") throw new TrackingError(404, "campaign_not_found");

      const clickId = createClickId();
      const incoming = sanitizeIncomingQuery(req.query);
      const platformClickIds = {};
      for (const key of PLATFORM_CLICK_KEYS) {
        if (incoming[key]) platformClickIds[key] = incoming[key];
      }
      const ip = String(req.ip || "");
      const userAgent = stringValue(req.get("user-agent"), 1000);
      const referrer = stringValue(req.get("referer"), 1500);

      await rest.request("pandora_tracking_clicks", {
        method: "POST",
        body: {
          tenant_id: campaign.tenant_id,
          campaign_id: campaign.id,
          click_id: clickId,
          landing_url: campaign.destination_url,
          referrer,
          user_agent: userAgent,
          ip_hash: ip ? sha256(hashPepper + "|ip|" + ip) : null,
          visitor_hash: sha256(hashPepper + "|visitor|" + (ip || "-") + "|" + (userAgent || "-")),
          platform_click_ids: platformClickIds,
          query_params: incoming,
          metadata: { collector: "vercel" },
        },
        prefer: "return=minimal",
      });

      const destination = buildDestinationUrl(campaign.destination_url, incoming, campaign, clickId);
      res.set("Cache-Control", "no-store, max-age=0");
      res.set("Referrer-Policy", "strict-origin-when-cross-origin");
      return res.redirect(302, destination);
    } catch (error) {
      return trackingFailure(res, error);
    }
  });

  router.options("/api/tracking/event", (_req, res) => {
    res.status(204);
    res.set("Cache-Control", "no-store");
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "content-type");
    res.set("Access-Control-Allow-Methods", "POST,OPTIONS");
    return res.end();
  });

  router.use("/api/tracking", express.json({ limit: "64kb", type: ["application/json", "application/*+json"] }));

  router.post("/api/tracking/event", async (req, res) => {
    try {
      const clickId = stringValue(req.body?.click_id, 40);
      const eventName = stringValue(req.body?.event_name, 64);
      const eventType = stringValue(req.body?.event_type, 32) || "event";
      if (!clickId || !CLICK_ID_RE.test(clickId)) throw new TrackingError(400, "click_id_invalid");
      if (!eventName || !EVENT_NAME_RE.test(eventName)) throw new TrackingError(400, "event_name_invalid");
      if (eventType !== "event") throw new TrackingError(403, "conversion_auth_required");

      const click = firstRow(await rest.request("pandora_tracking_clicks?" + queryString({
        select: "tenant_id,campaign_id",
        click_id: "eq." + clickId,
        limit: 1,
      })));
      if (!click) throw new TrackingError(404, "click_not_found");

      await rest.request("pandora_tracking_events", {
        method: "POST",
        body: {
          tenant_id: click.tenant_id,
          campaign_id: click.campaign_id,
          click_id: clickId,
          event_type: "event",
          event_name: eventName,
          source: "browser",
          metadata: sanitizeMetadata(req.body?.metadata),
        },
        prefer: "return=minimal",
      });
      return sendJson(res, 202, { ok: true }, true);
    } catch (error) {
      return trackingFailure(res, error, true);
    }
  });

  router.post("/api/tracking/conversion", async (req, res) => {
    try {
      const principal = await authenticate(req, "conversion:write");
      const eventType = stringValue(req.body?.event_type, 32);
      const eventName = stringValue(req.body?.event_name, 64);
      const externalEventId = stringValue(req.body?.external_event_id, 200);
      const clickId = stringValue(req.body?.click_id, 40);
      if (!eventType || !CONVERSION_TYPES.has(eventType)) throw new TrackingError(400, "event_type_invalid");
      if (!eventName || !EVENT_NAME_RE.test(eventName)) throw new TrackingError(400, "event_name_invalid");
      if (!externalEventId) throw new TrackingError(400, "external_event_id_required");
      if (clickId && !CLICK_ID_RE.test(clickId)) throw new TrackingError(400, "click_id_invalid");

      let campaignId = await campaignForTenant(principal.tenantId, stringValue(req.body?.campaign_id, 40));
      if (clickId) {
        const click = firstRow(await rest.request("pandora_tracking_clicks?" + queryString({
          select: "campaign_id",
          tenant_id: "eq." + principal.tenantId,
          click_id: "eq." + clickId,
          limit: 1,
        })));
        if (!click) throw new TrackingError(404, "click_not_found");
        campaignId = click.campaign_id;
      }

      const value = parseNumber(req.body?.value, "value");
      const currency = parseCurrency(req.body?.currency, value !== null);
      try {
        const inserted = await rest.request("pandora_tracking_events", {
          method: "POST",
          body: {
            tenant_id: principal.tenantId,
            campaign_id: campaignId,
            click_id: clickId,
            event_type: eventType,
            event_name: eventName,
            source: "server",
            external_event_id: externalEventId,
            value,
            currency,
            occurred_at: parseOccurredAt(req.body?.occurred_at),
            metadata: sanitizeMetadata(req.body?.metadata),
          },
          prefer: "return=representation",
        });
        return sendJson(res, 201, { ok: true, duplicate: false, id: firstRow(inserted)?.id || null });
      } catch (error) {
        const duplicate = error instanceof TrackingError
          && error.status === 409
          && error.details?.providerCode === "23505";
        if (!duplicate) throw error;
        const existing = firstRow(await rest.request("pandora_tracking_events?" + queryString({
          select: "id",
          tenant_id: "eq." + principal.tenantId,
          event_name: "eq." + eventName,
          external_event_id: "eq." + externalEventId,
          limit: 1,
        })));
        return sendJson(res, 200, { ok: true, duplicate: true, id: existing?.id || null });
      }
    } catch (error) {
      return trackingFailure(res, error);
    }
  });

  router.post("/api/tracking/cost", async (req, res) => {
    try {
      const principal = await authenticate(req, "cost:write");
      const provider = stringValue(req.body?.provider, 64);
      const externalRecordId = stringValue(req.body?.external_record_id, 200);
      const bucketDate = stringValue(req.body?.bucket_date, 10);
      if (!provider || !PROVIDER_RE.test(provider)) throw new TrackingError(400, "provider_invalid");
      if (!externalRecordId) throw new TrackingError(400, "external_record_id_required");
      if (!bucketDate || !DATE_RE.test(bucketDate)) throw new TrackingError(400, "bucket_date_invalid");
      const campaignId = await campaignForTenant(principal.tenantId, stringValue(req.body?.campaign_id, 40));
      const currency = parseCurrency(req.body?.currency, true);

      await rest.request("pandora_tracking_costs?on_conflict=tenant_id%2Cprovider%2Cexternal_record_id", {
        method: "POST",
        body: {
          tenant_id: principal.tenantId,
          campaign_id: campaignId,
          provider,
          external_record_id: externalRecordId,
          bucket_date: bucketDate,
          spend: parseNumber(req.body?.spend, "spend") ?? 0,
          impressions: parseNumber(req.body?.impressions, "impressions", { integer: true }) ?? 0,
          provider_clicks: parseNumber(req.body?.provider_clicks, "provider_clicks", { integer: true }) ?? 0,
          currency,
          metadata: sanitizeMetadata(req.body?.metadata),
        },
        prefer: "resolution=merge-duplicates,return=minimal",
      });
      return sendJson(res, 200, { ok: true });
    } catch (error) {
      return trackingFailure(res, error);
    }
  });

  router.get("/api/tracking/report", async (req, res) => {
    try {
      const principal = await authenticate(req, "report:read");
      const from = stringValue(req.query?.from, 10);
      const to = stringValue(req.query?.to, 10);
      const campaignId = stringValue(req.query?.campaign_id, 40);
      if (from && !DATE_RE.test(from)) throw new TrackingError(400, "from_invalid");
      if (to && !DATE_RE.test(to)) throw new TrackingError(400, "to_invalid");
      if (campaignId && !UUID_RE.test(campaignId)) throw new TrackingError(400, "campaign_id_invalid");

      const resource = "pandora_tracking_campaign_daily_v1?" + queryString({
        select: "*",
        tenant_id: "eq." + principal.tenantId,
        day: from ? "gte." + from : undefined,
        campaign_id: campaignId ? "eq." + campaignId : undefined,
        order: "day.desc",
        limit: 500,
      });
      let rows = await rest.request(resource);
      if (to) rows = (Array.isArray(rows) ? rows : []).filter((row) => String(row.day) <= to);
      return sendJson(res, 200, { ok: true, rows: Array.isArray(rows) ? rows : [] });
    } catch (error) {
      return trackingFailure(res, error);
    }
  });

  router.use("/api/tracking", (error, _req, res, next) => {
    if (!error) return next();
    if (error.type === "entity.too.large") return trackingFailure(res, new TrackingError(413, "body_too_large"));
    if (error instanceof SyntaxError) return trackingFailure(res, new TrackingError(400, "json_invalid"));
    return trackingFailure(res, error);
  });

  return router;
}

module.exports = {
  createPandoraTrackingRouter,
  _trackingInternals: {
    buildDestinationUrl,
    createClickId,
    parseBearerKey,
    sanitizeIncomingQuery,
    sanitizeMetadata,
    sha256,
  },
};

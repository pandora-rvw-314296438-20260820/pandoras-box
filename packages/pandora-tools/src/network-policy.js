"use strict";

const net = require("node:net");
const { domainToASCII } = require("node:url");
const { PandoraToolError } = require("./errors");

const NETWORK_CATEGORIES = Object.freeze([
  "provider_api",
  "dependency_registry",
  "customer_specified_endpoint",
  "unknown_external_endpoint",
]);

function normalizeHost(hostname) {
  const ascii = domainToASCII(String(hostname || "").replace(/\.$/, "").toLowerCase());
  if (!ascii) throw new PandoraToolError("policy_denied", "NETWORK_HOST_INVALID", "Network target host is invalid");
  return ascii;
}

function isBlockedIpv4(address) {
  const p = address.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a,b] = p;
  return a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
}

function isBlockedIpv6(address) {
  const value = address.toLowerCase().split("%")[0];
  if (value === "::" || value === "::1") return true;
  if (value.startsWith("fe8") || value.startsWith("fe9") || value.startsWith("fea") || value.startsWith("feb")) return true;
  if (value.startsWith("fc") || value.startsWith("fd")) return true;
  if (value.startsWith("ff")) return true;
  if (value.startsWith("::ffff:")) {
    const mapped = value.slice(7);
    if (net.isIP(mapped) === 4) return isBlockedIpv4(mapped);
  }
  return false;
}

function assertResolvedAddressAllowed(address) {
  const version = net.isIP(address);
  if (!version) throw new PandoraToolError("network", "NETWORK_ADDRESS_INVALID", "Resolved network address is invalid");
  if ((version === 4 && isBlockedIpv4(address)) || (version === 6 && isBlockedIpv6(address))) {
    throw new PandoraToolError("policy_denied", "NETWORK_PRIVATE_ADDRESS_DENIED", "Private, loopback, link-local, or reserved network targets are forbidden");
  }
  return true;
}

function assertResolvedAddressesAllowed(addresses) {
  if (!Array.isArray(addresses) || addresses.length === 0) {
    throw new PandoraToolError("network", "NETWORK_RESOLUTION_REQUIRED", "Network target must resolve before connection");
  }
  const normalized = [];
  for (const entry of addresses) {
    const address = typeof entry === "string" ? entry : entry?.address;
    assertResolvedAddressAllowed(address);
    normalized.push(address.toLowerCase());
  }
  return Object.freeze([...new Set(normalized)].sort());
}

function bindResolvedNetworkTarget(authorizedTarget, addresses) {
  if (!authorizedTarget?.host || !authorizedTarget?.url) {
    throw new PandoraToolError("network", "NETWORK_TARGET_NOT_AUTHORIZED", "Network target must be authorized before DNS binding");
  }
  const resolved_addresses = assertResolvedAddressesAllowed(addresses);
  return Object.freeze({ ...authorizedTarget, resolved_addresses, dns_bound: true });
}

function normalizeHostSet(values) {
  return new Set((values || []).map(normalizeHost));
}

function authorizeNetworkTarget(requirement, policy = {}) {
  if (!requirement || typeof requirement !== "object") throw new PandoraToolError("policy_denied", "NETWORK_REQUIREMENT_INVALID", "Network requirement is invalid");
  if (!NETWORK_CATEGORIES.includes(requirement.category)) throw new PandoraToolError("policy_denied", "NETWORK_CATEGORY_DENIED", "Unknown network target category is denied");
  let url;
  try { url = new URL(requirement.url); }
  catch { throw new PandoraToolError("policy_denied", "NETWORK_URL_INVALID", "Network target URL is invalid"); }
  if (!["https:", "http:"].includes(url.protocol)) throw new PandoraToolError("policy_denied", "NETWORK_SCHEME_DENIED", "Network target scheme is forbidden");
  if (url.username || url.password) throw new PandoraToolError("policy_denied", "NETWORK_CREDENTIALS_IN_URL", "Credentials in network URLs are forbidden");
  if (url.hash) throw new PandoraToolError("policy_denied", "NETWORK_FRAGMENT_DENIED", "Network target fragments are forbidden");
  const host = normalizeHost(url.hostname);
  if (["localhost", "metadata.google.internal"].includes(host) || host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".internal")) {
    throw new PandoraToolError("policy_denied", "NETWORK_LOCAL_HOST_DENIED", "Local and metadata network targets are forbidden");
  }
  if (net.isIP(host)) assertResolvedAddressAllowed(host);

  const provider = normalizeHostSet(policy.allowed_provider_hosts);
  const registries = normalizeHostSet(policy.allowed_registry_hosts);
  const customer = normalizeHostSet(policy.customer_authorized_hosts);
  const exceptional = normalizeHostSet(policy.approved_unknown_hosts);
  let allowed = false;
  if (requirement.category === "provider_api") allowed = provider.has(host);
  else if (requirement.category === "dependency_registry") allowed = registries.has(host);
  else if (requirement.category === "customer_specified_endpoint") allowed = requirement.customer_authorized === true && customer.has(host);
  else if (requirement.category === "unknown_external_endpoint") allowed = policy.allow_unknown_external === true && exceptional.has(host);
  if (!allowed) throw new PandoraToolError("policy_denied", "NETWORK_HOST_NOT_AUTHORIZED", "Network target is outside the authorized host policy");

  if (url.protocol === "http:" && policy.allow_plain_http !== true) throw new PandoraToolError("policy_denied", "NETWORK_TLS_REQUIRED", "TLS is required for external network access");
  const normalized = `${url.protocol}//${host}${url.port ? `:${url.port}` : ""}${url.pathname}${url.search}`;
  return Object.freeze({ category: requirement.category, url: normalized, host, protocol: url.protocol, port: url.port || (url.protocol === "https:" ? "443" : "80") });
}

module.exports = { NETWORK_CATEGORIES, normalizeHost, isBlockedIpv4, isBlockedIpv6, assertResolvedAddressAllowed, assertResolvedAddressesAllowed, bindResolvedNetworkTarget, authorizeNetworkTarget };

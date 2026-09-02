
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.memoryProjectKeyForControlProject = memoryProjectKeyForControlProject;
const source_authority_js_1 = require("./source-authority.js");

const PROJECT_KEY = /^[a-z0-9][a-z0-9._-]{0,79}$/;

function exactPolicyProjectKey(value, label) {
  if (typeof value !== "string" || !PROJECT_KEY.test(value)) {
    throw new Error(`source authority ${label} is missing or invalid`);
  }
  return value;
}

function memoryProjectKeyForControlProject(projectKey, policy = source_authority_js_1.sourceAuthorityPolicy) {
  if (projectKey === undefined || projectKey === null || projectKey === "") return undefined;
  if (typeof projectKey !== "string" || !PROJECT_KEY.test(projectKey)) {
    throw new Error("control project key is invalid");
  }
  const controlProjectKey = exactPolicyProjectKey(
    policy?.canonical?.vercel_project_name,
    "canonical.vercel_project_name",
  );
  const memoryProjectKey = exactPolicyProjectKey(policy?.project_key, "project_key");
  return projectKey === controlProjectKey ? memoryProjectKey : projectKey;
}

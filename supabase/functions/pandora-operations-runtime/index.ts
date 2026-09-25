import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import { createOperationsHandler } from "./handler.mjs";
const url = Deno.env.get("SUPABASE_URL") ?? "";
const publishable = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const boundedFetch: typeof fetch = (input, init = {}) =>
	fetch(input, {
		...init,
		signal: AbortSignal.any([
			...(init.signal ? [init.signal] : []),
			AbortSignal.timeout(12000),
		]),
	});
const admin = createClient(url, service, {
	auth: { persistSession: false, autoRefreshToken: false },
	global: { fetch: boundedFetch },
});
const authenticate = async (
	request: Request,
	scope: { organizationId: string; projectId: string },
) => {
	const authorization = request.headers.get("authorization") ?? "";
	if (!authorization.startsWith("Bearer ")) return null;
	const client = createClient(url, publishable, {
		auth: { persistSession: false, autoRefreshToken: false },
		global: { headers: { Authorization: authorization }, fetch: boundedFetch },
	});
	const { data, error } = await client.auth.getUser(authorization.slice(7));
	if (error || !data.user) return null;
	const membership = await client
		.from("memberships")
		.select("role,status")
		.eq("organization_id", scope.organizationId)
		.eq("user_id", data.user.id)
		.eq("status", "active")
		.maybeSingle();
	if (
		membership.error ||
		!membership.data ||
		!["owner", "admin"].includes(membership.data.role)
	)
		return null;
	const project = await client
		.from("pandora_projects")
		.select("id,organization_id")
		.eq("id", scope.projectId)
		.eq("organization_id", scope.organizationId)
		.maybeSingle();
	if (project.error || !project.data) return null;
	return {
		userId: data.user.id,
		active: true,
		role: membership.data.role,
		organizationId: project.data.organization_id,
		projectId: project.data.id,
	};
};
Deno.serve(
	createOperationsHandler({
		authenticate,
		rpc: (name: string, params: Record<string, unknown>) =>
			admin.rpc(name, params),
		allowedOrigins: (Deno.env.get("PANDORA_OPERATIONS_ALLOWED_ORIGINS") ?? "")
			.split(",")
			.map((s) => s.trim())
			.filter(Boolean),
	}),
);

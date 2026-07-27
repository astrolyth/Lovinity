// supabase/functions/push-dispatch/index.ts
//
// Edge Function: push-dispatch
//
// Relays a caller-supplied, already-generic {type, title, body} to a user's
// registered devices via FCM HTTP v1. Called ONLY by public.dispatch_push()
// (see supabase/migrations/20260726000001_push_notifications.sql), which
// authenticates with a shared dispatch secret stored server-side in
// private.push_config -- never a user JWT.
//
// E2E note: this function is content-free by construction. It never reads,
// decrypts, or invents message content -- it only forwards the title/body the
// database caller already chose (fixed, generic copy such as "New message
// from your partner"). See logic.ts's buildFcmMessage: it echoes exactly the
// type/title/body it was given and nothing else.
//
// No paid push service and no external push SDK: FCM HTTP v1 REST calls plus
// Deno's built-in Web Crypto for the OAuth2 JWT (RS256) signature.
//
// All pure/testable logic (body validation, JWT claims, FCM message shape,
// dead-token classification, JWT signing helpers) lives in ./logic.ts so
// index.test.ts can unit test it without ever importing this file -- this
// file's top-level `Deno.serve(...)` call requires --allow-net just to be
// imported, which would break `deno test` if the test imported it directly.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type DispatchBody,
  type ServiceAccount,
  buildFcmMessage,
  fetchAccessToken,
  isDeadTokenError,
  parseDispatchBody,
  timingSafeEqual,
} from "./logic.ts";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405);
    }

    const pushDispatchSecret = Deno.env.get("PUSH_DISPATCH_SECRET");
    const authHeader = req.headers.get("authorization") ?? "";
    const expected = `Bearer ${pushDispatchSecret ?? ""}`;
    if (!pushDispatchSecret || !timingSafeEqual(authHeader, expected)) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    let payload: DispatchBody;
    try {
      const raw = await req.json();
      payload = parseDispatchBody(raw);
    } catch (e) {
      const message = e instanceof Error ? e.message : "invalid request body";
      return jsonResponse({ error: "bad_request", message }, 400);
    }

    const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
    const fcmServiceAccountRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!fcmProjectId || !fcmServiceAccountRaw || !supabaseUrl || !supabaseServiceRoleKey) {
      console.error("push-dispatch: missing required environment configuration");
      return jsonResponse({ error: "server_misconfigured" }, 500);
    }

    let serviceAccount: ServiceAccount;
    try {
      serviceAccount = JSON.parse(fcmServiceAccountRaw);
    } catch {
      console.error("push-dispatch: FCM_SERVICE_ACCOUNT is not valid JSON");
      return jsonResponse({ error: "server_misconfigured" }, 500);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { data: tokenRows, error: selectError } = await supabase
      .from("device_push_tokens")
      .select("token, platform")
      .eq("user_id", payload.user_id);

    if (selectError) {
      console.error("push-dispatch: failed to load device tokens", selectError);
      return jsonResponse({ error: "internal_error" }, 500);
    }

    if (!tokenRows || tokenRows.length === 0) {
      return jsonResponse({ sent: 0, pruned: 0 });
    }

    let accessToken: string;
    try {
      accessToken = await fetchAccessToken(serviceAccount);
    } catch (e) {
      console.error("push-dispatch: OAuth token exchange failed", e);
      return jsonResponse({ error: "oauth_failed" }, 502);
    }

    let sent = 0;
    let pruned = 0;

    // Each token is handled independently so one bad/dead token can never
    // abort the rest of the batch.
    for (const row of tokenRows) {
      const token = row.token as string;
      try {
        const message = buildFcmMessage(token, {
          type: payload.type,
          title: payload.title,
          body: payload.body,
        });

        const resp = await fetch(
          `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${accessToken}`,
            },
            body: JSON.stringify(message),
          },
        );

        if (resp.ok) {
          sent += 1;
          continue;
        }

        const errorJson = await resp.json().catch(() => null);
        if (isDeadTokenError(errorJson, resp.status)) {
          const { error: deleteError } = await supabase
            .from("device_push_tokens")
            .delete()
            .eq("token", token);
          if (deleteError) {
            console.error("push-dispatch: failed to prune dead token", deleteError);
          } else {
            pruned += 1;
          }
        } else {
          console.error("push-dispatch: FCM send failed", resp.status, errorJson);
        }
      } catch (e) {
        // Isolate per-token failures (network blip, malformed row, etc.) --
        // never let one token's exception abort the batch.
        console.error("push-dispatch: unexpected error sending to token", e);
      }
    }

    return jsonResponse({ sent, pruned });
  } catch (e) {
    console.error("push-dispatch: unhandled error", e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});

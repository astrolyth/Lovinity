// supabase/functions/generate-questions/index.ts
//
// Edge Function: generate-questions
//
// Tops up the daily_questions pool when approved questions run low, using the
// Claude API with structured outputs. Everything it writes lands as
// status='pending' -- a human approves in the Supabase dashboard before any
// couple sees it (see supabase/migrations/20260802000003_question_queue.sql,
// where get_current_question() only ever selects status='approved'). This
// function must never write status='approved'.
//
// Intended to run at most monthly on a schedule, and to be safe to invoke by
// hand. It ignores the request body entirely: there is no input to this
// function, so there is nothing a caller can steer -- in particular no way to
// ask for a different status, category, language, or batch size.
//
// Authentication is a shared secret (GENERATE_QUESTIONS_SECRET), the same
// pattern push-dispatch uses, and supabase/config.toml turns verify_jwt off for
// this function. JWT verification would NOT protect this endpoint: the anon key
// is itself a JWT signed with the project's JWT secret and is compiled into the
// shipped Flutter binary (lib/core/config/env.dart), as is any user's session
// token. Every invocation below the threshold costs a paid Opus call and
// inserts up to BATCH pending rows, and there is no concurrency control, so an
// unauthenticated endpoint here is a billing and review-queue hazard.
//
// Pure logic (prompt, schema, validation, secret comparison) lives in
// ./logic.ts so it can be unit tested without --allow-net; same split as
// push-dispatch.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@0.115.0";
import {
  dedupeKey,
  parseGenerated,
  QUESTION_SCHEMA,
  SYSTEM_PROMPT,
  timingSafeEqual,
} from "./logic.ts";

/** Top up when approved questions fall below this. */
const THRESHOLD = 20;
/** How many questions to ask for in one generation. */
const BATCH = 20;

// Tone quality is the entire point of this function -- it runs at most monthly,
// so there is nothing to gain by generating on a cheaper model.
const MODEL = "claude-opus-5";
// Thinking is on by default on this model and shares the ceiling with the
// response text, so leave room for both: a truncated response would fail
// JSON.parse and waste the whole call.
const MAX_TOKENS = 16000;

/**
 * Page size for the cross-batch dedupe scan. Deliberately below PostgREST's
 * default `max-rows` of 1000 so a short page reliably means "end of table"
 * rather than "the server capped us".
 */
const SCAN_PAGE = 500;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Log/report only an error's message, never the error object. Anything thrown
 * by an HTTP client here has touched a credential (the Anthropic key, the
 * service_role key) and may carry request headers on the object; the message
 * string does not.
 */
function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405);
    }

    // Shared-secret gate, before any env read or any work. Fails closed: a
    // missing GENERATE_QUESTIONS_SECRET short-circuits to 401 rather than
    // comparing against "Bearer " and letting an empty token through.
    const generateQuestionsSecret = Deno.env.get("GENERATE_QUESTIONS_SECRET");
    const authHeader = req.headers.get("authorization") ?? "";
    const expected = `Bearer ${generateQuestionsSecret ?? ""}`;
    if (!generateQuestionsSecret || !timingSafeEqual(authHeader, expected)) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!apiKey || !supabaseUrl || !supabaseServiceRoleKey) {
      // Fail loudly. A silent no-op here is indistinguishable from "the pool
      // was already full", so a missing key would go unnoticed for months
      // while the approved pool quietly drained.
      console.error(
        "generate-questions: missing required environment configuration:",
        [
          !apiKey ? "ANTHROPIC_API_KEY" : null,
          !supabaseUrl ? "SUPABASE_URL" : null,
          !supabaseServiceRoleKey ? "SUPABASE_SERVICE_ROLE_KEY" : null,
        ].filter(Boolean).join(", "),
      );
      return jsonResponse({ error: "server_misconfigured" }, 500);
    }

    // service_role is required: this function writes daily_questions, which no
    // end-user role may insert into. The key stays inside this closure -- it is
    // never logged, echoed, or included in any response.
    const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { count, error: countError } = await supabase
      .from("daily_questions")
      .select("id", { count: "exact", head: true })
      .eq("status", "approved");
    if (countError) {
      console.error("generate-questions: approved count failed", countError);
      return jsonResponse({ error: "internal_error" }, 500);
    }

    const approvedPool = count ?? 0;
    if (approvedPool >= THRESHOLD) {
      return jsonResponse({
        generated: 0,
        duplicates_skipped: 0,
        approved_pool: approvedPool,
      });
    }

    // Every question already on file, at any status: a question a human
    // already rejected should not come back either.
    const existingKeys = new Set<string>();
    for (let from = 0; ; from += SCAN_PAGE) {
      const { data, error } = await supabase
        .from("daily_questions")
        .select("question")
        // A stable sort is required: paging an unordered select can repeat or
        // skip rows between pages, which would silently weaken the dedupe.
        .order("id")
        .range(from, from + SCAN_PAGE - 1);
      if (error) {
        console.error("generate-questions: existing-question scan failed", error);
        return jsonResponse({ error: "internal_error" }, 500);
      }
      const page = data ?? [];
      for (const row of page) {
        if (typeof row.question === "string") {
          existingKeys.add(dedupeKey(row.question));
        }
      }
      if (page.length < SCAN_PAGE) break;
    }

    const client = new Anthropic({ apiKey });
    let response;
    try {
      // Streaming, not messages.create: MAX_TOKENS is high enough that a slow
      // generation can outlive the Edge Function's wall-clock ceiling (a couple
      // of minutes) while the SDK is still waiting on its own 10-minute request
      // timeout. The platform would kill the invocation before the SDK returned
      // -- the catch below would never run, nothing would be logged, no
      // response would be sent, and the call would still be billed. A stream
      // keeps bytes moving; finalMessage() gives back the same complete Message
      // the non-streaming call would have, so every check below is unchanged.
      response = await client.messages.stream({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        // Structured outputs: the model's text is constrained to QUESTION_SCHEMA,
        // so the payload is parseable JSON by construction. Never string-parse
        // the response instead.
        output_config: {
          format: { type: "json_schema", schema: QUESTION_SCHEMA },
        },
        messages: [{
          role: "user",
          content:
            `Write ${BATCH} new questions. Vary the categories and don't repeat ` +
            `phrasings or themes within the batch.`,
        }],
      }).finalMessage();
    } catch (e) {
      console.error("generate-questions: Claude request failed:", errorMessage(e));
      return jsonResponse({ error: "generation_failed" }, 502);
    }

    if (response.stop_reason === "refusal") {
      // Deliberately not configured with server-side fallbacks: a refusal on
      // this prompt means something is wrong with the prompt, and a quietly
      // substituted model would change the tone the review queue exists to
      // protect. Surface it instead.
      // stop_details.category is a fixed enum ("cyber", "bio", ... or null) --
      // no model text, nothing caller-supplied. It is the only signal that says
      // *why* the refusal happened, and this is the hardest failure here to
      // reproduce, so log it.
      console.error(
        "generate-questions: model refused the request; category =",
        response.stop_details?.category ?? "unknown",
      );
      return jsonResponse({ error: "generation_refused" }, 502);
    }
    if (response.stop_reason === "max_tokens") {
      console.error(
        `generate-questions: response hit max_tokens (${MAX_TOKENS}); payload is truncated`,
      );
      return jsonResponse({ error: "generation_truncated" }, 502);
    }

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock) {
      console.error(
        "generate-questions: no text block in response; stop_reason =",
        response.stop_reason,
      );
      return jsonResponse({ error: "generation_failed" }, 502);
    }

    // JSON.parse is deliberately NOT inside the validation try below. V8 builds
    // its SyntaxError message out of an excerpt of the input -- e.g. `Unexpected
    // token 'h', "here are t"... is not valid JSON` -- so echoing that message
    // would leak ~30 characters of raw model output to the caller. Fixed
    // message here; parseGenerated's messages (built from indices and module
    // constants only) stay informative below.
    let payload: unknown;
    try {
      payload = JSON.parse(textBlock.text);
    } catch {
      console.error(
        `generate-questions: response text is not valid JSON (${textBlock.text.length} chars)`,
      );
      return jsonResponse(
        { error: "invalid_generated_payload", message: "response was not valid JSON" },
        502,
      );
    }

    // parseGenerated is all-or-nothing and throws on anything malformed: a bad
    // batch is rejected whole rather than partially inserted, and unvalidated
    // model output is never written.
    let generated;
    try {
      generated = parseGenerated(payload);
    } catch (e) {
      const message = errorMessage(e);
      console.error("generate-questions: invalid generated payload:", message);
      return jsonResponse({ error: "invalid_generated_payload", message }, 502);
    }

    // Cross-batch dedupe. Dropping rows here is reported in the response
    // rather than swallowed, so a generation that mostly repeated itself does
    // not look like a healthy top-up.
    const fresh = generated.filter((r) => !existingKeys.has(dedupeKey(r.question)));
    const duplicatesSkipped = generated.length - fresh.length;
    if (duplicatesSkipped > 0) {
      console.warn(
        `generate-questions: skipped ${duplicatesSkipped} of ${generated.length} ` +
          `question(s) already present in daily_questions`,
      );
    }

    if (fresh.length === 0) {
      return jsonResponse({
        generated: 0,
        duplicates_skipped: duplicatesSkipped,
        approved_pool: approvedPool,
      });
    }

    const { error: insertError } = await supabase.from("daily_questions").insert(
      // Built field by field from parseGenerated's own fresh objects -- the
      // model's raw entries are never spread in, so no model-supplied key can
      // reach the insert.
      fresh.map((r) => ({
        question: r.question,
        category: r.category,
        language: "en",
        status: "pending", // never 'approved' -- a human reviews first
        source: "generated",
      })),
    );
    if (insertError) {
      console.error("generate-questions: insert failed", insertError);
      return jsonResponse({ error: "internal_error" }, 500);
    }

    return jsonResponse({
      generated: fresh.length,
      duplicates_skipped: duplicatesSkipped,
      approved_pool: approvedPool,
    });
  } catch (e) {
    console.error("generate-questions: unhandled error:", errorMessage(e));
    return jsonResponse({ error: "internal_error" }, 500);
  }
});

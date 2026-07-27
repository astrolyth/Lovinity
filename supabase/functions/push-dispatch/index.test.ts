// supabase/functions/push-dispatch/index.test.ts
//
// Unit tests for the pure logic in logic.ts. No network calls, no real
// credentials -- everything here is deterministic input -> output.
//
// Deliberately imports from ./logic.ts, NOT ./index.ts: index.ts has a
// top-level `Deno.serve(...)` call which requires --allow-net just to be
// imported, and these tests must run with zero permissions.
//
// Run with (from the supabase/functions/push-dispatch directory):
//   deno test

import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

import {
  buildFcmMessage,
  buildOAuthJwtClaims,
  isDeadTokenError,
  parseDispatchBody,
  timingSafeEqual,
} from "./logic.ts";

// ---------------------------------------------------------------------------
// parseDispatchBody
// ---------------------------------------------------------------------------

Deno.test("parseDispatchBody: accepts a well-formed chat payload", () => {
  const input = {
    user_id: "11111111-2222-3333-4444-555555555555",
    type: "chat",
    title: "New message",
    body: "New message from your partner",
  };
  const result = parseDispatchBody(input);
  assertEquals(result, input);
});

Deno.test("parseDispatchBody: accepts a well-formed pairing payload", () => {
  const input = {
    user_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    type: "pairing",
    title: "You're connected",
    body: "You and your partner are now paired",
  };
  const result = parseDispatchBody(input);
  assertEquals(result, input);
});

Deno.test("parseDispatchBody: rejects null/non-object input", () => {
  assertThrows(() => parseDispatchBody(null));
  assertThrows(() => parseDispatchBody("not an object"));
  assertThrows(() => parseDispatchBody(42));
  assertThrows(() => parseDispatchBody([1, 2, 3]));
});

Deno.test("parseDispatchBody: rejects a missing/malformed user_id", () => {
  assertThrows(() =>
    parseDispatchBody({ type: "chat", title: "t", body: "b" })
  );
  assertThrows(() =>
    parseDispatchBody({
      user_id: "not-a-uuid",
      type: "chat",
      title: "t",
      body: "b",
    })
  );
});

Deno.test("parseDispatchBody: rejects a type outside the allow-list", () => {
  assertThrows(() =>
    parseDispatchBody({
      user_id: "11111111-2222-3333-4444-555555555555",
      type: "marketing", // not 'chat' | 'pairing'
      title: "t",
      body: "b",
    })
  );
});

Deno.test("parseDispatchBody: rejects empty title/body", () => {
  const base = {
    user_id: "11111111-2222-3333-4444-555555555555",
    type: "chat",
  };
  assertThrows(() => parseDispatchBody({ ...base, title: "", body: "b" }));
  assertThrows(() => parseDispatchBody({ ...base, title: "t", body: "" }));
});

Deno.test("parseDispatchBody: rejects overlong title/body", () => {
  const base = {
    user_id: "11111111-2222-3333-4444-555555555555",
    type: "chat",
  };
  assertThrows(() =>
    parseDispatchBody({ ...base, title: "x".repeat(201), body: "b" })
  );
  assertThrows(() =>
    parseDispatchBody({ ...base, title: "t", body: "x".repeat(1001) })
  );
});

// ---------------------------------------------------------------------------
// buildOAuthJwtClaims
// ---------------------------------------------------------------------------

Deno.test("buildOAuthJwtClaims: builds the expected claim set", () => {
  const now = 1_700_000_000;
  const claims = buildOAuthJwtClaims(
    { client_email: "svc@my-project.iam.gserviceaccount.com" },
    now,
  );
  assertEquals(claims, {
    iss: "svc@my-project.iam.gserviceaccount.com",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
});

Deno.test("buildOAuthJwtClaims: honors a custom token_uri if provided", () => {
  const now = 1_700_000_000;
  const claims = buildOAuthJwtClaims(
    {
      client_email: "svc@my-project.iam.gserviceaccount.com",
      token_uri: "https://example.test/token",
    },
    now,
  );
  assertEquals(claims.aud, "https://example.test/token");
});

// ---------------------------------------------------------------------------
// buildFcmMessage -- content-free assertion
// ---------------------------------------------------------------------------

Deno.test("buildFcmMessage: shape matches the FCM HTTP v1 contract", () => {
  const msg = buildFcmMessage("device-token-abc", {
    type: "chat",
    title: "New message",
    body: "New message from your partner",
  });

  assertEquals(msg, {
    message: {
      token: "device-token-abc",
      notification: {
        title: "New message",
        body: "New message from your partner",
      },
      data: { type: "chat" },
      android: { notification: { channel_id: "chat" } },
      apns: { payload: { aps: { sound: "default", "content-available": 1 } } },
    },
  });
});

Deno.test("buildFcmMessage: is content-free -- output contains only the passed token/type/title/body strings, nothing invented", () => {
  const payload = {
    type: "pairing",
    title: "SENTINEL_TITLE",
    body: "SENTINEL_BODY",
  };
  const msg = buildFcmMessage("SENTINEL_TOKEN", payload);
  const serialized = JSON.stringify(msg);

  // The only "content" strings appearing anywhere in the message are exactly
  // the ones the caller passed in -- no plaintext, no lookup, nothing added.
  const stringLeaves: string[] = [];
  const collect = (value: unknown) => {
    if (typeof value === "string") {
      stringLeaves.push(value);
    } else if (Array.isArray(value)) {
      value.forEach(collect);
    } else if (value && typeof value === "object") {
      Object.values(value).forEach(collect);
    }
  };
  collect(msg);

  const allowed = new Set([
    "SENTINEL_TOKEN",
    "SENTINEL_TITLE",
    "SENTINEL_BODY",
    "pairing",
    "chat", // fixed Android notification channel id, not user content
    "default", // fixed APNs sound
  ]);
  for (const s of stringLeaves) {
    assert(
      allowed.has(s),
      `unexpected/invented string literal in FCM message: ${JSON.stringify(s)} in ${serialized}`,
    );
  }
});

// ---------------------------------------------------------------------------
// isDeadTokenError
// ---------------------------------------------------------------------------

Deno.test("isDeadTokenError: true for FCM UNREGISTERED status", () => {
  const fcmError = {
    error: {
      code: 404,
      message: "Requested entity was not found.",
      status: "NOT_FOUND",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        },
      ],
    },
  };
  assert(isDeadTokenError(fcmError));
});

Deno.test("isDeadTokenError: true for bare HTTP 404 with no parseable body", () => {
  assert(isDeadTokenError(null, 404));
});

Deno.test("isDeadTokenError: true for top-level status NOT_FOUND", () => {
  assert(isDeadTokenError({ error: { status: "NOT_FOUND" } }));
});

Deno.test("isDeadTokenError: false for an unrelated/transient error", () => {
  const fcmError = {
    error: {
      code: 500,
      message: "Internal error.",
      status: "INTERNAL",
    },
  };
  assert(!isDeadTokenError(fcmError, 500));
});

Deno.test("isDeadTokenError: false for INVALID_ARGUMENT (bad message shape, not a dead token)", () => {
  const fcmError = {
    error: {
      code: 400,
      message: "Invalid registration token.",
      status: "INVALID_ARGUMENT",
    },
  };
  assert(!isDeadTokenError(fcmError, 400));
});

Deno.test("isDeadTokenError: false for malformed/absent error body", () => {
  assert(!isDeadTokenError(null));
  assert(!isDeadTokenError(undefined));
  assert(!isDeadTokenError("not json"));
  assert(!isDeadTokenError({}));
});

// ---------------------------------------------------------------------------
// timingSafeEqual
// ---------------------------------------------------------------------------

Deno.test("timingSafeEqual: true for identical strings", () => {
  assert(timingSafeEqual("Bearer abc123", "Bearer abc123"));
});

Deno.test("timingSafeEqual: false for different strings, including different lengths", () => {
  assert(!timingSafeEqual("Bearer abc123", "Bearer abc124"));
  assert(!timingSafeEqual("Bearer abc123", "Bearer abc12"));
  assert(!timingSafeEqual("", "Bearer abc123"));
});

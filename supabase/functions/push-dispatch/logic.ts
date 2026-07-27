// supabase/functions/push-dispatch/logic.ts
//
// Pure, network-free, credential-free logic for push-dispatch, kept in its
// own module so index.test.ts can import it without ever touching index.ts's
// top-level `Deno.serve(...)` (which requires --allow-net just to import).
//
// E2E note: this function is content-free by construction. It never reads,
// decrypts, or invents message content -- it only forwards the title/body the
// database caller already chose (fixed, generic copy such as "New message
// from your partner"). See buildFcmMessage below: it echoes exactly the
// type/title/body it was given and nothing else.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DispatchBody {
  user_id: string;
  type: string;
  title: string;
  body: string;
}

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  private_key_id?: string;
  token_uri?: string;
  [key: string]: unknown;
}

export interface DispatchPayload {
  type: string;
  title: string;
  body: string;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Must match the contract from Task 1's dispatch_push() callers.
const ALLOWED_TYPES = new Set(["chat", "pairing"]);

const MAX_TITLE_LEN = 200;
const MAX_BODY_LEN = 1000;

/**
 * Validate + narrow the JSON body posted by public.dispatch_push(). Throws a
 * plain Error with a human-readable message on any malformed input; callers
 * turn that into a 400.
 */
export function parseDispatchBody(json: unknown): DispatchBody {
  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new Error("request body must be a JSON object");
  }

  const obj = json as Record<string, unknown>;
  const { user_id, type, title, body } = obj;

  if (typeof user_id !== "string" || !UUID_RE.test(user_id)) {
    throw new Error("user_id must be a UUID string");
  }
  if (typeof type !== "string" || !ALLOWED_TYPES.has(type)) {
    throw new Error("type must be one of 'chat' | 'pairing'");
  }
  if (typeof title !== "string" || title.length === 0 || title.length > MAX_TITLE_LEN) {
    throw new Error(`title must be a non-empty string (max ${MAX_TITLE_LEN} chars)`);
  }
  if (typeof body !== "string" || body.length === 0 || body.length > MAX_BODY_LEN) {
    throw new Error(`body must be a non-empty string (max ${MAX_BODY_LEN} chars)`);
  }

  return { user_id, type, title, body };
}

/**
 * Build the JWT claim set for the Google OAuth2 "JWT bearer" grant. Pure --
 * takes `now` (epoch seconds) as a parameter instead of reading the clock, so
 * it is deterministic in tests.
 */
export function buildOAuthJwtClaims(
  serviceAccount: Pick<ServiceAccount, "client_email" | "token_uri">,
  now: number,
): Record<string, unknown> {
  return {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    // Google caps assertion lifetime at 1 hour.
    exp: now + 3600,
  };
}

/**
 * Build the FCM HTTP v1 `messages:send` request body for one device token.
 * Content-free by construction: the only strings that flow into the message
 * are the token (device identity, not content) and the caller-supplied
 * type/title/body -- nothing is invented or looked up here.
 */
export function buildFcmMessage(token: string, payload: DispatchPayload) {
  return {
    message: {
      token,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: {
        type: payload.type,
      },
      android: {
        notification: {
          channel_id: "chat",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            "content-available": 1,
          },
        },
      },
    },
  };
}

/**
 * Classify an FCM per-message failure as "the token is dead, prune it" vs
 * "some other, possibly transient, error -- leave the token alone".
 * `httpStatus` is the outer HTTP status of the messages:send response;
 * `fcmErrorResponse` is its parsed JSON body (or null/undefined if it
 * couldn't be parsed).
 */
export function isDeadTokenError(
  fcmErrorResponse: unknown,
  httpStatus?: number,
): boolean {
  if (httpStatus === 404) return true;

  if (typeof fcmErrorResponse !== "object" || fcmErrorResponse === null) {
    return false;
  }

  const error = (fcmErrorResponse as Record<string, unknown>).error;
  if (typeof error !== "object" || error === null) return false;

  const errObj = error as Record<string, unknown>;
  if (errObj.status === "UNREGISTERED" || errObj.status === "NOT_FOUND") {
    return true;
  }

  const details = errObj.details;
  if (Array.isArray(details)) {
    for (const detail of details) {
      if (
        detail &&
        typeof detail === "object" &&
        (detail as Record<string, unknown>).errorCode === "UNREGISTERED"
      ) {
        return true;
      }
    }
  }

  return false;
}

/** Constant-time string comparison for the dispatch-secret check. */
export function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  if (aBytes.length !== bBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Crypto helpers -- pure given their inputs (no env/global state), but not
// exercised in unit tests since they need a real PKCS8 key; covered by the
// deno check type-check plus manual read-through.
// ---------------------------------------------------------------------------

export function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function pemPrivateKeyToDer(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export async function signOAuthJwt(
  serviceAccount: ServiceAccount,
  now: number,
): Promise<string> {
  const header = {
    alg: "RS256",
    typ: "JWT",
    kid: serviceAccount.private_key_id,
  };
  const claims = buildOAuthJwtClaims(serviceAccount, now);
  const signingInput =
    `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claims))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemPrivateKeyToDer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export async function fetchAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signOAuthJwt(serviceAccount, now);

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`OAuth token exchange failed: ${resp.status} ${text}`);
  }

  const json = await resp.json();
  if (typeof json.access_token !== "string") {
    throw new Error("OAuth token exchange response missing access_token");
  }
  return json.access_token;
}

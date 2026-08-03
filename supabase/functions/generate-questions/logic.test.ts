// supabase/functions/generate-questions/logic.test.ts
//
// Unit tests for the pure logic in logic.ts. No network, no credentials, no
// env vars -- everything here is deterministic input -> output.
//
// Deliberately imports from ./logic.ts, NOT ./index.ts: index.ts has a
// top-level `Deno.serve(...)` which requires --allow-net just to be imported,
// and these tests must run with zero permissions. Same split as
// push-dispatch/logic.ts.
//
// Every assertThrows here pins the *reason* the batch was rejected, not merely
// that something threw: a rejection test with no message argument would keep
// passing if the throw started coming from an unrelated bug.
//
// Run with (from the repo root):
//   deno test supabase/functions/generate-questions/logic.test.ts

import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  CATEGORIES,
  MAX_QUESTION_LEN,
  MIN_QUESTION_LEN,
  parseGenerated,
  QUESTION_SCHEMA,
  SYSTEM_PROMPT,
} from "./logic.ts";

// ---------------------------------------------------------------------------
// parseGenerated -- happy path
// ---------------------------------------------------------------------------

Deno.test("parseGenerated accepts a well-formed batch", () => {
  const out = parseGenerated({
    questions: [
      { question: "What made you smile today?", category: "playful" },
      { question: "Which sunnah do you want to build together?", category: "deen" },
    ],
  });
  assertEquals(out.length, 2);
  assertEquals(out[0].category, "playful");
});

Deno.test("parseGenerated accepts every app category", () => {
  const out = parseGenerated({
    questions: CATEGORIES.map((category) => ({
      question: `A question about ${category}?`,
      category,
    })),
  });
  assertEquals(out.map((q) => q.category), [...CATEGORIES]);
});

Deno.test("parseGenerated trims surrounding whitespace off the question", () => {
  const out = parseGenerated({
    questions: [{ question: "  What are you grateful for?\n", category: "reflective" }],
  });
  assertEquals(out[0].question, "What are you grateful for?");
});

Deno.test("parseGenerated strips zero-width characters from inside the question", () => {
  // trim() does not touch U+200B..U+200D / U+2060, so they would otherwise be
  // stored verbatim in a question that renders with invisible junk in it.
  const out = parseGenerated({
    questions: [
      {
        question: "What are you\u200B grateful\u2060 for\u200D?",
        category: "reflective",
      },
    ],
  });
  assertEquals(out[0].question, "What are you grateful for?");
});

Deno.test("parseGenerated returns a plain, narrowed object -- no extra keys pass through", () => {
  const out = parseGenerated({
    questions: [
      {
        question: "What is one dua you make for me?",
        category: "deen",
        // Anything the model bolts on is dropped, not forwarded to the insert.
        id: "hijacked",
        status: "approved",
      },
    ],
  });
  assertEquals(out, [{ question: "What is one dua you make for me?", category: "deen" }]);
});

// ---------------------------------------------------------------------------
// parseGenerated -- rejections (this is a trust boundary: model output)
// ---------------------------------------------------------------------------

Deno.test("parseGenerated rejects an unknown category", () => {
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "What made you smile today?", category: "spicy" }],
      }),
    Error,
    "category must be one of",
  );
});

Deno.test("parseGenerated rejects a category that differs only in case", () => {
  // The category column is checked against exact lowercase values, so a
  // near-miss like "Deen" must be rejected rather than quietly lowercased.
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "What made you smile today?", category: "Deen" }],
      }),
    Error,
    "category must be one of",
  );
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "What made you smile today?", category: "PLAYFUL" }],
      }),
    Error,
    "category must be one of",
  );
});

Deno.test("parseGenerated rejects an empty or blank question", () => {
  assertThrows(
    () => parseGenerated({ questions: [{ question: "   ", category: "deen" }] }),
    Error,
    "question is empty",
  );
  assertThrows(
    () => parseGenerated({ questions: [{ question: "", category: "deen" }] }),
    Error,
    "question is empty",
  );
});

Deno.test("parseGenerated rejects a question made only of zero-width characters", () => {
  // These survive trim(), so without an explicit strip this batch would land
  // as a visually blank pending row awaiting human review.
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "\u200B\u200B\u200D", category: "deen" }],
      }),
    Error,
    "question is empty",
  );
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: " \u2060 \uFEFF ", category: "deen" }],
      }),
    Error,
    "question is empty",
  );
});

Deno.test("parseGenerated rejects a non-array payload", () => {
  assertThrows(
    () => parseGenerated({ questions: "nope" }),
    Error,
    "questions is not an array",
  );
  assertThrows(
    () => parseGenerated({ questions: 42 }),
    Error,
    "questions is not an array",
  );
  assertThrows(
    () =>
      parseGenerated({
        questions: { "0": { question: "What made you smile today?", category: "deen" } },
      }),
    Error,
    "questions is not an array",
  );
});

Deno.test("parseGenerated rejects null / non-object input", () => {
  const wanted = "generated payload must be a JSON object";
  assertThrows(() => parseGenerated(null), Error, wanted);
  assertThrows(() => parseGenerated(undefined), Error, wanted);
  assertThrows(() => parseGenerated("not an object"), Error, wanted);
  assertThrows(() => parseGenerated(42), Error, wanted);
  assertThrows(
    () => parseGenerated([{ question: "What made you smile today?", category: "deen" }]),
    Error,
    wanted,
  );
});

Deno.test("parseGenerated rejects a missing questions key", () => {
  assertThrows(() => parseGenerated({}), Error, "questions is not an array");
  assertThrows(
    () =>
      parseGenerated({
        items: [{ question: "What made you smile today?", category: "deen" }],
      }),
    Error,
    "questions is not an array",
  );
});

Deno.test("parseGenerated rejects an empty batch", () => {
  // An empty array is not a successful generation -- surfacing it as an error
  // keeps the caller from reporting "inserted 0" as a healthy top-up.
  assertThrows(
    () => parseGenerated({ questions: [] }),
    Error,
    "payload.questions is empty",
  );
});

Deno.test("parseGenerated rejects a non-object array element", () => {
  assertThrows(
    () => parseGenerated({ questions: ["just a string"] }),
    Error,
    "questions[0] is not an object",
  );
  assertThrows(
    () => parseGenerated({ questions: [null] }),
    Error,
    "questions[0] is not an object",
  );
  assertThrows(
    () => parseGenerated({ questions: [["question", "playful"]] }),
    Error,
    "questions[0] is not an object",
  );
});

Deno.test("parseGenerated rejects non-string question / category fields", () => {
  assertThrows(
    () => parseGenerated({ questions: [{ question: 7, category: "deen" }] }),
    Error,
    "question is not a string",
  );
  assertThrows(
    () => parseGenerated({ questions: [{ category: "deen" }] }),
    Error,
    "question is not a string",
  );
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "What made you smile today?", category: 7 }],
      }),
    Error,
    "category is not a string",
  );
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "What made you smile today?", category: null }],
      }),
    Error,
    "category is not a string",
  );
  assertThrows(
    () => parseGenerated({ questions: [{ question: "What made you smile today?" }] }),
    Error,
    "category is not a string",
  );
});

// ---------------------------------------------------------------------------
// parseGenerated -- length bounds (pinned exactly at the boundary)
// ---------------------------------------------------------------------------

Deno.test("length bounds are the values the prompt promises the model", () => {
  // The prompt quotes these numbers, so a silent change to either constant
  // would make the prompt lie about what gets accepted.
  assertEquals(MIN_QUESTION_LEN, 10);
  assertEquals(MAX_QUESTION_LEN, 500);
});

Deno.test("parseGenerated accepts a question exactly at MAX_QUESTION_LEN", () => {
  const atLimit = "x".repeat(MAX_QUESTION_LEN);
  const out = parseGenerated({ questions: [{ question: atLimit, category: "playful" }] });
  assertEquals(out[0].question.length, MAX_QUESTION_LEN);
});

Deno.test("parseGenerated rejects a question one character over MAX_QUESTION_LEN", () => {
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "x".repeat(MAX_QUESTION_LEN + 1), category: "playful" }],
      }),
    Error,
    `longer than ${MAX_QUESTION_LEN} characters`,
  );
});

Deno.test("parseGenerated accepts a question exactly at MIN_QUESTION_LEN", () => {
  const atFloor = "x".repeat(MIN_QUESTION_LEN);
  const out = parseGenerated({ questions: [{ question: atFloor, category: "playful" }] });
  assertEquals(out[0].question.length, MIN_QUESTION_LEN);
});

Deno.test("parseGenerated rejects a question one character under MIN_QUESTION_LEN", () => {
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: "x".repeat(MIN_QUESTION_LEN - 1), category: "playful" }],
      }),
    Error,
    `shorter than ${MIN_QUESTION_LEN} characters`,
  );
});

Deno.test("parseGenerated rejects degenerately short output", () => {
  // "x" and "?" satisfy every other rule; only the floor catches them.
  for (const question of ["x", "?", "Why us?"]) {
    assertThrows(
      () => parseGenerated({ questions: [{ question, category: "reflective" }] }),
      Error,
      `shorter than ${MIN_QUESTION_LEN} characters`,
    );
  }
});

Deno.test("the length floor is measured after zero-width characters are stripped", () => {
  // Padding a one-word question with invisible characters must not buy it a
  // pass over the floor.
  assertThrows(
    () =>
      parseGenerated({
        questions: [{ question: `Why?${"\u200B".repeat(20)}`, category: "reflective" }],
      }),
    Error,
    `shorter than ${MIN_QUESTION_LEN} characters`,
  );
});

// ---------------------------------------------------------------------------
// parseGenerated -- intra-batch duplicates
// ---------------------------------------------------------------------------

Deno.test("parseGenerated rejects a batch containing the same question twice", () => {
  // daily_questions has no unique constraint on `question`, so a generation
  // that returned one question twenty times would otherwise insert cleanly.
  assertThrows(
    () =>
      parseGenerated({
        questions: [
          { question: "What made you smile today?", category: "playful" },
          { question: "Which sunnah do you want to build together?", category: "deen" },
          { question: "What made you smile today?", category: "playful" },
        ],
      }),
    Error,
    "questions[2].question duplicates questions[0]",
  );
});

Deno.test("duplicate detection ignores case, padding, and whitespace runs", () => {
  assertThrows(
    () =>
      parseGenerated({
        questions: [
          { question: "What made you smile today?", category: "playful" },
          { question: "  what MADE you   smile today?  ", category: "reflective" },
        ],
      }),
    Error,
    "questions[1].question duplicates questions[0]",
  );
});

Deno.test("parseGenerated still accepts a batch of genuinely different questions", () => {
  const out = parseGenerated({
    questions: [
      { question: "What made you smile today?", category: "playful" },
      { question: "What made you smile this week?", category: "reflective" },
      { question: "Which sunnah do you want to build together?", category: "deen" },
    ],
  });
  assertEquals(out.length, 3);
});

Deno.test("parseGenerated rejects the whole batch when any single item is bad", () => {
  // All-or-nothing: a partially bad batch must not be silently truncated.
  assertThrows(
    () =>
      parseGenerated({
        questions: [
          { question: "What made you smile today?", category: "playful" },
          { question: "What are you grateful for right now?", category: "spicy" },
        ],
      }),
    Error,
    "questions[1].category must be one of",
  );
});

// ---------------------------------------------------------------------------
// Schema + prompt
// ---------------------------------------------------------------------------

Deno.test("schema and prompt are wired for the four app categories", () => {
  // Copy before sorting: the schema is a shared module-level constant.
  const cats = [...QUESTION_SCHEMA.properties.questions.items.properties.category.enum];
  assertEquals(cats.sort(), ["deen", "future", "playful", "reflective"]);
  // The prompt must carry the app's frame, not generic couple-quiz copy.
  assertEquals(SYSTEM_PROMPT.includes("Muslim"), true);
});

Deno.test("schema is strict enough for structured outputs", () => {
  const item = QUESTION_SCHEMA.properties.questions.items;
  assertEquals(QUESTION_SCHEMA.type, "object");
  assertEquals(QUESTION_SCHEMA.additionalProperties, false);
  assertEquals([...QUESTION_SCHEMA.required], ["questions"]);
  assertEquals(QUESTION_SCHEMA.properties.questions.type, "array");
  assertEquals(item.type, "object");
  assertEquals(item.additionalProperties, false);
  assertEquals([...item.required].sort(), ["category", "question"]);
  assertEquals(item.properties.question.type, "string");
  assertEquals(item.properties.category.type, "string");
});

Deno.test("schema enum matches CATEGORIES exactly", () => {
  assertEquals(
    [...QUESTION_SCHEMA.properties.questions.items.properties.category.enum],
    [...CATEGORIES],
  );
});

Deno.test("prompt names every category it asks the model to assign", () => {
  for (const category of CATEGORIES) {
    assert(
      SYSTEM_PROMPT.includes(category),
      `SYSTEM_PROMPT never mentions the "${category}" category`,
    );
  }
});

Deno.test("prompt sets the married-couple frame", () => {
  assert(SYSTEM_PROMPT.includes("married"), "SYSTEM_PROMPT must say the couple is married");
  // Guard against a placeholder prompt sneaking into a deploy.
  assert(SYSTEM_PROMPT.length > 300, "SYSTEM_PROMPT looks like a stub");
});

Deno.test("prompt does not promise a question every day", () => {
  // Questions come from a per-couple queue that only advances once BOTH
  // partners have answered (20260802000003_question_queue.sql), so a question
  // can sit for days. Time-anchored wording ("today's question") goes stale.
  assert(
    !/each day|every day|daily question/i.test(SYSTEM_PROMPT),
    "SYSTEM_PROMPT must not tell the model the question changes daily",
  );
});

Deno.test("prompt requires questions that read for either spouse", () => {
  assert(
    SYSTEM_PROMPT.includes("either spouse"),
    "SYSTEM_PROMPT must require gender-symmetric wording: both partners resolve the same row",
  );
});

Deno.test("prompt states the length bounds the parser enforces", () => {
  assert(
    SYSTEM_PROMPT.includes(String(MAX_QUESTION_LEN)),
    "SYSTEM_PROMPT must tell the model the maximum question length",
  );
  assert(
    SYSTEM_PROMPT.includes(String(MIN_QUESTION_LEN)),
    "SYSTEM_PROMPT must tell the model the minimum question length",
  );
});

Deno.test("logic.ts performs no env lookups", () => {
  // Two guarantees, neither of which a regex over a same-file string literal
  // could give us:
  //
  // 1. Module scope: this test file runs with zero permissions, so if logic.ts
  //    touched Deno.env at import time the suite would already have died with
  //    a NotCapable error before reaching any test body.
  // 2. Call time: swap Deno.env for a booby trap and exercise the only
  //    exported function that runs code.
  const realEnv = Deno.env;
  const trap = new Proxy({} as typeof Deno.env, {
    get() {
      throw new Error("logic.ts must never read Deno.env");
    },
  });

  Object.defineProperty(Deno, "env", { value: trap, configurable: true });
  try {
    parseGenerated({
      questions: [{ question: "What made you smile today?", category: "playful" }],
    });
  } finally {
    Object.defineProperty(Deno, "env", { value: realEnv, configurable: true });
  }

  // Sanity-check that the trap was actually armed -- otherwise the block above
  // would prove nothing.
  assertThrows(
    () => {
      Object.defineProperty(Deno, "env", { value: trap, configurable: true });
      try {
        Deno.env.get("ANTHROPIC_API_KEY");
      } finally {
        Object.defineProperty(Deno, "env", { value: realEnv, configurable: true });
      }
    },
    Error,
    "must never read Deno.env",
  );
});

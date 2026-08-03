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
// Run with (from the repo root):
//   deno test supabase/functions/generate-questions/logic.test.ts

import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  CATEGORIES,
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
  assertThrows(() =>
    parseGenerated({ questions: [{ question: "x", category: "spicy" }] })
  );
});

Deno.test("parseGenerated rejects an empty or blank question", () => {
  assertThrows(() => parseGenerated({ questions: [{ question: "   ", category: "deen" }] }));
  assertThrows(() => parseGenerated({ questions: [{ question: "", category: "deen" }] }));
});

Deno.test("parseGenerated rejects a non-array payload", () => {
  assertThrows(() => parseGenerated({ questions: "nope" }));
  assertThrows(() => parseGenerated({ questions: 42 }));
  assertThrows(() => parseGenerated({ questions: { "0": { question: "x", category: "deen" } } }));
});

Deno.test("parseGenerated rejects null / non-object input", () => {
  assertThrows(() => parseGenerated(null));
  assertThrows(() => parseGenerated(undefined));
  assertThrows(() => parseGenerated("not an object"));
  assertThrows(() => parseGenerated(42));
  assertThrows(() => parseGenerated([{ question: "x", category: "deen" }]));
});

Deno.test("parseGenerated rejects a missing questions key", () => {
  assertThrows(() => parseGenerated({}));
  assertThrows(() => parseGenerated({ items: [{ question: "x", category: "deen" }] }));
});

Deno.test("parseGenerated rejects an empty batch", () => {
  // An empty array is not a successful generation -- surfacing it as an error
  // keeps the caller from reporting "inserted 0" as a healthy top-up.
  assertThrows(() => parseGenerated({ questions: [] }));
});

Deno.test("parseGenerated rejects a non-object array element", () => {
  assertThrows(() => parseGenerated({ questions: ["just a string"] }));
  assertThrows(() => parseGenerated({ questions: [null] }));
  assertThrows(() => parseGenerated({ questions: [["question", "playful"]] }));
});

Deno.test("parseGenerated rejects non-string question / category fields", () => {
  assertThrows(() => parseGenerated({ questions: [{ question: 7, category: "deen" }] }));
  assertThrows(() => parseGenerated({ questions: [{ question: "x", category: 7 }] }));
  assertThrows(() => parseGenerated({ questions: [{ question: "x", category: null }] }));
  assertThrows(() => parseGenerated({ questions: [{ category: "deen" }] }));
  assertThrows(() => parseGenerated({ questions: [{ question: "x" }] }));
});

Deno.test("parseGenerated rejects an absurdly long question", () => {
  assertThrows(() =>
    parseGenerated({ questions: [{ question: "x".repeat(501), category: "playful" }] })
  );
});

Deno.test("parseGenerated rejects the whole batch when any single item is bad", () => {
  // All-or-nothing: a partially bad batch must not be silently truncated.
  assertThrows(() =>
    parseGenerated({
      questions: [
        { question: "What made you smile today?", category: "playful" },
        { question: "What made you smile today?", category: "spicy" },
      ],
    })
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
  assert(SYSTEM_PROMPT.trim().length > 0);
  // Guard against a placeholder prompt sneaking into a deploy.
  assert(SYSTEM_PROMPT.length > 300, "SYSTEM_PROMPT looks like a stub");
});

Deno.test("prompt and schema carry no secrets or env lookups", () => {
  assert(!/sk-|service_role|ANTHROPIC/i.test(SYSTEM_PROMPT));
  assert(!/sk-|service_role|ANTHROPIC/i.test(JSON.stringify(QUESTION_SCHEMA)));
});

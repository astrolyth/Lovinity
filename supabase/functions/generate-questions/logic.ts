// supabase/functions/generate-questions/logic.ts
//
// Pure, network-free, credential-free pieces of the question generator: the
// system prompt, the structured-output JSON schema, and validation of what
// came back from the model. Kept in its own module so logic.test.ts can
// import it without ever touching index.ts's top-level `Deno.serve(...)`
// (which requires --allow-net just to import) -- the same split as
// push-dispatch/logic.ts.
//
// Nothing here reads Deno.env, opens a socket, or knows an API key. The
// caller (index.ts, Task 7) owns the network and the credentials.
//
// Trust note: parseGenerated is a trust boundary. Everything it inspects is
// text a language model produced, so it validates strictly and throws rather
// than coercing or quietly dropping items. Generated rows land with
// status = 'pending' and only enter circulation after a human approves them.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * The category values `public.daily_questions.category` already uses.
 * See supabase/migrations/20260712000002_full_schema.sql:142.
 */
export const CATEGORIES = ["playful", "reflective", "future", "deen"] as const;
export type Category = (typeof CATEGORIES)[number];

export type GeneratedQuestion = { question: string; category: Category };

/**
 * Upper bound on a single generated question. A question the couple can each
 * answer in two or three sentences is short; anything past this is malformed
 * output (a paragraph, a leaked instruction, a runaway generation) rather
 * than something worth queueing for review.
 */
export const MAX_QUESTION_LEN = 500;

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

export const SYSTEM_PROMPT = `
You write the "question of the day" for Lovinity, an app used by married
Muslim couples to stay close. Each day both spouses answer the same question
privately, then see each other's answer.

Write questions that:
- a husband and wife would each answer in two or three sentences, then enjoy
  reading each other's answer
- sit naturally inside an Islamic marriage: warm, affectionate, and modest
- span everyday life, memories, hopes, gratitude, and faith practised together
- assume the couple is already married; never frame anything as dating
- are specific enough to spark a real answer, not "how was your day?"
- are written in plain, everyday English a non-native speaker reads easily

Avoid: anything explicit or physically intimate; anything that presumes
children, wealth, in-laws, or living in the same country; therapy-speak and
clinical language; questions with a single factual answer; questions that
invite comparison, scorekeeping, or criticism of the other spouse; anything
that could start a fight. Do not give rulings on fiqh or quote hadith.

Assign each question exactly one category:
- playful     — light, fun, easy to answer
- reflective  — feelings, memories, or the relationship so far
- future      — hopes, plans, what you are building together
- deen        — faith practised together: worship, character, gratitude to Allah

Vary the categories across a batch, and do not repeat a question you have
already written in the same batch.
`.trim();

// ---------------------------------------------------------------------------
// Structured-output schema
// ---------------------------------------------------------------------------

/**
 * JSON Schema passed as `output_config.format` on the Messages API.
 *
 * Strict by design: `additionalProperties: false` and `required` on both
 * fields, so the model cannot invent an `id`, `status`, or `language` column
 * for us to accidentally forward into the insert.
 *
 * Note: structured outputs do not support array length constraints
 * (minItems/maxItems), so the batch size is requested in the user message and
 * the batch is validated in parseGenerated instead.
 */
export const QUESTION_SCHEMA = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          question: { type: "string" },
          category: { type: "string", enum: [...CATEGORIES] },
        },
        required: ["question", "category"],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false,
} as const;

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate a parsed model response and narrow it to the exact shape we are
 * willing to insert. Throws a plain Error with a human-readable message on
 * anything malformed; the caller turns that into a non-2xx so a bad batch is
 * never written to daily_questions.
 *
 * All-or-nothing: one bad item rejects the whole batch. Silently dropping
 * items would make a degraded generation look like a healthy top-up.
 */
export function parseGenerated(raw: unknown): GeneratedQuestion[] {
  if (!isPlainObject(raw)) {
    throw new Error("generated payload must be a JSON object");
  }

  const questions = raw.questions;
  if (!Array.isArray(questions)) {
    throw new Error("payload.questions is not an array");
  }
  if (questions.length === 0) {
    throw new Error("payload.questions is empty");
  }

  return questions.map((entry, i) => {
    if (!isPlainObject(entry)) {
      throw new Error(`questions[${i}] is not an object`);
    }

    const { question, category } = entry;

    if (typeof question !== "string") {
      throw new Error(`questions[${i}].question is not a string`);
    }
    const trimmed = question.trim();
    if (trimmed.length === 0) {
      throw new Error(`questions[${i}].question is empty`);
    }
    if (trimmed.length > MAX_QUESTION_LEN) {
      throw new Error(
        `questions[${i}].question is longer than ${MAX_QUESTION_LEN} characters`,
      );
    }

    if (typeof category !== "string") {
      throw new Error(`questions[${i}].category is not a string`);
    }
    if (!(CATEGORIES as readonly string[]).includes(category)) {
      throw new Error(
        `questions[${i}].category must be one of ${CATEGORIES.join(", ")}`,
      );
    }

    return { question: trimmed, category: category as Category };
  });
}

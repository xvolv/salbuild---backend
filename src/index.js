import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import rateLimit from "express-rate-limit";

import {
  buildMessages,
  buildExtractTasksMessages,
  buildReflectionMessages,
  normalizeLines,
} from "./reframe.js";
import { groqChatCompletions } from "./groq.js";
import {
  geminiChatCompletion,
  listGeminiModels,
  pickGeminiGenerateContentModel,
} from "./gemini.js";

dotenv.config();

const DEFAULT_GROQ_MODEL = "llama-3.1-8b-instant";
const DEFAULT_GEMINI_MODEL = "gemini-2.5-flash";

const provider = String(
  process.env.AI_PROVIDER || process.env.REFRAME_PROVIDER || "groq",
)
  .trim()
  .toLowerCase();
const model =
  provider === "gemini"
    ? process.env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL
    : process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL;

console.log(`[INIT] AI_PROVIDER env = ${process.env.AI_PROVIDER}`);
console.log(`[INIT] REFRAME_PROVIDER env = ${process.env.REFRAME_PROVIDER}`);
console.log(`[INIT] Provider selected: ${provider}`);
console.log(`[INIT] Model: ${model}`);

if (provider === "groq" && !process.env.GROQ_API_KEY) {
  console.warn("[INIT] WARNING: GROQ_API_KEY is missing!");
}
if (provider === "gemini" && !process.env.GEMINI_API_KEY) {
  console.warn("[INIT] WARNING: GEMINI_API_KEY is missing!");
}

async function runCompletion({ messages, hardMode, maxTokens }) {
  const startTime = Date.now();
  try {
    const hardTimeoutMs = Number(process.env.AI_HARD_TIMEOUT_MS || 55000);
    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error("timeout")), hardTimeoutMs);
    });

    if (provider === "gemini") {
      console.log(`[AI] Calling Gemini (${model})...`);
      try {
        const result = await Promise.race([
          geminiChatCompletion({
            model,
            messages,
            maxTokens,
            temperature: hardMode ? 0.2 : 0.35,
          }),
          timeoutPromise,
        ]);
        console.log(`[AI] Gemini finished in ${Date.now() - startTime}ms`);
        return result;
      } catch (err) {
        const status = Number(err?.status || 0);
        const msg = String(err?.message || "");
        const shouldFallback =
          status === 404 ||
          msg.includes(" is not found ") ||
          msg.includes("NOT_FOUND") ||
          msg.toLowerCase().includes("call listmodels");
        if (shouldFallback) {
          const fallbackModel = await pickGeminiGenerateContentModel();
          if (fallbackModel && model !== fallbackModel) {
            console.log(
              `[AI] Gemini model not found. Retrying with ${fallbackModel}...`,
            );
            const result = await Promise.race([
              geminiChatCompletion({
                model: fallbackModel,
                messages,
                maxTokens,
                temperature: hardMode ? 0.2 : 0.35,
              }),
              timeoutPromise,
            ]);
            console.log(`[AI] Gemini finished in ${Date.now() - startTime}ms`);
            return result;
          }
        }
        throw err;
      }
    }

    console.log(`[AI] Calling Groq (${model})...`);
    const result = await Promise.race([
      groqChatCompletions({
        model,
        messages,
        maxTokens,
        temperature: hardMode ? 0.2 : 0.35,
      }),
      timeoutPromise,
    ]);
    console.log(`[AI] Groq finished in ${Date.now() - startTime}ms`);
    return result;
  } catch (err) {
    if (err.message === "timeout") {
      console.error(`[AI] Timeout after ${Date.now() - startTime}ms`);
      throw new Error("timeout");
    }
    console.error(`[AI] Error after ${Date.now() - startTime}ms:`, err.message);
    throw err;
  }
}

const app = express();

app.disable("x-powered-by");
app.use(cors());
app.use(express.json({ limit: "64kb" }));

// Log all requests
app.use((req, res, next) => {
  console.log(`[REQ] ${req.method} ${req.url}`);
  next();
});

const limiter = rateLimit({
  windowMs: 60_000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
});

app.use("/v1/", limiter);

app.get("/health", (req, res) => {
  res.json({
    ok: true,
    provider,
    model,
    groqKeyPresent: Boolean(process.env.GROQ_API_KEY),
    geminiKeyPresent: Boolean(process.env.GEMINI_API_KEY),
  });
});

app.get("/v1/reframe_debug", async (req, res) => {
  try {
    const messages = buildMessages({ text: "ping", hardMode: true });
    const completion = await runCompletion({
      messages,
      hardMode: true,
      maxTokens: 200,
    });
    const lines = normalizeLines(completion);
    return res.json({
      ok: true,
      provider,
      model,
      lines,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    if (msg.toLowerCase().includes("timeout")) {
      return res.status(504).json({ error: "timeout", message: msg, provider });
    }
    if (
      msg.startsWith("HF error ") ||
      msg.startsWith("Groq error ") ||
      msg.startsWith("Gemini error ")
    ) {
      return res
        .status(502)
        .json({ error: "upstream_error", message: msg, provider });
    }
    return res
      .status(500)
      .json({ error: "server_error", message: msg, provider });
  }
});

app.get("/v1/gemini_models", async (req, res) => {
  try {
    const models = await listGeminiModels();
    const generateContentModels = models
      .filter((m) =>
        Array.isArray(m?.supportedGenerationMethods)
          ? m.supportedGenerationMethods.includes("generateContent")
          : false,
      )
      .map((m) => m.name);

    let picked;
    try {
      picked = await pickGeminiGenerateContentModel();
    } catch {
      picked = undefined;
    }

    return res.json({
      ok: true,
      provider,
      configuredModel: model,
      pickedGenerateContentModel: picked,
      generateContentModels,
      models,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    return res
      .status(500)
      .json({ ok: false, error: "server_error", message: msg });
  }
});

app.post("/v1/reframe_reflect", async (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  console.log(`[${requestId}] Starting reflect request...`);

  try {
    res.setTimeout(60_000);
    const { text, question, hardMode, profileName, profileText } =
      req.body ?? {};

    if (typeof text !== "string" || text.trim().length === 0) {
      return res.status(400).json({ error: "text_required" });
    }
    if (typeof question !== "string" || question.trim().length === 0) {
      return res.status(400).json({ error: "question_required" });
    }
    if (text.length > 1500) {
      return res.status(413).json({ error: "text_too_long" });
    }
    if (question.length > 400) {
      return res.status(413).json({ error: "question_too_long" });
    }

    const messages = buildReflectionMessages({
      text,
      question,
      profileName,
      profileText,
    });
    const completion = await runCompletion({
      messages,
      hardMode: Boolean(hardMode),
      maxTokens: 820,
    });

    const reflection = String(completion || "").trim();
    if (!reflection) {
      return res
        .status(502)
        .json({ error: "upstream_error", message: "empty" });
    }

    // Post-processing: force personalization if model ignored rules
    const name = typeof profileName === "string" ? profileName.trim() : "";
    const profile = typeof profileText === "string" ? profileText.trim() : "";
    let finalReflection = reflection;
    if (name && !finalReflection.startsWith(`${name},`)) {
      finalReflection = `${name}, ${finalReflection}`;
    }
    if (name || profile) {
      if (
        !finalReflection.toLowerCase().includes("builder") &&
        !finalReflection.toLowerCase().includes("execution") &&
        !finalReflection.toLowerCase().includes("control")
      ) {
        finalReflection +=
          " Focus on execution and control: one controllable choice, repeated daily, is how you build.";
      }
    }

    return res.json({
      provider,
      model,
      reflection: finalReflection,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    console.error(`[${requestId}] Reflect failed:`, msg);

    const providerName =
      String(err?.provider || provider || "").trim() || "unknown";
    const status = Number(err?.status || 0);
    const retryAfterSeconds = Number(err?.retryAfterSeconds || 0);
    const isRateLimit =
      status === 429 ||
      msg.toLowerCase().includes("rate limit") ||
      msg.includes(" error 429") ||
      msg.includes(" 429:");
    if (isRateLimit) {
      return res.status(429).json({
        error: "rate_limited",
        provider: providerName,
        retryAfterSeconds:
          Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0
            ? retryAfterSeconds
            : undefined,
      });
    }

    if (msg.toLowerCase().includes("timeout")) {
      return res
        .status(504)
        .json({ error: "timeout", message: "AI provider timed out" });
    }
    if (
      msg.startsWith("HF error ") ||
      msg.startsWith("Groq error ") ||
      msg.startsWith("Gemini error ")
    ) {
      return res.status(502).json({ error: "upstream_error", message: msg });
    }
    return res.status(500).json({ error: "server_error", message: msg });
  }
});

app.post("/v1/extract_tasks", async (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  console.log(`[${requestId}] Starting extract_tasks request...`);

  try {
    res.setTimeout(60_000);
    const { text } = req.body ?? {};

    if (typeof text !== "string" || text.trim().length === 0) {
      return res.status(400).json({ error: "text_required" });
    }
    if (text.length > 12_000) {
      return res.status(413).json({ error: "text_too_long" });
    }

    const messages = buildExtractTasksMessages({ text });
    const completion = await runCompletion({
      messages,
      hardMode: true,
      maxTokens: 420,
    });

    const raw = String(completion || "").trim();
    if (!raw) {
      return res
        .status(502)
        .json({ error: "upstream_error", message: "empty" });
    }

    const cleaned = raw
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/```\s*$/i, "")
      .trim();

    async function parseTasksJsonOrThrow(s) {
      const start = s.indexOf("{");
      const end = s.lastIndexOf("}");
      const candidate = start >= 0 && end > start ? s.slice(start, end + 1) : s;
      return JSON.parse(candidate);
    }

    let parsed;
    try {
      parsed = await parseTasksJsonOrThrow(cleaned);
    } catch (e) {
      // Second-pass repair: ask the model to output strict JSON only.
      const repairMessages = [
        {
          role: "system",
          content:
            "You repair malformed JSON. Return ONLY valid JSON, no markdown, no prose.\n" +
            'Schema: {"tasks":["task 1","task 2"]}.\n' +
            "Rules: tasks must be strings, 1-50 items, no numbering, no brackets like [ ].",
        },
        {
          role: "user",
          content:
            "Convert the following content into valid JSON with the exact schema.\n\nCONTENT:\n" +
            String(raw || "").trim(),
        },
      ];

      const repaired = await runCompletion({
        messages: repairMessages,
        hardMode: true,
        maxTokens: 260,
      });

      const repairedRaw = String(repaired || "").trim();
      const repairedCleaned = repairedRaw
        .replace(/^```json\s*/i, "")
        .replace(/^```\s*/i, "")
        .replace(/```\s*$/i, "")
        .trim();

      try {
        parsed = await parseTasksJsonOrThrow(repairedCleaned);
      } catch (e2) {
        const rawSnippet = raw.length > 400 ? raw.slice(0, 400) : raw;
        const repairedSnippet =
          repairedRaw.length > 400 ? repairedRaw.slice(0, 400) : repairedRaw;
        return res.status(502).json({
          error: "upstream_error",
          message: "invalid_json",
          details: {
            parseError: String(e?.message || ""),
            repairParseError: String(e2?.message || ""),
            rawSnippet,
            repairedSnippet,
          },
        });
      }
    }

    const tasksRaw = parsed?.tasks;
    const tasks = Array.isArray(tasksRaw)
      ? tasksRaw
          .map((t) => String(t || "").trim())
          .filter((t) => t.length > 0)
          .slice(0, 50)
      : [];

    if (tasks.length === 0) {
      return res.status(502).json({
        error: "upstream_error",
        message: "no_tasks",
        raw,
      });
    }

    return res.json({ tasks });
  } catch (err) {
    const msg = String(err?.message || "");
    console.error(`[${requestId}] extract_tasks failed:`, msg);

    const providerName =
      String(err?.provider || provider || "").trim() || "unknown";
    const status = Number(err?.status || 0);
    const retryAfterSeconds = Number(err?.retryAfterSeconds || 0);
    const isRateLimit =
      status === 429 ||
      msg.toLowerCase().includes("rate limit") ||
      msg.includes(" error 429") ||
      msg.includes(" 429:");
    if (isRateLimit) {
      return res.status(429).json({
        error: "rate_limited",
        provider: providerName,
        retryAfterSeconds:
          Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0
            ? retryAfterSeconds
            : undefined,
      });
    }

    if (msg.toLowerCase().includes("timeout")) {
      return res
        .status(504)
        .json({ error: "timeout", message: "AI provider timed out" });
    }
    if (
      msg.startsWith("HF error ") ||
      msg.startsWith("Groq error ") ||
      msg.startsWith("Gemini error ")
    ) {
      return res.status(502).json({ error: "upstream_error", message: msg });
    }
    return res.status(500).json({ error: "server_error", message: msg });
  }
});

app.post("/v1/reframe", async (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  console.log(`[${requestId}] Starting reframe request...`);

  try {
    res.setTimeout(60_000); // Backend timeout
    const { text, hardMode, profileName, profileText } = req.body ?? {};

    if (typeof text !== "string" || text.trim().length === 0) {
      console.log(`[${requestId}] Error: text_required`);
      return res.status(400).json({ error: "text_required" });
    }

    console.log(
      `[${requestId}] Text length: ${text.length}, Hard mode: ${hardMode}`,
    );

    const messages = buildMessages({
      text,
      hardMode: Boolean(hardMode),
      profileName,
      profileText,
    });

    const completion = await runCompletion({
      messages,
      hardMode: Boolean(hardMode),
      maxTokens: 320,
    });

    const lines = normalizeLines(completion);

    const name = typeof profileName === "string" ? profileName.trim() : "";
    const profile = typeof profileText === "string" ? profileText.trim() : "";

    // Force single-question output: choose best question candidate and place it into line 4.
    // This makes the UI show exactly one line while keeping API backward-compatible.
    const nonEmpty = lines
      .map((l) => String(l || "").trim())
      .filter((l) => l.length > 0);

    const isBannedTemplate = (s) =>
      String(s || "")
        .toLowerCase()
        .startsWith("what exactly will you do today about");

    const nonBanned = nonEmpty.filter(
      (l) => !isBannedTemplate(l.replace(/^"+|"+$/g, "").trim()),
    );
    const modelCandidate =
      nonBanned.find((l) => l.includes("?")) ||
      nonBanned.find((l) => l.startsWith('"') && l.endsWith('"')) ||
      nonBanned[nonBanned.length - 1] ||
      '"What specific next step restores control right now?"';

    const questionCandidate = modelCandidate;

    lines[0] = "";
    lines[1] = "";
    lines[2] = "";
    lines[3] = questionCandidate;

    // Post-processing: force personalization on the question if model ignored rules.
    if (lines.length >= 4) {
      const raw = String(lines[3] || "").trim();
      const unquoted = raw.replace(/^"+|"+$/g, "").trim();
      let q = unquoted;

      // Guard: if a banned template slipped through, replace it with a safer generic question.
      if (isBannedTemplate(q)) {
        q = "What is the smallest concrete target you will commit to today?";
      }

      if (name && !q.toLowerCase().startsWith(`${name.toLowerCase()},`)) {
        q = `${name}, ${q}`;
      }

      const qLower = q.toLowerCase();
      const hasGoalAnchor =
        qLower.includes("builder") ||
        qLower.includes("execution") ||
        qLower.includes("control");
      if (!hasGoalAnchor && (name || profile)) {
        q = `${q.replace(/\?+\s*$/, "")} as a builder?`;
      }

      if (!q.trim().endsWith("?")) {
        q = `${q.trim()}?`;
      }

      lines[3] = `"${q.replace(/"/g, "").trim()}"`;
    }
    console.log(`[${requestId}] Success: generated ${lines.length} lines`);

    return res.json({
      provider,
      model,
      lines,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    console.error(`[${requestId}] Request failed:`, msg);

    const providerName =
      String(err?.provider || provider || "").trim() || "unknown";
    const status = Number(err?.status || 0);
    const retryAfterSeconds = Number(err?.retryAfterSeconds || 0);
    const isRateLimit =
      status === 429 ||
      msg.toLowerCase().includes("rate limit") ||
      msg.includes(" error 429") ||
      msg.includes(" 429:");
    if (isRateLimit) {
      return res.status(429).json({
        error: "rate_limited",
        provider: providerName,
        retryAfterSeconds:
          Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0
            ? retryAfterSeconds
            : undefined,
      });
    }

    if (msg.toLowerCase().includes("timeout")) {
      return res
        .status(504)
        .json({ error: "timeout", message: "AI provider timed out" });
    }
    if (
      msg.startsWith("HF error ") ||
      msg.startsWith("Groq error ") ||
      msg.startsWith("Gemini error ")
    ) {
      return res.status(502).json({ error: "upstream_error", message: msg });
    }
    return res.status(500).json({ error: "server_error", message: msg });
  }
});

const port = Number(process.env.PORT || 3000);
app.listen(port, "0.0.0.0", () => {
  console.log(`reframe-backend listening on :${port}`);
});

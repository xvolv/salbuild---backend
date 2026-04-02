import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import rateLimit from "express-rate-limit";

import {
  buildMessages,
  buildReflectionMessages,
  normalizeLines,
} from "./reframe.js";
import { groqChatCompletions } from "./groq.js";

dotenv.config();

const DEFAULT_GROQ_MODEL = "llama-3.1-8b-instant";

console.log(`[INIT] REFRAME_PROVIDER env = ${process.env.REFRAME_PROVIDER}`);
const provider = "groq";
console.log(`[INIT] Provider forced to: ${provider}`);
console.log(
  `[INIT] Groq model: ${process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL}`,
);

if (!process.env.GROQ_API_KEY) {
  console.warn("[INIT] WARNING: GROQ_API_KEY is missing!");
}

const model = process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL;

async function runCompletion({ messages, hardMode, maxTokens }) {
  const startTime = Date.now();
  try {
    const hardTimeoutMs = Number(process.env.AI_HARD_TIMEOUT_MS || 55000);
    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error("timeout")), hardTimeoutMs);
    });

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
app.use(express.json({ limit: "8kb" }));

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
    model:
      provider === "groq"
        ? process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL
        : process.env.HF_MODEL || DEFAULT_HF_MODEL,
  });
});

app.get("/v1/reframe_debug", async (req, res) => {
  try {
    const messages = buildMessages({ text: "ping", hardMode: true });
    const completion = await runCompletion({
      messages,
      hardMode: true,
      maxTokens: 64,
    });
    const lines = normalizeLines(completion);
    return res.json({
      ok: true,
      provider,
      model:
        provider === "groq"
          ? process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL
          : process.env.HF_MODEL || DEFAULT_HF_MODEL,
      lines,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    if (msg.toLowerCase().includes("timeout")) {
      return res.status(504).json({ error: "timeout", message: msg, provider });
    }
    if (msg.startsWith("HF error ") || msg.startsWith("Groq error ")) {
      return res
        .status(502)
        .json({ error: "upstream_error", message: msg, provider });
    }
    return res
      .status(500)
      .json({ error: "server_error", message: msg, provider });
  }
});

app.post("/v1/reframe_reflect", async (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  console.log(`[${requestId}] Starting reflect request...`);

  try {
    res.setTimeout(60_000);
    const { text, question, hardMode } = req.body ?? {};

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

    const messages = buildReflectionMessages({ text, question });
    const completion = await runCompletion({
      messages,
      hardMode: Boolean(hardMode),
      maxTokens: 240,
    });

    const reflection = String(completion || "").trim();
    if (!reflection) {
      return res
        .status(502)
        .json({ error: "upstream_error", message: "empty" });
    }

    return res.json({
      provider,
      model:
        provider === "groq"
          ? process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL
          : process.env.HF_MODEL || DEFAULT_HF_MODEL,
      reflection,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    console.error(`[${requestId}] Reflect failed:`, msg);

    if (msg.toLowerCase().includes("timeout")) {
      return res
        .status(504)
        .json({ error: "timeout", message: "AI provider timed out" });
    }
    if (msg.startsWith("HF error ") || msg.startsWith("Groq error ")) {
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
    const { text, hardMode } = req.body ?? {};

    if (typeof text !== "string" || text.trim().length === 0) {
      console.log(`[${requestId}] Error: text_required`);
      return res.status(400).json({ error: "text_required" });
    }

    console.log(
      `[${requestId}] Text length: ${text.length}, Hard mode: ${hardMode}`,
    );

    const messages = buildMessages({ text, hardMode: Boolean(hardMode) });

    const completion = await runCompletion({
      messages,
      hardMode: Boolean(hardMode),
      maxTokens: 200,
    });

    const lines = normalizeLines(completion);
    console.log(`[${requestId}] Success: generated ${lines.length} lines`);

    return res.json({
      provider,
      model:
        provider === "groq"
          ? process.env.GROQ_MODEL || DEFAULT_GROQ_MODEL
          : process.env.HF_MODEL || DEFAULT_HF_MODEL,
      lines,
    });
  } catch (err) {
    const msg = String(err?.message || "");
    console.error(`[${requestId}] Request failed:`, msg);

    if (msg.toLowerCase().includes("timeout")) {
      return res
        .status(504)
        .json({ error: "timeout", message: "AI provider timed out" });
    }
    if (msg.startsWith("HF error ") || msg.startsWith("Groq error ")) {
      return res.status(502).json({ error: "upstream_error", message: msg });
    }
    return res.status(500).json({ error: "server_error", message: msg });
  }
});

const port = Number(process.env.PORT || 3000);
app.listen(port, "0.0.0.0", () => {
  console.log(`reframe-backend listening on :${port}`);
});

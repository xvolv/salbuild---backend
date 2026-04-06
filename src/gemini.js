const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

function normalizeGeminiModelName(model) {
  const m = String(model || "").trim();
  if (!m) return "";
  return m.startsWith("models/") ? m.slice("models/".length) : m;
}

function getGeminiUrl(model) {
  const mRaw = String(model || "").trim() || "gemini-1.5-flash";
  const m = normalizeGeminiModelName(mRaw) || "gemini-1.5-flash";
  return `${GEMINI_API_BASE}/${encodeURIComponent(m)}:generateContent`;
}

export async function pickGeminiGenerateContentModel() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY missing");
  }

  let resp;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`,
      {
        method: "GET",
        headers: { "content-type": "application/json" },
      },
    );
  } catch (e) {
    const cause = String(e?.cause?.message || e?.cause || e?.message || e);
    const err = new Error(`Gemini list models fetch failed: ${cause}`);
    err.provider = "gemini";
    err.status = 0;
    throw err;
  }

  if (!resp.ok) {
    const text = await resp.text();
    const err = new Error(`Gemini list models error ${resp.status}: ${text}`);
    err.provider = "gemini";
    err.status = resp.status;
    throw err;
  }

  const data = await resp.json();
  const models = Array.isArray(data?.models) ? data.models : [];
  const supported = models
    .filter((m) =>
      Array.isArray(m?.supportedGenerationMethods)
        ? m.supportedGenerationMethods.includes("generateContent")
        : false,
    )
    .map((m) => String(m?.name || "").trim())
    .filter((n) => n.length > 0);

  if (supported.length === 0) {
    throw new Error(
      "No Gemini models support generateContent for this API key",
    );
  }

  const preferredOrder = [
    "models/gemini-2.5-flash",
    "models/gemini-2.5-pro",
    "models/gemini-2.0-flash",
    "models/gemini-2.0-flash-001",
    "models/gemini-flash-latest",
    "models/gemini-1.5-flash",
    "models/gemini-1.5-flash-latest",
    "models/gemini-1.5-pro",
    "models/gemini-1.5-pro-latest",
    "models/gemini-pro",
  ];

  const preferred = preferredOrder.find((p) => supported.includes(p));
  const picked = preferred || supported[0];
  return normalizeGeminiModelName(picked) || "gemini-1.5-flash";
}

export async function listGeminiModels() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY missing");
  }

  let resp;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`,
      {
        method: "GET",
        headers: { "content-type": "application/json" },
      },
    );
  } catch (e) {
    const cause = String(e?.cause?.message || e?.cause || e?.message || e);
    const err = new Error(`Gemini list models fetch failed: ${cause}`);
    err.provider = "gemini";
    err.status = 0;
    throw err;
  }

  if (!resp.ok) {
    const text = await resp.text();
    const err = new Error(`Gemini list models error ${resp.status}: ${text}`);
    err.provider = "gemini";
    err.status = resp.status;
    throw err;
  }

  const data = await resp.json();
  const models = Array.isArray(data?.models) ? data.models : [];

  return models.map((m) => ({
    name: String(m?.name || "").trim(),
    supportedGenerationMethods: Array.isArray(m?.supportedGenerationMethods)
      ? m.supportedGenerationMethods
      : [],
  }));
}

export async function geminiChatCompletion({
  model = "gemini-1.5-flash",
  messages,
  maxTokens,
  temperature,
}) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY missing");
  }

  const controller = new AbortController();
  const timeoutMs = Number(process.env.GEMINI_TIMEOUT_MS || 25000);
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let resp;
  try {
    const contents = messages.map((msg) => ({
      role: msg.role === "user" ? "user" : "model",
      parts: [{ text: msg.content }],
    }));

    const body = JSON.stringify({
      contents,
      generationConfig: {
        temperature,
        maxOutputTokens: maxTokens,
      },
    });

    try {
      resp = await fetch(
        `${getGeminiUrl(model)}?key=${encodeURIComponent(apiKey)}`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
          },
          body,
          signal: controller.signal,
        },
      );
    } catch (e) {
      const cause = String(e?.cause?.message || e?.cause || e?.message || e);
      const err = new Error(`Gemini fetch failed: ${cause}`);
      err.provider = "gemini";
      err.status = 0;
      throw err;
    }
  } catch (e) {
    if (e?.name === "AbortError") {
      throw new Error("Gemini timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!resp.ok) {
    const text = await resp.text();
    const err = new Error(`Gemini error ${resp.status}: ${text}`);
    err.provider = "gemini";
    err.status = resp.status;
    const retryAfter = resp.headers?.get?.("retry-after");
    if (retryAfter != null && String(retryAfter).trim().length > 0) {
      const n = Number(retryAfter);
      if (Number.isFinite(n) && n > 0) {
        err.retryAfterSeconds = n;
      }
    }
    throw err;
  }

  const data = await resp.json();
  const candidate = data?.candidates?.[0];
  const parts = candidate?.content?.parts;
  const finishReason = candidate?.finishReason;
  const safetyRatings = candidate?.safetyRatings;

  let content = "";
  if (Array.isArray(parts)) {
    content = parts
      .map((p) => (typeof p?.text === "string" ? p.text : ""))
      .join("")
      .trim();
  }

  if (content.length === 0) {
    const details = {
      finishReason,
      hasCandidate: Boolean(candidate),
      hasParts: Array.isArray(parts),
      safetyRatings,
    };
    const err = new Error(
      `Bad Gemini response: no text content. details=${JSON.stringify(details)}`,
    );
    err.provider = "gemini";
    err.status = 502;
    throw err;
  }

  return content;
}

const GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions";

export async function groqChatCompletions({
  model,
  messages,
  maxTokens,
  temperature,
  jsonOnly,
}) {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    throw new Error("GROQ_API_KEY missing");
  }

  const controller = new AbortController();
  const timeoutMs = Number(process.env.GROQ_TIMEOUT_MS || 20000);
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let resp;
  try {
    resp = await fetch(GROQ_API_URL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages,
        max_tokens: maxTokens,
        temperature,
        ...(jsonOnly ? { response_format: { type: "json_object" } } : {}),
      }),
      signal: controller.signal,
    });
  } catch (e) {
    if (e?.name === "AbortError") {
      throw new Error("Groq timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!resp.ok) {
    const text = await resp.text();
    const err = new Error(`Groq error ${resp.status}: ${text}`);
    err.provider = "groq";
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
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.trim().length === 0) {
    throw new Error("Bad Groq response");
  }

  return content;
}

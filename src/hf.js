const HF_API_URL = "https://router.huggingface.co/v1/chat/completions";

function getHfModelsUrl(model) {
  return `https://api-inference.huggingface.co/models/${encodeURIComponent(model)}`;
}

export async function hfChatCompletions({
  model,
  messages,
  maxTokens,
  temperature,
  provider,
}) {
  const token = process.env.HF_API_TOKEN;
  if (!token) {
    throw new Error("HF_API_TOKEN missing");
  }

  const controller = new AbortController();
  const timeoutMs = Number(process.env.HF_TIMEOUT_MS || 20000);
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let resp;
  try {
    resp = await fetch(HF_API_URL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages,
        max_tokens: maxTokens,
        temperature,
        ...(provider ? { provider } : {}),
      }),
      signal: controller.signal,
    });
  } catch (e) {
    if (e?.name === "AbortError") {
      throw new Error("HF timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`HF error ${resp.status}: ${text}`);
  }

  const data = await resp.json();
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.trim().length === 0) {
    throw new Error("Bad HF response");
  }
  return content;
}

export async function hfTextGeneration({
  model,
  prompt,
  maxNewTokens,
  temperature,
}) {
  const token = process.env.HF_API_TOKEN;
  if (!token) {
    throw new Error("HF_API_TOKEN missing");
  }

  const controller = new AbortController();
  const timeoutMs = Number(process.env.HF_TIMEOUT_MS || 20000);
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let resp;
  try {
    resp = await fetch(getHfModelsUrl(model), {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        inputs: prompt,
        parameters: {
          max_new_tokens: maxNewTokens,
          temperature,
          return_full_text: false,
        },
      }),
      signal: controller.signal,
    });
  } catch (e) {
    if (e?.name === "AbortError") {
      throw new Error("HF timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`HF error ${resp.status}: ${text}`);
  }

  const data = await resp.json();
  const first = Array.isArray(data) ? data[0] : data;
  const generatedText = first?.generated_text;
  if (typeof generatedText !== "string" || generatedText.trim().length === 0) {
    throw new Error("Bad HF response");
  }
  return generatedText;
}

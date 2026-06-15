import Anthropic from "@anthropic-ai/sdk";

// The top Claude writing model. Adaptive thinking is enabled on every call so
// Claude decides how much to reason per task.
export const WRITING_MODEL = "claude-opus-4-8";

let client: Anthropic | null = null;

export function getAnthropic(): Anthropic {
  if (!process.env.ANTHROPIC_API_KEY) {
    throw new Error(
      "ANTHROPIC_API_KEY is not set. Add it to your .env file (see .env.example)."
    );
  }
  if (!client) {
    client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }
  return client;
}

interface CompleteOptions {
  system: string;
  user: string;
  maxTokens?: number;
}

/**
 * Run a single completion against the writing model and return the text.
 * Streams under the hood so large/slow responses don't hit request timeouts,
 * then collects the final message.
 */
export async function complete({
  system,
  user,
  maxTokens = 8000,
}: CompleteOptions): Promise<string> {
  const anthropic = getAnthropic();

  const stream = anthropic.messages.stream({
    model: WRITING_MODEL,
    max_tokens: maxTokens,
    thinking: { type: "adaptive" },
    system,
    messages: [{ role: "user", content: user }],
  });

  const message = await stream.finalMessage();

  return message.content
    .filter((block): block is Anthropic.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("\n")
    .trim();
}

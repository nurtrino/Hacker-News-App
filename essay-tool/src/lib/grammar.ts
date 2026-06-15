import { complete } from "./anthropic";
import { GRAMMAR_CLAUDE_SYSTEM } from "./prompts";

export interface LanguageToolMatch {
  message: string;
  shortMessage: string;
  offset: number;
  length: number;
  context: string;
  replacements: string[];
  ruleId: string;
  category: string;
}

const LT_URL =
  process.env.LANGUAGETOOL_URL || "https://api.languagetool.org/v2/check";

/**
 * Run the essay through LanguageTool (mechanics: spelling, grammar, punctuation).
 * Returns a normalized list of matches. Throws on network failure so the caller
 * can surface a useful message.
 */
export async function runLanguageTool(
  text: string
): Promise<LanguageToolMatch[]> {
  const body = new URLSearchParams({
    text,
    language: "en-US",
    level: "picky",
  });

  const res = await fetch(LT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  if (!res.ok) {
    throw new Error(`LanguageTool returned ${res.status}`);
  }

  const data = (await res.json()) as {
    matches?: Array<{
      message: string;
      shortMessage?: string;
      offset: number;
      length: number;
      context?: { text: string };
      replacements?: Array<{ value: string }>;
      rule?: { id: string; category?: { name?: string } };
    }>;
  };

  return (data.matches ?? []).map((m) => ({
    message: m.message,
    shortMessage: m.shortMessage ?? "",
    offset: m.offset,
    length: m.length,
    context: m.context?.text ?? "",
    replacements: (m.replacements ?? []).slice(0, 5).map((r) => r.value),
    ruleId: m.rule?.id ?? "",
    category: m.rule?.category?.name ?? "",
  }));
}

/** Run the Claude style/clarity proofreading pass. Returns markdown. */
export async function runClaudeGrammar(text: string): Promise<string> {
  return complete({
    system: GRAMMAR_CLAUDE_SYSTEM,
    user: `Here is the essay to proofread:\n\n${text}`,
    maxTokens: 4000,
  });
}

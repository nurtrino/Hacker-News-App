"use client";

import Markdown from "./Markdown";

export interface Critique {
  id: string;
  critic: string;
  criticName: string;
  content: string;
}

export interface GrammarReport {
  id: string;
  source: string;
  content: string;
}

interface LTMatch {
  message: string;
  shortMessage: string;
  context: string;
  replacements: string[];
  category: string;
}

function LanguageToolReport({ content }: { content: string }) {
  let parsed: LTMatch[] | { error: string };
  try {
    parsed = JSON.parse(content);
  } catch {
    return <p className="text-sm text-stone-500">Could not read grammar results.</p>;
  }

  if (!Array.isArray(parsed)) {
    return (
      <p className="text-sm text-red-600">
        LanguageTool unavailable: {parsed.error}
      </p>
    );
  }

  if (parsed.length === 0) {
    return (
      <p className="text-sm text-green-700">
        No spelling, grammar, or punctuation issues found. ✓
      </p>
    );
  }

  return (
    <ul className="space-y-3">
      {parsed.map((m, i) => (
        <li key={i} className="rounded-lg bg-stone-50 p-3 text-sm">
          <p className="font-medium text-stone-800">{m.message}</p>
          {m.context && (
            <p className="mt-1 font-mono text-xs text-stone-500">…{m.context}…</p>
          )}
          {m.replacements.length > 0 && (
            <p className="mt-1 text-xs text-stone-600">
              Suggestions:{" "}
              <span className="font-medium">{m.replacements.join(", ")}</span>
            </p>
          )}
        </li>
      ))}
    </ul>
  );
}

const CRITIC_TINT: Record<string, string> = {
  community_fit: "border-l-emerald-400",
  admissions_reader: "border-l-sky-400",
  skeptic: "border-l-rose-400",
  ai_tells: "border-l-violet-400",
};

export default function ReviewPanel({
  critiques,
  grammarReports,
}: {
  critiques: Critique[];
  grammarReports: GrammarReport[];
}) {
  const claude = grammarReports.find((g) => g.source === "CLAUDE");
  const lt = grammarReports.find((g) => g.source === "LANGUAGETOOL");

  if (critiques.length === 0 && grammarReports.length === 0) {
    return (
      <p className="text-sm text-stone-400">
        No feedback yet for this draft. Send it to the Council or run a grammar
        check.
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {critiques.length > 0 && (
        <div className="space-y-4">
          <div>
            <h3 className="font-serif text-lg font-semibold">The Council</h3>
            <p className="text-xs text-stone-400">
              Reviewed in order — each member saw the earlier notes.
            </p>
          </div>
          {critiques.map((c, i) => (
            <div
              key={c.id}
              className={`rounded-xl border border-stone-200 border-l-4 bg-white p-4 ${
                CRITIC_TINT[c.critic] ?? "border-l-stone-300"
              }`}
            >
              <h4 className="font-semibold">
                {i + 1}. {c.criticName}
              </h4>
              <div className="mt-2 text-sm text-stone-700">
                <Markdown text={c.content} />
              </div>
            </div>
          ))}
        </div>
      )}

      {grammarReports.length > 0 && (
        <div className="space-y-4">
          <h3 className="font-serif text-lg font-semibold">Grammar & polish</h3>
          {lt && (
            <div className="rounded-xl border border-stone-200 bg-white p-4">
              <h4 className="font-semibold">LanguageTool (mechanics)</h4>
              <div className="mt-2">
                <LanguageToolReport content={lt.content} />
              </div>
            </div>
          )}
          {claude && (
            <div className="rounded-xl border border-stone-200 bg-white p-4">
              <h4 className="font-semibold">Claude (style & clarity)</h4>
              <div className="mt-2 text-sm text-stone-700">
                <Markdown text={claude.content} />
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

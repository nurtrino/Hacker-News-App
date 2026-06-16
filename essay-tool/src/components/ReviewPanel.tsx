"use client";

import Markdown from "./Markdown";

export interface Suggestion {
  id: string;
  original: string;
  replacement: string;
  reason: string;
  status: string; // PENDING | ACCEPTED | REJECTED | STALE
}

export interface Critique {
  id: string;
  critic: string;
  criticName: string;
  content: string;
  suggestions: Suggestion[];
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

function SuggestionCard({
  s,
  onApply,
  applying,
  disabled,
}: {
  s: Suggestion;
  onApply?: (suggestionId: string, accept: boolean) => void;
  applying: boolean;
  disabled: boolean;
}) {
  const tone =
    s.status === "ACCEPTED"
      ? "border-green-200 bg-green-50"
      : s.status === "REJECTED"
      ? "border-stone-200 bg-stone-50 opacity-60"
      : s.status === "STALE"
      ? "border-amber-300 bg-amber-50"
      : "border-stone-200 bg-stone-50";

  return (
    <div className={`rounded-lg border p-3 text-sm ${tone}`}>
      <p className="leading-relaxed">
        <span className="rounded bg-red-100 px-1 text-red-800 line-through">
          {s.original}
        </span>{" "}
        →{" "}
        {s.replacement ? (
          <span className="rounded bg-green-100 px-1 text-green-900">
            {s.replacement}
          </span>
        ) : (
          <span className="italic text-stone-500">(delete)</span>
        )}
      </p>
      {s.reason && <p className="mt-1 text-xs text-stone-500">{s.reason}</p>}
      <div className="mt-2">
        {s.status === "ACCEPTED" ? (
          <span className="text-xs font-medium text-green-700">✓ Accepted</span>
        ) : s.status === "REJECTED" ? (
          <span className="text-xs text-stone-400">Rejected</span>
        ) : s.status === "STALE" ? (
          <span className="text-xs text-amber-700">
            Couldn&apos;t apply — the text changed
          </span>
        ) : (
          <div className="flex gap-2">
            <button
              onClick={() => onApply?.(s.id, true)}
              disabled={disabled}
              className="rounded bg-ink px-2.5 py-1 text-xs font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
            >
              {applying ? "Applying…" : "Accept"}
            </button>
            <button
              onClick={() => onApply?.(s.id, false)}
              disabled={disabled}
              className="rounded border border-stone-300 px-2.5 py-1 text-xs font-medium text-stone-600 transition hover:border-stone-400 disabled:opacity-40"
            >
              Reject
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

export default function ReviewPanel({
  critiques,
  grammarReports,
  onApply,
  onAcceptAll,
  applyingId,
}: {
  critiques: Critique[];
  grammarReports: GrammarReport[];
  onApply?: (suggestionId: string, accept: boolean) => void;
  onAcceptAll?: () => void;
  applyingId?: string | null;
}) {
  const claude = grammarReports.find((g) => g.source === "CLAUDE");
  const lt = grammarReports.find((g) => g.source === "LANGUAGETOOL");

  const pendingCount = critiques.reduce(
    (n, c) => n + c.suggestions.filter((s) => s.status === "PENDING").length,
    0
  );
  const busy = applyingId != null;

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
          <div className="flex items-start justify-between gap-3">
            <div>
              <h3 className="font-serif text-lg font-semibold">The Council</h3>
              <p className="text-xs text-stone-400">
                Reviewed in order — each member saw the earlier notes.
              </p>
            </div>
            {pendingCount > 0 && onAcceptAll && (
              <button
                onClick={onAcceptAll}
                disabled={busy}
                className="shrink-0 rounded-lg bg-ink px-3 py-1.5 text-xs font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
              >
                {applyingId === "ALL"
                  ? "Applying…"
                  : `Accept all ${pendingCount} edits`}
              </button>
            )}
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
              {c.suggestions.length > 0 && (
                <div className="mt-3 space-y-2">
                  <p className="text-xs font-semibold uppercase tracking-wide text-stone-400">
                    Proposed edits
                  </p>
                  {c.suggestions.map((s) => (
                    <SuggestionCard
                      key={s.id}
                      s={s}
                      onApply={onApply}
                      applying={applyingId === s.id}
                      disabled={busy}
                    />
                  ))}
                </div>
              )}
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

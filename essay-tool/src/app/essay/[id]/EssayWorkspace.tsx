"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { COMMON_APP_PROMPTS } from "@/lib/prompts";
import ReviewPanel, {
  type Critique,
  type GrammarReport,
} from "@/components/ReviewPanel";
import DraftDiff from "@/components/DraftDiff";

interface Revision {
  id: string;
  round: number;
  content: string;
  critiques: Critique[];
  grammarReports: GrammarReport[];
}

interface Essay {
  id: string;
  title: string;
  topic: string;
  outline: string;
  draft: string;
  stage: string;
  promptId: string | null;
  revisions: Revision[];
}

type Stage = "OUTLINE" | "DRAFT" | "EDIT";

const STAGES: { key: Stage; label: string }[] = [
  { key: "OUTLINE", label: "1 · Outline" },
  { key: "DRAFT", label: "2 · Draft & Council" },
  { key: "EDIT", label: "3 · Edit" },
];

function wordCount(text: string): number {
  const t = text.trim();
  return t ? t.split(/\s+/).length : 0;
}

export default function EssayWorkspace({ initialEssay }: { initialEssay: Essay }) {
  const [title, setTitle] = useState(initialEssay.title);
  const [topic, setTopic] = useState(initialEssay.topic);
  const [outline, setOutline] = useState(initialEssay.outline);
  const [draft, setDraft] = useState(initialEssay.draft);
  const [promptId, setPromptId] = useState<string | null>(initialEssay.promptId);
  const [stage, setStage] = useState<Stage>((initialEssay.stage as Stage) || "OUTLINE");
  const [revisions, setRevisions] = useState<Revision[]>(initialEssay.revisions);

  const [saveState, setSaveState] = useState<"idle" | "saving" | "saved">("idle");
  const [busy, setBusy] = useState<
    null | "outline" | "draft" | "council" | "grammar" | "writer"
  >(null);
  const [error, setError] = useState("");

  // The Writer's proposed revision (not yet accepted into the draft).
  const [writerNotes, setWriterNotes] = useState("");
  const [proposal, setProposal] = useState<string | null>(null);

  const id = initialEssay.id;
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const latest = revisions[0] ?? null;

  // --- persistence ---------------------------------------------------------

  const persist = useCallback(
    async (data: Record<string, unknown>) => {
      setSaveState("saving");
      await fetch(`/api/essays/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      setSaveState("saved");
    },
    [id]
  );

  // Debounced autosave for the text fields.
  const queueSave = useCallback(
    (data: Record<string, unknown>) => {
      setSaveState("saving");
      if (saveTimer.current) clearTimeout(saveTimer.current);
      saveTimer.current = setTimeout(() => persist(data), 700);
    },
    [persist]
  );

  async function refreshRevisions() {
    const res = await fetch(`/api/essays/${id}`);
    if (res.ok) {
      const { essay } = await res.json();
      setRevisions(essay.revisions);
      setDraft(essay.draft);
    }
  }

  // --- AI actions ----------------------------------------------------------

  async function generateOutline() {
    setError("");
    setBusy("outline");
    const res = await fetch(`/api/essays/${id}/outline`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ topic, promptId }),
    });
    setBusy(null);
    const data = await res.json();
    if (res.ok) setOutline(data.outline);
    else setError(data.error ?? "Something went wrong.");
  }

  async function generateDraft() {
    if (!promptId) {
      setError("Choose a Common App prompt first.");
      return;
    }
    setError("");
    setBusy("draft");
    await persist({ outline, promptId });
    const res = await fetch(`/api/essays/${id}/draft`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ promptId }),
    });
    setBusy(null);
    const data = await res.json();
    if (res.ok) {
      setDraft(data.draft);
      setStage("DRAFT");
    } else setError(data.error ?? "Something went wrong.");
  }

  async function sendToCouncil() {
    setError("");
    setBusy("council");
    const res = await fetch(`/api/essays/${id}/council`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ draft }),
    });
    const data = await res.json();
    setBusy(null);
    if (res.ok) await refreshRevisions();
    else setError(data.error ?? "The Council failed to respond.");
  }

  async function runGrammar() {
    setError("");
    setBusy("grammar");
    const res = await fetch(`/api/essays/${id}/grammar`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ draft }),
    });
    const data = await res.json();
    setBusy(null);
    if (res.ok) await refreshRevisions();
    else setError(data.error ?? "Grammar check failed.");
  }

  async function reviseWithWriter(applyCouncil: boolean) {
    setError("");
    setBusy("writer");
    const res = await fetch(`/api/essays/${id}/writer`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ draft, notes: writerNotes, applyCouncil }),
    });
    const data = await res.json();
    setBusy(null);
    if (res.ok) setProposal(data.proposal);
    else setError(data.error ?? "The writer failed to respond.");
  }

  async function acceptProposal() {
    if (proposal === null) return;
    setDraft(proposal);
    await persist({ draft: proposal });
    setProposal(null);
    setWriterNotes("");
  }

  function discardProposal() {
    setProposal(null);
  }

  function goToStage(next: Stage) {
    setStage(next);
    persist({ stage: next });
  }

  const words = useMemo(() => wordCount(draft), [draft]);

  // --- render --------------------------------------------------------------

  return (
    <main className="mx-auto max-w-6xl px-6 py-8">
      {/* Header */}
      <div className="flex items-center justify-between gap-4">
        <Link href="/" className="text-sm text-stone-400 hover:text-stone-700">
          ← All essays
        </Link>
        <span className="text-xs text-stone-400">
          {saveState === "saving" ? "Saving…" : saveState === "saved" ? "Saved" : ""}
        </span>
      </div>

      <input
        value={title}
        onChange={(e) => {
          setTitle(e.target.value);
          queueSave({ title: e.target.value });
        }}
        className="mt-3 w-full bg-transparent font-serif text-3xl font-bold outline-none"
        placeholder="Untitled Personal Statement"
      />

      {/* Stage stepper */}
      <nav className="mt-6 flex gap-1 rounded-xl border border-stone-200 bg-white p-1">
        {STAGES.map((s) => (
          <button
            key={s.key}
            onClick={() => goToStage(s.key)}
            className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition ${
              stage === s.key
                ? "bg-ink text-white"
                : "text-stone-500 hover:bg-stone-100"
            }`}
          >
            {s.label}
          </button>
        ))}
      </nav>

      {error && (
        <div className="mt-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {/* STAGE 1: OUTLINE */}
      {stage === "OUTLINE" && (
        <section className="mt-6 space-y-6">
          <div>
            <label className="block text-sm font-medium text-stone-700">
              What do you want to write about?
            </label>
            <p className="text-sm text-stone-500">
              Jot down the story, moment, or idea. The AI can build an outline
              from this, or you can write your own below.
            </p>
            <textarea
              value={topic}
              onChange={(e) => {
                setTopic(e.target.value);
                queueSave({ topic: e.target.value });
              }}
              rows={5}
              placeholder="e.g. The summer I rebuilt my grandfather's broken radio and learned to sit with not-knowing…"
              className="mt-2 w-full rounded-xl border border-stone-300 p-4 outline-none focus:border-accent"
            />
            <button
              onClick={generateOutline}
              disabled={busy !== null}
              className="mt-3 rounded-lg bg-accent px-4 py-2 text-sm font-medium text-white transition hover:opacity-90 disabled:opacity-40"
            >
              {busy === "outline" ? "Building outline…" : "✨ Generate outline with AI"}
            </button>
          </div>

          <div>
            <label className="block text-sm font-medium text-stone-700">
              Outline
            </label>
            <textarea
              value={outline}
              onChange={(e) => {
                setOutline(e.target.value);
                queueSave({ outline: e.target.value });
              }}
              rows={16}
              placeholder="Your outline will appear here. You can edit it freely."
              className="mt-2 w-full rounded-xl border border-stone-300 p-4 font-mono text-sm leading-relaxed outline-none focus:border-accent"
            />
          </div>

          <button
            onClick={() => goToStage("DRAFT")}
            disabled={!outline.trim()}
            className="rounded-lg bg-ink px-5 py-2.5 font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
          >
            Continue to drafting →
          </button>
        </section>
      )}

      {/* STAGE 2 & 3 share the editor + review layout */}
      {(stage === "DRAFT" || stage === "EDIT") && (
        <section className="mt-6 grid gap-8 lg:grid-cols-2">
          {/* Left: prompt + editor */}
          <div className="space-y-5">
            {stage === "DRAFT" && (
              <div className="rounded-xl border border-stone-200 bg-white p-4">
                <label className="block text-sm font-medium text-stone-700">
                  Which prompt is this essay answering?
                </label>
                <div className="mt-3 space-y-2">
                  {COMMON_APP_PROMPTS.map((p) => (
                    <label
                      key={p.id}
                      className={`flex cursor-pointer gap-3 rounded-lg border p-3 text-sm transition ${
                        promptId === p.id
                          ? "border-accent bg-amber-50"
                          : "border-stone-200 hover:border-stone-300"
                      }`}
                    >
                      <input
                        type="radio"
                        name="prompt"
                        checked={promptId === p.id}
                        onChange={() => {
                          setPromptId(p.id);
                          persist({ promptId: p.id });
                        }}
                        className="mt-1 accent-accent"
                      />
                      <span>
                        <span className="font-medium">{p.label}</span>
                        <span className="block text-stone-500">{p.text}</span>
                      </span>
                    </label>
                  ))}
                </div>
                <button
                  onClick={generateDraft}
                  disabled={busy !== null || !promptId}
                  className="mt-4 rounded-lg bg-accent px-4 py-2 text-sm font-medium text-white transition hover:opacity-90 disabled:opacity-40"
                >
                  {busy === "draft"
                    ? "Writing your essay…"
                    : draft.trim()
                    ? "✨ Rewrite draft from outline"
                    : "✨ Write the essay with Claude"}
                </button>
              </div>
            )}

            <div>
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-stone-700">
                  {stage === "EDIT" ? "Edit your essay" : "Draft"}
                </label>
                <span
                  className={`text-xs ${
                    words > 650 ? "font-semibold text-red-600" : "text-stone-400"
                  }`}
                >
                  {words} / 650 words
                </span>
              </div>
              <textarea
                value={draft}
                onChange={(e) => {
                  setDraft(e.target.value);
                  queueSave({ draft: e.target.value });
                }}
                rows={24}
                placeholder="Your essay will appear here once Claude drafts it. Edit freely."
                className="mt-2 w-full rounded-xl border border-stone-300 p-4 font-serif text-[15px] leading-relaxed outline-none focus:border-accent"
              />
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                onClick={sendToCouncil}
                disabled={busy !== null || !draft.trim()}
                className="rounded-lg bg-ink px-4 py-2 text-sm font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
              >
                {busy === "council"
                  ? "The Council is reading…"
                  : latest?.critiques.length
                  ? "↻ Send back to the Council"
                  : "Send to the Council"}
              </button>
              <button
                onClick={runGrammar}
                disabled={busy !== null || !draft.trim()}
                className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-medium text-stone-700 transition hover:border-stone-400 disabled:opacity-40"
              >
                {busy === "grammar" ? "Checking…" : "Run grammar check"}
              </button>
              {stage === "DRAFT" && (
                <button
                  onClick={() => goToStage("EDIT")}
                  disabled={!draft.trim()}
                  className="ml-auto rounded-lg px-4 py-2 text-sm font-medium text-stone-500 transition hover:text-ink disabled:opacity-40"
                >
                  Continue to editing →
                </button>
              )}
            </div>

            {/* The Writer */}
            <div className="rounded-xl border border-stone-200 bg-white p-4">
              <h3 className="font-serif text-lg font-semibold">The Writer</h3>
              <p className="mt-1 text-sm text-stone-500">
                Give the writer notes to revise your draft, or have it fold in
                the council&apos;s feedback. You&apos;ll see the proposed changes
                before anything is applied.
              </p>
              <textarea
                value={writerNotes}
                onChange={(e) => setWriterNotes(e.target.value)}
                rows={3}
                placeholder="e.g. Tighten the opening, cut the third paragraph, make the ending less neat…"
                className="mt-3 w-full rounded-lg border border-stone-300 p-3 text-sm outline-none focus:border-accent"
              />
              <div className="mt-3 flex flex-wrap gap-3">
                <button
                  onClick={() => reviseWithWriter(false)}
                  disabled={busy !== null || !writerNotes.trim()}
                  className="rounded-lg bg-accent px-4 py-2 text-sm font-medium text-white transition hover:opacity-90 disabled:opacity-40"
                >
                  {busy === "writer" ? "Writing…" : "✨ Revise with my notes"}
                </button>
                <button
                  onClick={() => reviseWithWriter(true)}
                  disabled={busy !== null || !latest?.critiques.length}
                  title={
                    !latest?.critiques.length
                      ? "Send the draft to the Council first"
                      : ""
                  }
                  className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-medium text-stone-700 transition hover:border-stone-400 disabled:opacity-40"
                >
                  Apply council feedback{writerNotes.trim() ? " + my notes" : ""}
                </button>
              </div>
            </div>

            {/* Proposed revision (from the Writer) */}
            {proposal !== null && (
              <div className="rounded-xl border-2 border-accent bg-amber-50/40 p-4">
                <div className="flex items-center justify-between">
                  <h3 className="font-serif text-lg font-semibold">
                    Proposed revision
                  </h3>
                  <span className="text-xs text-stone-500">
                    <span className="rounded bg-green-100 px-1 text-green-900">
                      added
                    </span>{" "}
                    <span className="rounded bg-red-100 px-1 text-red-800 line-through">
                      removed
                    </span>
                  </span>
                </div>
                <div className="mt-3 max-h-96 overflow-y-auto rounded-lg bg-white p-4">
                  <DraftDiff before={draft} after={proposal} />
                </div>
                <div className="mt-3 flex gap-3">
                  <button
                    onClick={acceptProposal}
                    className="rounded-lg bg-ink px-4 py-2 text-sm font-medium text-white transition hover:bg-stone-700"
                  >
                    Accept changes
                  </button>
                  <button
                    onClick={discardProposal}
                    className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-medium text-stone-700 transition hover:border-stone-400"
                  >
                    Discard
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Right: review panel */}
          <div className="lg:max-h-[calc(100vh-9rem)] lg:overflow-y-auto lg:pr-1">
            {latest && (
              <p className="mb-3 text-xs uppercase tracking-wide text-stone-400">
                Feedback on round {latest.round}
              </p>
            )}
            <ReviewPanel
              critiques={latest?.critiques ?? []}
              grammarReports={latest?.grammarReports ?? []}
            />
          </div>
        </section>
      )}
    </main>
  );
}

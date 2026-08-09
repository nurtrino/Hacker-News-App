"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { COMMON_APP_PROMPTS } from "@/lib/prompts";

interface EssaySummary {
  id: string;
  title: string;
  type: string;
  stage: string;
  promptId: string | null;
  school: string;
  updatedAt: string;
}

const STAGE_LABEL: Record<string, string> = {
  OUTLINE: "Outlining",
  DRAFT: "Drafting & review",
  EDIT: "Editing",
};

export default function Dashboard() {
  const router = useRouter();
  const [essays, setEssays] = useState<EssaySummary[] | null>(null);
  const [creating, setCreating] = useState<null | "PERSONAL_STATEMENT" | "SUPPLEMENTAL">(
    null
  );

  async function load() {
    const res = await fetch("/api/essays");
    if (res.ok) {
      const data = await res.json();
      setEssays(data.essays);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function newEssay(type: "PERSONAL_STATEMENT" | "SUPPLEMENTAL") {
    setCreating(type);
    const res = await fetch("/api/essays", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type }),
    });
    setCreating(null);
    if (res.ok) {
      const { id } = await res.json();
      router.push(`/essay/${id}`);
    }
  }

  async function remove(id: string) {
    if (!confirm("Delete this essay and all of its feedback? This can't be undone.")) return;
    await fetch(`/api/essays/${id}`, { method: "DELETE" });
    load();
  }

  async function logout() {
    await fetch("/api/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  const personalStatements =
    essays?.filter((e) => e.type !== "SUPPLEMENTAL") ?? [];
  const supplements = essays?.filter((e) => e.type === "SUPPLEMENTAL") ?? [];

  function EssayCard({ essay }: { essay: EssaySummary }) {
    const prompt = COMMON_APP_PROMPTS.find((p) => p.id === essay.promptId);
    const meta =
      essay.type === "SUPPLEMENTAL"
        ? essay.school.trim()
          ? essay.school.trim()
          : ""
        : prompt
        ? prompt.label
        : "";
    return (
      <div className="group flex items-center justify-between rounded-xl border border-stone-200 bg-white p-5 transition hover:border-stone-300 hover:shadow-sm">
        <Link href={`/essay/${essay.id}`} className="min-w-0 flex-1">
          <h2 className="truncate font-serif text-xl font-semibold">
            {essay.title}
          </h2>
          <p className="mt-1 text-sm text-stone-500">
            {STAGE_LABEL[essay.stage] ?? essay.stage}
            {meta ? ` · ${meta}` : ""} · edited{" "}
            {new Date(essay.updatedAt).toLocaleDateString()}
          </p>
        </Link>
        <button
          onClick={() => remove(essay.id)}
          className="ml-4 text-sm text-stone-300 opacity-0 transition hover:text-red-600 group-hover:opacity-100"
        >
          Delete
        </button>
      </div>
    );
  }

  return (
    <main className="mx-auto max-w-4xl px-6 py-12">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="font-serif text-3xl font-bold">Your college essays</h1>
          <p className="mt-1 text-stone-500">
            Iterate on your application essays with the Council.
          </p>
        </div>
        <button
          onClick={logout}
          className="text-sm text-stone-400 transition hover:text-stone-700"
        >
          Sign out
        </button>
      </header>

      {/* Personal Statements */}
      <section className="mt-10">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-serif text-2xl font-semibold">Personal Statements</h2>
            <p className="mt-1 text-sm text-stone-500">
              Your Common App essay, built from a prompt you choose.
            </p>
          </div>
          <button
            onClick={() => newEssay("PERSONAL_STATEMENT")}
            disabled={creating !== null}
            className="rounded-xl bg-ink px-5 py-3 font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
          >
            {creating === "PERSONAL_STATEMENT" ? "Creating…" : "+ New personal statement"}
          </button>
        </div>

        <div className="mt-5 space-y-3">
          {essays === null && <p className="text-stone-400">Loading…</p>}
          {essays !== null && personalStatements.length === 0 && (
            <p className="text-stone-400">
              No personal statements yet. Start your first one above.
            </p>
          )}
          {personalStatements.map((essay) => (
            <EssayCard key={essay.id} essay={essay} />
          ))}
        </div>
      </section>

      {/* Supplemental Essays */}
      <section className="mt-12">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-serif text-2xl font-semibold">Supplemental Essays</h2>
            <p className="mt-1 text-sm text-stone-500">
              School-specific essays — you supply the prompt, your outline, and
              the school.
            </p>
          </div>
          <button
            onClick={() => newEssay("SUPPLEMENTAL")}
            disabled={creating !== null}
            className="rounded-xl bg-ink px-5 py-3 font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
          >
            {creating === "SUPPLEMENTAL" ? "Creating…" : "+ New supplemental essay"}
          </button>
        </div>

        <div className="mt-5 space-y-3">
          {essays === null && <p className="text-stone-400">Loading…</p>}
          {essays !== null && supplements.length === 0 && (
            <p className="text-stone-400">
              No supplemental essays yet. Start your first one above.
            </p>
          )}
          {supplements.map((essay) => (
            <EssayCard key={essay.id} essay={essay} />
          ))}
        </div>
      </section>
    </main>
  );
}

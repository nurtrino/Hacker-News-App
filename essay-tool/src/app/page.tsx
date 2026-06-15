"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { COMMON_APP_PROMPTS } from "@/lib/prompts";

interface EssaySummary {
  id: string;
  title: string;
  stage: string;
  promptId: string | null;
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
  const [creating, setCreating] = useState(false);

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

  async function newEssay() {
    setCreating(true);
    const res = await fetch("/api/essays", { method: "POST" });
    setCreating(false);
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

  return (
    <main className="mx-auto max-w-4xl px-6 py-12">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="font-serif text-3xl font-bold">Personal Statements</h1>
          <p className="mt-1 text-stone-500">
            Iterate on your college application essays with the Council.
          </p>
        </div>
        <button
          onClick={logout}
          className="text-sm text-stone-400 transition hover:text-stone-700"
        >
          Sign out
        </button>
      </header>

      <button
        onClick={newEssay}
        disabled={creating}
        className="mt-8 rounded-xl bg-ink px-5 py-3 font-medium text-white transition hover:bg-stone-700 disabled:opacity-40"
      >
        {creating ? "Creating…" : "+ Start a new essay"}
      </button>

      <section className="mt-8 space-y-3">
        {essays === null && <p className="text-stone-400">Loading…</p>}
        {essays?.length === 0 && (
          <p className="text-stone-400">
            No essays yet. Start your first one above.
          </p>
        )}
        {essays?.map((essay) => {
          const prompt = COMMON_APP_PROMPTS.find((p) => p.id === essay.promptId);
          return (
            <div
              key={essay.id}
              className="group flex items-center justify-between rounded-xl border border-stone-200 bg-white p-5 transition hover:border-stone-300 hover:shadow-sm"
            >
              <Link href={`/essay/${essay.id}`} className="min-w-0 flex-1">
                <h2 className="truncate font-serif text-xl font-semibold">
                  {essay.title}
                </h2>
                <p className="mt-1 text-sm text-stone-500">
                  {STAGE_LABEL[essay.stage] ?? essay.stage}
                  {prompt ? ` · ${prompt.label}` : ""} · edited{" "}
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
        })}
      </section>
    </main>
  );
}

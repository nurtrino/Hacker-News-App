import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { runLanguageTool, runClaudeGrammar } from "@/lib/grammar";
import { getOrCreateCurrentRevision } from "@/lib/revisions";

export const maxDuration = 300;

// Run the grammar pass (LanguageTool mechanics + Claude style) on the draft.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as { draft?: string };

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const draft = (body.draft ?? essay.draft).trim();
  if (!draft) {
    return NextResponse.json(
      { error: "There's no draft to check yet." },
      { status: 400 }
    );
  }
  if (draft !== essay.draft) {
    await prisma.essay.update({ where: { id: params.id }, data: { draft } });
  }

  const revision = await getOrCreateCurrentRevision(params.id, draft);

  // Run both passes; if one fails, still return the other.
  const [ltResult, claudeResult] = await Promise.allSettled([
    runLanguageTool(draft),
    runClaudeGrammar(draft),
  ]);

  await prisma.grammarReport.deleteMany({ where: { revisionId: revision.id } });

  const reports: { source: string; content: string }[] = [];

  if (ltResult.status === "fulfilled") {
    reports.push({
      source: "LANGUAGETOOL",
      content: JSON.stringify(ltResult.value),
    });
  } else {
    reports.push({
      source: "LANGUAGETOOL",
      content: JSON.stringify({
        error:
          ltResult.reason instanceof Error
            ? ltResult.reason.message
            : "LanguageTool check failed.",
      }),
    });
  }

  if (claudeResult.status === "fulfilled") {
    reports.push({ source: "CLAUDE", content: claudeResult.value });
  } else {
    reports.push({
      source: "CLAUDE",
      content:
        "_The Claude proofreading pass failed: " +
        (claudeResult.reason instanceof Error
          ? claudeResult.reason.message
          : "unknown error") +
        "_",
    });
  }

  await prisma.grammarReport.createMany({
    data: reports.map((r) => ({ ...r, revisionId: revision.id })),
  });

  const grammarReports = await prisma.grammarReport.findMany({
    where: { revisionId: revision.id },
    orderBy: { createdAt: "asc" },
  });

  return NextResponse.json({ revisionId: revision.id, grammarReports });
}

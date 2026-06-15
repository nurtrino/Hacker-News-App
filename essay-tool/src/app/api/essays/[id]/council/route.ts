import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import { COUNCIL, getPrompt, buildCouncilUser } from "@/lib/prompts";
import { getOrCreateCurrentRevision } from "@/lib/revisions";

export const maxDuration = 300;

// Send the current draft to the Council. Members review the SAME draft, but in
// sequence: each member also sees the notes left by earlier members so they can
// build on them. Critiques are stored against a snapshot revision.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as { draft?: string };

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  // Persist any unsaved edits the client sent.
  const draft = (body.draft ?? essay.draft).trim();
  if (!draft) {
    return NextResponse.json(
      { error: "There's no draft to review yet." },
      { status: 400 }
    );
  }
  if (draft !== essay.draft) {
    await prisma.essay.update({ where: { id: params.id }, data: { draft } });
  }

  const prompt = getPrompt(essay.promptId);
  const promptContext = prompt
    ? `The essay is responding to this Common App prompt:\n"${prompt.text}"\n\n`
    : "";

  try {
    const revision = await getOrCreateCurrentRevision(params.id, draft);

    // Run the critics one at a time, feeding each the earlier members' notes.
    const results: { critic: (typeof COUNCIL)[number]; content: string }[] = [];
    let priorNotes = "";
    for (const critic of COUNCIL) {
      const content = await complete({
        system: critic.system,
        user: buildCouncilUser(promptContext, draft, priorNotes),
        maxTokens: 4000,
      });
      results.push({ critic, content });
      priorNotes += `\n\n## ${critic.name}\n${content}`;
    }

    // Replace any prior critiques on this revision (supports re-running).
    await prisma.critique.deleteMany({ where: { revisionId: revision.id } });
    await prisma.critique.createMany({
      data: results.map(({ critic, content }, order) => ({
        revisionId: revision.id,
        critic: critic.key,
        criticName: critic.name,
        content,
        order,
      })),
    });

    const critiques = await prisma.critique.findMany({
      where: { revisionId: revision.id },
      orderBy: { order: "asc" },
    });

    return NextResponse.json({ revisionId: revision.id, round: revision.round, critiques });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "The Council failed to respond." },
      { status: 500 }
    );
  }
}

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import { COUNCIL, getPrompt } from "@/lib/prompts";
import { getOrCreateCurrentRevision } from "@/lib/revisions";

export const maxDuration = 300;

// Send the current draft to the Council: run all three critics in parallel
// and store their critiques against a snapshot revision.
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

    // Run the three critics concurrently.
    const results = await Promise.all(
      COUNCIL.map((critic) =>
        complete({
          system: critic.system,
          user: `${promptContext}Here is the essay to critique:\n\n${draft}`,
          maxTokens: 4000,
        }).then((content) => ({ critic, content }))
      )
    );

    // Replace any prior critiques on this revision (supports re-running).
    await prisma.critique.deleteMany({ where: { revisionId: revision.id } });
    await prisma.critique.createMany({
      data: results.map(({ critic, content }) => ({
        revisionId: revision.id,
        critic: critic.key,
        criticName: critic.name,
        content,
      })),
    });

    const critiques = await prisma.critique.findMany({
      where: { revisionId: revision.id },
      orderBy: { createdAt: "asc" },
    });

    return NextResponse.json({ revisionId: revision.id, round: revision.round, critiques });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "The Council failed to respond." },
      { status: 500 }
    );
  }
}

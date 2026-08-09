import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import {
  COUNCIL,
  getPrompt,
  buildCouncilUser,
  buildSupplementContext,
} from "@/lib/prompts";
import { getOrCreateCurrentRevision } from "@/lib/revisions";
import { parseCouncilResponse } from "@/lib/council";

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

  const promptContext =
    essay.type === "SUPPLEMENTAL"
      ? buildSupplementContext({
          customPrompt: essay.customPrompt,
          school: essay.school,
          schoolInfo: essay.schoolInfo,
        })
      : (() => {
          const prompt = getPrompt(essay.promptId);
          return prompt
            ? `The essay is responding to this Common App prompt:\n"${prompt.text}"\n\n`
            : "";
        })();

  try {
    const revision = await getOrCreateCurrentRevision(params.id, draft);

    // Replace any prior critiques on this revision (cascades to suggestions).
    await prisma.critique.deleteMany({ where: { revisionId: revision.id } });

    // Run the critics one at a time, feeding each the earlier members' notes.
    // Each member returns a critique plus proposed edits, which we store as
    // accept/reject suggestions.
    let priorNotes = "";
    let order = 0;
    for (const critic of COUNCIL) {
      const raw = await complete({
        system: critic.system,
        user: buildCouncilUser(promptContext, draft, priorNotes),
        maxTokens: 4000,
      });
      const { notes, edits } = parseCouncilResponse(raw);

      await prisma.critique.create({
        data: {
          revisionId: revision.id,
          critic: critic.key,
          criticName: critic.name,
          content: notes,
          order: order++,
          suggestions: {
            create: edits.map((e) => ({
              original: e.original,
              replacement: e.replacement,
              reason: e.reason,
            })),
          },
        },
      });

      priorNotes += `\n\n## ${critic.name}\n${notes}`;
    }

    const critiques = await prisma.critique.findMany({
      where: { revisionId: revision.id },
      orderBy: { order: "asc" },
      include: { suggestions: { orderBy: { createdAt: "asc" } } },
    });

    return NextResponse.json({ revisionId: revision.id, round: revision.round, critiques });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "The Council failed to respond." },
      { status: 500 }
    );
  }
}

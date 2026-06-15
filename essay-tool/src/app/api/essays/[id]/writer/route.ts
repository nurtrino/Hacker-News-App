import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import { WRITER_SYSTEM, buildWriterUser, getPrompt } from "@/lib/prompts";

export const maxDuration = 300;

// The Writer produces a *proposed* revised draft. It does NOT overwrite the
// saved draft — the client shows the proposal and the student accepts it.
//
// Body:
//   notes?: string         student instructions for the writer
//   applyCouncil?: boolean  also fold in the latest council critiques
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as {
    notes?: string;
    applyCouncil?: boolean;
    draft?: string;
  };

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  // Use the freshest draft (the client may have unsaved edits).
  const draft = (body.draft ?? essay.draft).trim();
  if (!draft) {
    return NextResponse.json(
      { error: "There's no draft for the writer to revise yet." },
      { status: 400 }
    );
  }
  if (draft !== essay.draft) {
    await prisma.essay.update({ where: { id: params.id }, data: { draft } });
  }

  if (!body.notes?.trim() && !body.applyCouncil) {
    return NextResponse.json(
      { error: "Give the writer some notes, or apply the council's feedback." },
      { status: 400 }
    );
  }

  // Gather the latest council feedback if asked to apply it.
  let councilNotes = "";
  if (body.applyCouncil) {
    const latest = await prisma.revision.findFirst({
      where: { essayId: params.id },
      orderBy: { round: "desc" },
      include: { critiques: { orderBy: { order: "asc" } } },
    });
    councilNotes = (latest?.critiques ?? [])
      .map((c) => `## ${c.criticName}\n${c.content}`)
      .join("\n\n");
    if (!councilNotes) {
      return NextResponse.json(
        { error: "There's no council feedback to apply yet. Send it to the Council first." },
        { status: 400 }
      );
    }
  }

  const prompt = getPrompt(essay.promptId);

  try {
    const proposal = await complete({
      system: WRITER_SYSTEM,
      user: buildWriterUser({
        promptText: prompt?.text,
        draft,
        councilNotes,
        studentNotes: body.notes,
      }),
      maxTokens: 4000,
    });

    return NextResponse.json({ proposal });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "The writer failed to respond." },
      { status: 500 }
    );
  }
}

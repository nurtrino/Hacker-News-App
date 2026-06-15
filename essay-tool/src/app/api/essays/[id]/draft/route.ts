import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import { buildDraftSystem, getPrompt } from "@/lib/prompts";

export const maxDuration = 300;

// Write a full draft from the outline + chosen prompt.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as {
    promptId?: string;
  };

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const promptId = body.promptId ?? essay.promptId;
  const prompt = getPrompt(promptId);
  if (!prompt) {
    return NextResponse.json(
      { error: "Choose a Common App prompt before generating the draft." },
      { status: 400 }
    );
  }

  if (!essay.outline.trim()) {
    return NextResponse.json(
      { error: "Write or generate an outline first." },
      { status: 400 }
    );
  }

  try {
    const draft = await complete({
      system: buildDraftSystem(prompt.text),
      user: `Here is the student's outline. Turn it into the full essay:\n\n${essay.outline}`,
      maxTokens: 4000,
    });

    await prisma.essay.update({
      where: { id: params.id },
      data: { draft, promptId, stage: "DRAFT" },
    });

    return NextResponse.json({ draft });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Failed to write the draft." },
      { status: 500 }
    );
  }
}

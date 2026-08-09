import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { complete } from "@/lib/anthropic";
import {
  OUTLINE_SYSTEM,
  SUPPLEMENT_OUTLINE_SYSTEM,
  getPrompt,
  buildSupplementContext,
} from "@/lib/prompts";

export const maxDuration = 300;

// Generate an outline from the student's topic (and optionally the chosen prompt).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as {
    topic?: string;
    promptId?: string | null;
  };

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const topic = (body.topic ?? essay.topic ?? "").trim();
  if (!topic) {
    return NextResponse.json(
      { error: "Add a topic or some notes first so the AI has something to work with." },
      { status: 400 }
    );
  }

  const isSupplement = essay.type === "SUPPLEMENTAL";

  let system: string;
  let contextLine: string;
  if (isSupplement) {
    system = SUPPLEMENT_OUTLINE_SYSTEM;
    contextLine = buildSupplementContext({
      customPrompt: essay.customPrompt,
      school: essay.school,
      schoolInfo: essay.schoolInfo,
      wordLimit: essay.wordLimit,
    });
  } else {
    system = OUTLINE_SYSTEM;
    const prompt = getPrompt(body.promptId ?? essay.promptId);
    contextLine = prompt
      ? `The student is leaning toward this Common App prompt:\n"${prompt.text}"\n\n`
      : "";
  }

  try {
    const outline = await complete({
      system,
      user: `${contextLine}Here is what the student wants to write about:\n\n${topic}\n\nBuild them a strong outline.`,
      maxTokens: 3000,
    });

    await prisma.essay.update({
      where: { id: params.id },
      data: { outline, topic },
    });

    return NextResponse.json({ outline });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Failed to generate outline." },
      { status: 500 }
    );
  }
}

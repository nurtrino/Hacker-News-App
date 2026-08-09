import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

// Get one essay with its full review history.
export async function GET(
  _req: NextRequest,
  { params }: { params: { id: string } }
) {
  const essay = await prisma.essay.findUnique({
    where: { id: params.id },
    include: {
      revisions: {
        orderBy: { round: "desc" },
        include: {
          critiques: {
            orderBy: { order: "asc" },
            include: { suggestions: { orderBy: { createdAt: "asc" } } },
          },
          grammarReports: { orderBy: { createdAt: "asc" } },
        },
      },
    },
  });

  if (!essay) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ essay });
}

// Save editable fields.
export async function PATCH(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = (await req.json().catch(() => ({}))) as {
    title?: string;
    topic?: string;
    outline?: string;
    draft?: string;
    stage?: string;
    promptId?: string | null;
    customPrompt?: string;
    school?: string;
    schoolInfo?: string;
    wordLimit?: number | null;
  };

  const data: Record<string, unknown> = {};
  if (typeof body.title === "string")
    data.title = body.title.trim() || "Untitled Essay";
  if (typeof body.topic === "string") data.topic = body.topic;
  if (typeof body.outline === "string") data.outline = body.outline;
  if (typeof body.draft === "string") data.draft = body.draft;
  if (typeof body.stage === "string") data.stage = body.stage;
  if (body.promptId === null || typeof body.promptId === "string")
    data.promptId = body.promptId;
  if (typeof body.customPrompt === "string") data.customPrompt = body.customPrompt;
  if (typeof body.school === "string") data.school = body.school;
  if (typeof body.schoolInfo === "string") data.schoolInfo = body.schoolInfo;
  if (body.wordLimit === null) {
    data.wordLimit = null;
  } else if (typeof body.wordLimit === "number" && Number.isFinite(body.wordLimit)) {
    data.wordLimit = body.wordLimit > 0 ? Math.round(body.wordLimit) : null;
  }

  const essay = await prisma.essay.update({
    where: { id: params.id },
    data,
  });

  return NextResponse.json({ essay });
}

// Delete an essay (and its revisions/critiques/grammar via cascade).
export async function DELETE(
  _req: NextRequest,
  { params }: { params: { id: string } }
) {
  await prisma.essay.delete({ where: { id: params.id } });
  return NextResponse.json({ ok: true });
}

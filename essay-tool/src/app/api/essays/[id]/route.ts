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
  };

  const data: Record<string, unknown> = {};
  if (typeof body.title === "string") data.title = body.title.trim() || "Untitled Personal Statement";
  if (typeof body.topic === "string") data.topic = body.topic;
  if (typeof body.outline === "string") data.outline = body.outline;
  if (typeof body.draft === "string") data.draft = body.draft;
  if (typeof body.stage === "string") data.stage = body.stage;
  if (body.promptId === null || typeof body.promptId === "string")
    data.promptId = body.promptId;

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

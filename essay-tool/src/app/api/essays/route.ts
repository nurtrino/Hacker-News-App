import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

// List all essays (most recently edited first).
export async function GET() {
  const essays = await prisma.essay.findMany({
    orderBy: { updatedAt: "desc" },
    select: {
      id: true,
      title: true,
      type: true,
      stage: true,
      promptId: true,
      school: true,
      updatedAt: true,
    },
  });
  return NextResponse.json({ essays });
}

// Create a new (blank) essay and return its id. `type` is PERSONAL_STATEMENT
// (default) or SUPPLEMENTAL.
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => ({}))) as {
    title?: string;
    type?: string;
  };

  const type = body.type === "SUPPLEMENTAL" ? "SUPPLEMENTAL" : "PERSONAL_STATEMENT";
  const fallbackTitle =
    type === "SUPPLEMENTAL"
      ? "Untitled Supplemental Essay"
      : "Untitled Personal Statement";
  const title = body.title?.trim() || fallbackTitle;

  const essay = await prisma.essay.create({
    data: { title, type },
    select: { id: true },
  });

  return NextResponse.json({ id: essay.id });
}

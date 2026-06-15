import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

// List all essays (most recently edited first).
export async function GET() {
  const essays = await prisma.essay.findMany({
    orderBy: { updatedAt: "desc" },
    select: {
      id: true,
      title: true,
      stage: true,
      promptId: true,
      updatedAt: true,
    },
  });
  return NextResponse.json({ essays });
}

// Create a new (blank) essay and return its id.
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => ({}))) as { title?: string };
  const title = body.title?.trim() || "Untitled Personal Statement";

  const essay = await prisma.essay.create({
    data: { title },
    select: { id: true },
  });

  return NextResponse.json({ id: essay.id });
}

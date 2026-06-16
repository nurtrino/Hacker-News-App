import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

// Accept or reject a single council suggestion. Accepting replaces the
// suggestion's `original` text with its `replacement` in the working draft.
//
// Body: { suggestionId: string, accept: boolean }
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const { suggestionId, accept } = (await req.json().catch(() => ({}))) as {
    suggestionId?: string;
    accept?: boolean;
  };

  if (!suggestionId) {
    return NextResponse.json({ error: "Missing suggestionId" }, { status: 400 });
  }

  const suggestion = await prisma.suggestion.findUnique({
    where: { id: suggestionId },
    include: { critique: { include: { revision: true } } },
  });

  // Make sure the suggestion really belongs to this essay.
  if (!suggestion || suggestion.critique.revision.essayId !== params.id) {
    return NextResponse.json({ error: "Suggestion not found" }, { status: 404 });
  }

  if (!accept) {
    const updated = await prisma.suggestion.update({
      where: { id: suggestionId },
      data: { status: "REJECTED" },
    });
    return NextResponse.json({ status: updated.status });
  }

  const essay = await prisma.essay.findUnique({ where: { id: params.id } });
  if (!essay) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const idx = essay.draft.indexOf(suggestion.original);
  if (idx === -1) {
    // The text changed (or an earlier accepted edit already touched it).
    await prisma.suggestion.update({
      where: { id: suggestionId },
      data: { status: "STALE" },
    });
    return NextResponse.json({
      applied: false,
      status: "STALE",
      error:
        "Couldn't find the original text — it may have changed or already been edited.",
    });
  }

  const newDraft =
    essay.draft.slice(0, idx) +
    suggestion.replacement +
    essay.draft.slice(idx + suggestion.original.length);

  await prisma.essay.update({
    where: { id: params.id },
    data: { draft: newDraft },
  });
  await prisma.suggestion.update({
    where: { id: suggestionId },
    data: { status: "ACCEPTED" },
  });

  return NextResponse.json({ applied: true, status: "ACCEPTED", draft: newDraft });
}

import { prisma } from "./db";

/**
 * Return the revision representing the current draft. If the most recent
 * revision already matches the draft text, reuse it (so Council + Grammar from
 * the same draft share one review round). Otherwise snapshot a new revision.
 */
export async function getOrCreateCurrentRevision(
  essayId: string,
  draft: string
) {
  const latest = await prisma.revision.findFirst({
    where: { essayId },
    orderBy: { round: "desc" },
  });

  if (latest && latest.content === draft) {
    return latest;
  }

  return prisma.revision.create({
    data: {
      essayId,
      content: draft,
      round: (latest?.round ?? 0) + 1,
    },
  });
}

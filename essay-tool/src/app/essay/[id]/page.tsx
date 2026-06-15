import { notFound } from "next/navigation";
import { prisma } from "@/lib/db";
import EssayWorkspace from "./EssayWorkspace";

export const dynamic = "force-dynamic";

export default async function EssayPage({
  params,
}: {
  params: { id: string };
}) {
  const essay = await prisma.essay.findUnique({
    where: { id: params.id },
    include: {
      revisions: {
        orderBy: { round: "desc" },
        include: {
          critiques: { orderBy: { createdAt: "asc" } },
          grammarReports: { orderBy: { createdAt: "asc" } },
        },
      },
    },
  });

  if (!essay) notFound();

  // Serialize dates for the client component.
  const initial = JSON.parse(JSON.stringify(essay));

  return <EssayWorkspace initialEssay={initial} />;
}

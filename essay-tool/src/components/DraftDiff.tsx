// A small, dependency-free word-level diff so the student can see what the
// writer changed before accepting it. Deletions are struck through in red,
// additions highlighted in green.

import React from "react";

function tokenize(text: string): string[] {
  // Keep whitespace as part of tokens so reconstruction reads naturally.
  return text.match(/\S+\s*|\s+/g) ?? [];
}

type Op = { type: "same" | "add" | "del"; text: string };

function diffWords(a: string[], b: string[]): Op[] {
  // Classic LCS dynamic-programming table.
  const n = a.length;
  const m = b.length;
  const dp: number[][] = Array.from({ length: n + 1 }, () =>
    new Array(m + 1).fill(0)
  );
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] =
        a[i] === b[j]
          ? dp[i + 1][j + 1] + 1
          : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  const ops: Op[] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      ops.push({ type: "same", text: a[i] });
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.push({ type: "del", text: a[i] });
      i++;
    } else {
      ops.push({ type: "add", text: b[j] });
      j++;
    }
  }
  while (i < n) ops.push({ type: "del", text: a[i++] });
  while (j < m) ops.push({ type: "add", text: b[j++] });
  return ops;
}

export default function DraftDiff({
  before,
  after,
}: {
  before: string;
  after: string;
}) {
  const ops = diffWords(tokenize(before), tokenize(after));
  return (
    <p className="whitespace-pre-wrap font-serif text-[15px] leading-relaxed">
      {ops.map((op, i) => {
        if (op.type === "same") return <span key={i}>{op.text}</span>;
        if (op.type === "add")
          return (
            <span key={i} className="rounded bg-green-100 text-green-900">
              {op.text}
            </span>
          );
        return (
          <span key={i} className="rounded bg-red-100 text-red-800 line-through">
            {op.text}
          </span>
        );
      })}
    </p>
  );
}

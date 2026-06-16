// Parse a council member's raw response into the markdown critique (notes) and
// the structured list of proposed edits, which the member emits as a fenced
// ```edits``` block containing a JSON array.

export interface ParsedEdit {
  original: string;
  replacement: string;
  reason: string;
}

export interface ParsedCouncilResponse {
  notes: string;
  edits: ParsedEdit[];
}

export function parseCouncilResponse(raw: string): ParsedCouncilResponse {
  // Prefer a block explicitly labeled `edits`, then fall back to any fenced
  // block that looks like a JSON array.
  const labeled = raw.match(/```edits\s*([\s\S]*?)```/i);
  const generic = labeled
    ? null
    : raw.match(/```(?:json)?\s*(\[[\s\S]*?\])\s*```/i);
  const match = labeled ?? generic;

  let edits: ParsedEdit[] = [];
  let notes = raw;

  if (match) {
    notes = raw.replace(match[0], "").trim();
    try {
      const parsed = JSON.parse(match[1].trim());
      if (Array.isArray(parsed)) {
        edits = parsed
          .filter(
            (e) =>
              e &&
              typeof e.original === "string" &&
              typeof e.replacement === "string" &&
              e.original.trim().length > 0 &&
              e.original !== e.replacement
          )
          .map((e) => ({
            original: e.original,
            replacement: e.replacement,
            reason: typeof e.reason === "string" ? e.reason : "",
          }));
      }
    } catch {
      // If the JSON is malformed, keep the notes and drop the edits silently.
    }
  }

  return { notes, edits };
}

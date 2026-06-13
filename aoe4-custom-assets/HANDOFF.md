# HANDOFF — AoE4 Custom Asset Injection (local phase)

> Context for a local Claude Code session (or a human) picking up this
> project on a Windows machine with Age of Empires IV installed. The remote
> research phase is complete; everything below is current as of 2026-06-13.
> Companion doc: `RESEARCH.md` (full findings + format details).

## Mission

Get custom 3D models (modern units / tanks) rendering in AoE4. The official
Content Editor has no model-import pipeline, so we are building one on top of
the community toolkit **AOEMods.Essence** (MIT, C#,
https://github.com/aoemods/AOEMods.Essence).

## State of knowledge (do not re-research; verified by source inspection)

- `.sga` archives: read + write fully working in AOEMods.Essence
  (`ArchiveWriter` emits per-file CRCs; `sga-pack` / `sga-unpack` CLI).
- `.rrgeom` (models): READ works (`RRGeomReader`). Relic Chunky tree
  `MESH → LOD → GEOM`, chunks `NBME/NBLO/NBGO/GOHD/GEOB`. Vertex stride
  `elementDataLength`: pos 3×half @0, normals 3×sbyte @8, UVs 2×half @12,
  remaining stride bytes UNMAPPED (likely tangents + bone weights/indices).
  Indices: uint16 triangles. NO writer exists yet — that's our job.
- `.rrtex` (textures): READ works (decode to PNG). No writer yet.
- `.rrmaterial`: READ works. Skeletons/animations: no tooling anywhere.
- Generic `ChunkyFileWriter` exists and `RGDWriter` proves chunky writing
  round-trips — use as template.
- Game loads mods as plain `.sga` files inside subfolders of the local mods
  directory (same mechanism as mods downloaded from ageofempires.com).
  **Untested assumption #1:** a hand-packed `.sga` with replacement
  `art/**` paths overrides base assets via mod mount priority.

## Strategy

Round-trip patching: never build chunky files from scratch. Parse a real
donor file, swap only the buffers we understand, byte-copy everything else
(unknown chunks, trailing vertex bytes, header fields). This survives our
ignorance of the format's dark corners.

- **Phase 1 — texture swap PoC (DO THIS FIRST).** Build `RRTexWriter`
  (re-encode a PNG → BC-compressed `TMAN`/`TDAT` chunks, mirroring
  `RRTexReader`), repack one obviously-recolored unit texture into a local
  mod `.sga`, launch game, look at the unit. This proves untested
  assumption #1 with minimal format work. If loose-file or simple
  override doesn't work, try mirroring the exact folder/naming layout of an
  installed downloaded mod.
- **Phase 2 — rigid mesh swap.** Build `RRGeomWriter` (round-trip). Donor:
  a near-rigid siege unit (bombard / ribauldequin / trebuchet). Replace its
  vertex+index buffers with a tank mesh from Blender (export glTF; toolkit
  already converts rrgeom→glTF, we go the other way). For trailing vertex
  bytes, clone from the donor's nearest original vertex.
- **Phase 3 — full skinned custom units.** Requires decoding skeleton/anim
  formats. Out of scope until 1–2 work.

## Local setup steps

1. Clone this repo + branch `claude/aoe2-decompile-feasibility-74c1lp`.
2. Install .NET SDK (8+). Clone https://github.com/aoemods/AOEMods.Essence
   and build: `dotnet build AOEMods.Essence.sln -c Release`
   (CLI project: `AOEMods.Essence.CLI`). If it has bit-rotted against newer
   SDKs, pin the SDK version from its `global.json`/csproj.
3. Locate the game data, typically:
   `C:\Program Files (x86)\Steam\steamapps\common\Age of Empires IV\cardinal\archives\`
   (or the Xbox/MS Store equivalent). Unpack with
   `AOEMods.Essence.CLI sga-unpack <archive>.sga <outdir>` — start with the
   art/data archives and find one unit's `.rrgeom`, its `.rrtex` set, and
   `.rrmaterial`.
4. Locate the local mods dir, typically under
   `%USERPROFILE%\Documents\My Games\Age of Empires IV\mods\` — inspect how
   an installed subscribed mod is laid out (folder structure + its `.sga`)
   and mirror it exactly for our PoC archive.
5. Copy a few sample files (one rrgeom + textures + material, and one
   downloaded mod `.sga` for layout reference) into `aoe4-custom-assets/samples/`
   locally for development. **Do NOT commit/push extracted game assets** —
   they're Microsoft's copyright. `samples/` is for local use; add it to
   `.gitignore` first.

## Deliverables to build (in this repo)

- `aoe4-custom-assets/tools/` — either a fork/extension of AOEMods.Essence
  adding `RRTexWriter` + `RRGeomWriter`, or a standalone Python
  implementation if C# tooling is awkward; round-trip tests that
  re-emit an unmodified file byte-identical (the acceptance bar before
  trying anything in-game).
- Phase-1 PoC mod archive + a `BUILD.md` documenting the exact repack and
  install steps that made the game render the swapped texture.

## Constraints / reminders

- Local & skirmish-vs-AI use; not publishable via the official mod browser;
  untested in ranked MP (likely blocked or desync) — don't try ranked.
- Game patches can shift paths/format versions; keep samples + tool
  versions noted in `BUILD.md`.
- Ship only original art; never redistribute extracted assets.

# AoE4 Custom Asset Injection — Feasibility Research

Goal: get custom 3D models (modern units, tanks, etc.) rendering in Age of
Empires IV, despite the official Content Editor having no model-import
pipeline.

Status: **plausible path identified, unproven in-game.** Research date: 2026-06-12.

## Key findings

Based on inspection of [AOEMods.Essence](https://github.com/aoemods/AOEMods.Essence)
(MIT-licensed C# toolkit for AoE4's Essence engine formats):

1. **`.sga` archives: read AND write are solved.** `ArchiveWriter` produces
   complete archives including per-file CRCs (`FileVerificationType` supports
   `None`/`CRC`/hash-block modes). Modified or hand-built archives are
   producible today via `sga-pack`.

2. **The game loads local mod `.sga` files from a directory** —
   subscribed mods downloaded from ageofempires.com are just `.sga` files
   dropped into a subfolder of the local mods directory
   (see [this gist](https://gist.github.com/alyti/24459f6e2d5eba2cab10aca27d29470b)).
   If the engine resolves asset virtual paths through mounted mod archives
   with priority over base data (standard Relic behavior since Dawn of War),
   a hand-packed `.sga` containing replacement `art/**` files is a back door
   for custom assets. **This is the load-bearing untested assumption.**

3. **`.rrgeom` (model geometry) is mostly decoded — read-only so far.**
   `RRGeomReader` shows a Relic Chunky tree (`MESH → LOD → GEOM` with
   `GOHD`/`GEOB` chunks). Per-vertex layout: position = 3×half at offset 0,
   normals = 3×sbyte at offset 8, UVs = 2×half at offset 12, then
   `elementDataLength - 16` bytes of *unmapped* attributes (very likely
   tangents + bone indices/weights). Indices = uint16 triangles. This is a
   simple, fixed-stride format — not the hard part of the problem.

4. **Generic Relic Chunky write infrastructure already exists**
   (`ChunkyFileWriter`, working `RGDWriter`). An `RRGeomWriter` is a
   tractable engineering task, especially using a **round-trip strategy**:
   parse an existing donor `.rrgeom`, replace only the vertex/index buffers,
   preserve all unknown chunks and per-vertex trailing bytes verbatim.

5. **`.rrtex` (textures) and `.rrmaterial`: readers only.** Texture decode
   to PNG works, so encode (BC-compressed data back into `TMAN`/`TDAT`
   chunks) is the mirror-image task.

6. **Not decoded anywhere yet:** skeletons and animations. No community
   tooling handles them. This caps phase-2 ambitions at *mesh swaps that
   reuse existing skeletons/animations* — which is fine for vehicles:
   siege units (bombard, ribauldequin, trebuchet) are near-rigid donors
   ideal for tanks.

## Phased plan

| Phase | Goal | Risk |
|-------|------|------|
| 1 | **Texture-swap PoC.** Write `RRTexWriter`, repack one recolored unit texture into a local mod `.sga`, confirm the game renders it. Proves the override path end-to-end. | Medium — hinges on finding #2 |
| 2 | **Rigid mesh swap.** Write `RRGeomWriter` (round-trip patching). Replace a siege unit's mesh with a tank mesh authored in Blender, reusing the donor's skeleton, materials, and animations. | Medium |
| 3 | **Full custom skinned units.** Requires decoding the trailing vertex attributes + skeleton/animation chunky formats. | High / research-grade |

## Constraints (unchanged by any of this)

- Local/private use. Repacked-asset mods can't go through the official mod
  browser, and visual overrides are client-side only — fine for skirmish
  vs AI and probably observers; untested for ranked MP, where data checksum
  mismatches may block or desync.
- Every game patch can move file paths or bump format versions; the
  round-trip approach minimizes but doesn't eliminate breakage.
- Only ship original meshes/textures in the mod archive; never redistribute
  extracted game assets.

## What's needed to proceed

From a machine with AoE4 installed:
1. A handful of sample files extracted with AOEMods.Essence (`sga-unpack`):
   one unit's `.rrgeom`, its `.rrtex` set, and `.rrmaterial`.
2. The mods directory layout of an installed subscribed mod (folder names +
   one downloaded mod `.sga`) to mirror its structure for the PoC.
3. Someone to launch the game and report whether the phase-1 texture swap
   renders.

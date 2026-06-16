# Essay Tool

A personal web app for iterating on your college application essays with an AI
**Council**. It starts with the **Personal Statement** (the Common App essay).

You move an essay through three stages:

1. **Outline** — Write your own outline, or give the AI a topic and let it build
   one. Edit it freely.
2. **Draft & Council** — Pick the Common App prompt your essay answers, and the
   top Claude writing model (Opus 4.8) writes a full draft from your outline.
   From here you work the revision loop:
   - **The Writer** — give it notes ("tighten the opening", "cut the third
     paragraph") and it proposes a revised draft. You see the changes as a diff
     and **Accept** or **Discard** them — nothing is applied until you accept.
   - **The Council** — send the draft to the four-member Council. Members
     review the *same* draft **in sequence**, and each one sees the earlier
     members' notes so they build on each other. Each member gives a critique
     **and proposes concrete edits** on the essay; you **accept or reject each
     edit** individually (or "Accept all"), and accepted edits are applied
     straight into your draft.
   - **Apply the feedback** — have the Writer fold the Council's notes (plus any
     of your own) into a proposed revision, then accept or push back and send it
     to the Council again.
   - A **grammar pass** (LanguageTool + a Claude proofreading pass) checks
     mechanics and style.
3. **Edit** — Keep revising the essay yourself and looping it back through the
   Writer and Council. Every round is saved so you can see how the essay and the
   feedback evolve.

Each essay you create is saved; the home page lists them all so you can keep
iterating over the application season.

## The Council

Three AI editors, each with a distinct lens (chosen so the feedback doesn't
overlap):

| Critic | Lens |
| --- | --- |
| **The Dean (Community Fit)** | A senior administrator asking: will this person make our campus community better? Reads for character, generosity, curiosity, and red flags. |
| **The Admissions Reader** | A real admissions officer on their 50th essay of the day: does it stand out, reveal character, and avoid clichés? Judges the hook and the ending hard. |
| **The Skeptic** | The devil's advocate: hunts for overdone topics, empty bragging, "telling" instead of "showing," and anything that rings false — and says how to fix it. |
| **The AI-Tell Detector** | Trained on the known markers of AI-generated prose (tell-tale vocabulary like "tapestry"/"testament", antithesis templates, the rule of three, tidy-bow endings, em-dash overuse). Flags anything that would make an admissions reader suspect a bot wrote it, and suggests more human phrasing. |

The Council reviews **in the order the critics are listed**, and each member is
shown the earlier members' notes. You can change, reorder, add, or remove critics
by editing `COUNCIL` in [`src/lib/prompts.ts`](src/lib/prompts.ts). The Writer's
behavior lives in the same file (`WRITER_SYSTEM`).

## Tech

- **Next.js** (App Router) + **TypeScript** + **Tailwind CSS**
- **Prisma** + **SQLite** (zero-config locally; one file you can deploy anywhere)
- **@anthropic-ai/sdk** on `claude-opus-4-8` (adaptive thinking)
- **LanguageTool** for grammar mechanics
- Single-password login (one user)

## Running it locally

You need [Node.js 18+](https://nodejs.org) and an
[Anthropic API key](https://console.anthropic.com/settings/keys).

```bash
cd essay-tool
cp .env.example .env        # then edit .env (see below)
npm install
npm run db:push             # creates the SQLite tables
npm run dev                 # http://localhost:3000
```

Edit `.env`:

```
ANTHROPIC_API_KEY=sk-ant-...        # your key
APP_PASSWORD=pick-a-password        # what you'll type to log in
SESSION_SECRET=...                  # run the command below to generate
DATABASE_URL="file:./dev.db"        # fine as-is for local
```

Generate a session secret:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## Deploying it online

The app is a standard long-running Next.js server with a SQLite file, so it runs
on any host that gives you a **persistent disk** (Render, Railway, Fly.io, a VPS,
etc.). A `Dockerfile` is included.

### Deploy to Render (recommended)

A Render **Blueprint** lives at the repo root: [`render.yaml`](../render.yaml).
It defines the web service, a 1 GB persistent disk mounted at `/data`, and the
environment variables.

> ⚠️ The persistent disk requires a **paid instance** (Starter, ~$7/mo). On
> Render's free tier the disk is wiped on every deploy, which would delete your
> essays. The blueprint is set to `plan: starter` for this reason.

Steps:

1. Push this repo to GitHub (already done if you're reading this on GitHub).
2. In the Render dashboard: **New → Blueprint**, connect the repo, and pick the
   `essay-tool` branch. Render reads `render.yaml` and proposes the service.
3. Render will prompt for the two secret values (they're marked `sync: false`):
   - `ANTHROPIC_API_KEY` — your Anthropic key
   - `APP_PASSWORD` — the password you'll use to log in
   `SESSION_SECRET` is generated automatically; `DATABASE_URL` is preset to the
   disk.
4. Click **Apply**. The first build runs the Dockerfile, `prisma db push`
   creates the database on the disk, and the app starts.
5. Open the service URL, log in with your `APP_PASSWORD`, and start writing.

To update later, push to the `essay-tool` branch — `autoDeploy` is on, so Render
rebuilds automatically.

1. Set these environment variables on your host:
   - `ANTHROPIC_API_KEY`
   - `APP_PASSWORD`
   - `SESSION_SECRET`
   - `DATABASE_URL` — point it at a file on the persistent volume, e.g.
     `file:/data/essays.db`
2. Mount a volume at `/data` (so your essays survive restarts/redeploys).
3. Build & run the container (it runs `prisma db push` then `next start`):

```bash
docker build -t essay-tool .
docker run -p 3000:3000 --env-file .env -v $(pwd)/data:/data essay-tool
```

> **Note on Vercel:** Vercel's filesystem is ephemeral, so SQLite won't persist
> there. To use Vercel, switch the Prisma datasource to Postgres (e.g. Neon) and
> set `DATABASE_URL` to the Postgres connection string — the rest of the app is
> unchanged.

### Optional: self-hosted LanguageTool

The free public LanguageTool API is rate-limited. For heavy use, run your own and
point `LANGUAGETOOL_URL` at it:

```bash
docker run -d -p 8081:8010 erikvl87/languagetool
# then set LANGUAGETOOL_URL=http://localhost:8081/v2/check
```

## Project layout

```
essay-tool/
  prisma/schema.prisma         Essay / Revision / Critique / GrammarReport models
  src/
    lib/
      anthropic.ts             Claude client + completion helper (Opus 4.8)
      prompts.ts               Common App prompts, the 3 critics, stage prompts
      grammar.ts               LanguageTool + Claude proofreading
      auth.ts                  Signed session cookie (single password)
      db.ts                    Prisma client
      revisions.ts             Snapshot-per-review-round helper
    middleware.ts              Password gate for the whole app
    components/                Markdown renderer, ReviewPanel
    app/
      login/                   Login page
      page.tsx                 Dashboard (new essay + saved list)
      essay/[id]/              The editor (3-stage workspace)
      api/                     essays CRUD + outline/draft/council/grammar
```

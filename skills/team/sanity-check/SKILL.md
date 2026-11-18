---
name: sanity-check
description: >
  Run end-to-end sanity checks against the Keep platform after writing code. Deploys all services
  (infra + 4 repos) in noauth mode, then runs the committed Playwright + REST E2E suite in keep-ui
  (12 checks: send alert, change status/assignee, notes, incidents, dismiss, timeline, presets,
  dashboards, workflows) and triages any failures. Use after finishing a code change, before
  pushing/merging, or when the user says "run sanity checks", "sanity check", "verify the app works",
  or invokes /sanity-check.
compatibility: Requires Docker and Node (the keep-ui Playwright suite). The Playwright MCP is optional
  — only for the manual fallback. Windows (PowerShell) or bash.
---

# Keep Sanity Checks

Post-implementation gate. After code is written, **deploy every service** (in noauth mode) and **verify
all 12 sanity checks pass** by running the **committed Playwright + REST E2E suite** in `keep-ui`. The
agent runs the suite, reads the machine-readable results, and spends its reasoning only on *triaging
failures* — it does **not** hand-drive the UI on the happy path. Do not declare success until all 12 are
green (or explicitly reported as failing with detail).

> **This file is the single source of truth.** The repo-root `sanity_checks.txt` and
> `custom_workflow.txt` are scratch copies and may drift — when they disagree with this skill, this
> skill wins.

The flow is: **Step 0** preflight → **Step 0.5** locate repos → **Step 1** deploy → **Step 2** run the
suite + triage → **Step 3** report. The suite lives at `keep-ui/e2e/` (config `keep-ui/playwright.config.ts`)
and drives the live stack (UI :3000, gateway :8080, workflows :8081); it seeds and asserts backend state
via REST and asserts rendering via the browser. The Playwright **MCP** is now only a *manual fallback* for
reproducing a single failing check interactively — see the last section.

### Key UI routes (reference, base `http://localhost:3000`)

Useful when triaging a failure or driving the MCP fallback:

| Page | Route |
|---|---|
| Alerts feed (default view) | `/alerts/feed` |
| Saved preset / custom view | `/alerts/<preset-name>` |
| Incidents list | `/incidents` |
| Incident detail (tabs) | `/incidents/<id>/alerts`, `/incidents/<id>/timeline`, `/incidents/<id>/activity` |
| Dashboard | `/dashboard/<dashboard-name>` (created on the fly — there is **no** `/dashboard` index) |
| Workflows list | `/workflows` |
| Workflow detail | `/workflows/<workflow-id>` |
| Workflow run / execution | `/workflows/<workflow-id>/runs/<execution-id>` |
| Workflow visual builder | `/workflows/builder` |
| Providers / Rules / Settings | `/providers`, `/rules`, `/settings` |
| Mapping / Extraction / Dedup / Maintenance | `/mapping`, `/extraction`, `/deduplication`, `/maintenance` |

Presets are created and managed from the alerts feed (the preset list in the alerts sidebar); there is
no dedicated `/presets` page. Dashboards likewise have no index — create one, then it lives at
`/dashboard/<name>`.

## Step 0 — Preflight (fail fast before deploying)

Deploying 5 services is expensive; verify prerequisites first so a missing tool doesn't surface 3
minutes in.

1. **Suite runner available** — the checks run via `@playwright/test` in `keep-ui` (already a devDep). On
   the **first** run, install the browser once: `cd <root>/keep-ui && npm run test:e2e:install` (a one-time
   cost, not per-run). The Playwright **MCP** is *not* required for the suite — only for the manual fallback;
   don't block on it.
2. **Docker running** — `docker info` succeeds.
3. **Dependencies installed** — the deploy script auto-installs on first run (it runs `poetry install`
   in each Python repo when its venv is missing, and `npm install` in `keep-ui` when `node_modules` is
   missing), so you normally don't need to do anything here. Pass `-Install` / `--install` to force a
   reinstall after a dependency change.
4. **Service `.env` files present and consistent** — the deploy script validates each service's
   `<repo>/.env` and seeds a missing one from the bundled `scripts/env-templates/`. The templates carry
   **placeholder secrets** (e.g. `OPENAI_API_KEY=sk-REPLACE_ME`, `NEXTAUTH_SECRET=…generate-one`) — if a
   service was seeded from a template, fill those in before relying on AI/auth features. It also runs two
   consistency checks and **warns** on failure: (a) the gateway and event-handler must point at the **same
   database** (they share one, see gotchas), and (b) `keep-ui`'s `API_URL` must point at the gateway's real
   host:port (`http://localhost:8080`) — a stale value like `:8000` makes every UI call hit a dead port and
   the app looks broken though the backend is fine. You don't normally run anything here — it happens inside
   Step 1 — but if the script reports a seeded `.env`, a DB mismatch, or an `API_URL` mismatch, resolve it
   before trusting the checks.

## Step 0.5 — Ask the user where the Keep repos live

**Don't guess the repo location.** The skill is usually installed globally (e.g.
`~/.claude/skills/sanity-check/`), nowhere near the actual `keep-*` checkouts, so resolving paths
relative to this file lands in the wrong place. Instead, **ask the user once** for the absolute path to
the directory that *contains* the four repos (`keep-api-gateway`, `keep-event-handler`, `keep-workflows`,
`keep-ui`), then pass it to the deploy script on every invocation.

> e.g. "Where are your Keep repos? Give me the directory that contains `keep-api-gateway`,
> `keep-workflows`, etc. (something like `~/dev/keep`)."

Carry that path through as `--root <path>` (bash) / `-KeepRoot <path>` (PowerShell), or export
`KEEP_ROOT` so you don't have to repeat it. The script validates the four repos exist under it and exits
with a clear message if not — if that happens, re-ask rather than falling back to a guessed path. (If the
user runs the skill from inside a repo checkout and omits the path, the script falls back to sibling
resolution, but prefer the explicit path.)

## Step 1 — Deploy all services

Use the bundled deploy script — it checks whether the stack is **already up** (and just reuses it if so),
validates/seeds each service's `.env`, installs any missing deps, starts infra (Postgres + Kafka + Redis +
Pusher via `keep-event-handler/docker-compose.infra.yml`), loads each service's `.env` so it runs with the
config the app expects, launches all 4 services in the background with their real entrypoints (gunicorn for
the gateway/workflows, the Kafka consumer for the event-handler, `npm run dev` for the UI), and polls each
health endpoint. Run it from this skill's own `scripts/` directory, passing the repo root from Step 0.5:

```powershell
# Windows / PowerShell  (KEEP_ROOT = the dir containing the keep-* repos)
.\deploy.ps1 -KeepRoot C:\dev\keep            # reuse existing Postgres data
.\deploy.ps1 -KeepRoot C:\dev\keep -Clean     # opt-in: wipe volumes first for a deterministic run
.\deploy.ps1 -KeepRoot C:\dev\keep -Down      # tear everything down
```
```bash
# bash / WSL / CI  (--root = the dir containing the keep-* repos)
./deploy.sh --root ~/dev/keep            # reuse existing Postgres data
./deploy.sh --root ~/dev/keep --clean    # opt-in: wipe volumes first for a deterministic run
./deploy.sh --root ~/dev/keep --down     # tear everything down
```

**Idempotent startup:** if all four services already pass their health checks, the script prints
`Dev env already up — reusing it` and exits without redeploying — so re-running mid-session is cheap. If
the state is **ambiguous** (a partial or stale run — some ports held, not all healthy), it kills its own
tracked PIDs *and* force-frees the dev-env ports (8080, 8081, 8092, 8094, 3000) before starting clean.
Note that port-freeing kills whatever else is listening on those ports, so don't run unrelated services on
them during a sanity check.

The script waits until every service is healthy before returning:

| Service | URL | Launched as (dir) |
|---|---|---|
| API Gateway | `http://localhost:8080/healthcheck` | `poetry run gunicorn src.main:get_app --bind 0.0.0.0:8080 …` (`keep-api-gateway`) |
| Workflow Engine | `http://localhost:8081/healthcheck` | `poetry run gunicorn src.main:app --bind 0.0.0.0:8081 …` (`keep-workflows`) |
| Event Handler | `http://localhost:8092/healthz` | `poetry run python -m src.consumer_main` (`keep-event-handler`) |
| UI | `http://localhost:3000` | `npm run dev` (`keep-ui`) |

**Clean state:** by default the script reuses the existing Postgres volume (fast). Stale data can make
checks pass/fail spuriously — when you need deterministic results (or a second run is colliding), pass
`-Clean` / `--clean` to wipe volumes first. This is opt-in because it destroys all data in that Postgres.

The deploy must finish with **all four healthy** before Step 2 — the suite's own `global-setup` re-checks
health and that the stack is in **noauth** mode, and aborts with a clear message otherwise.

### ⚠️ Gotchas

- **Every Python service must share ONE database.** When `DATABASE_CONNECTION_STRING` is unset the
  services fall back to `sqlite:///./keep.db` (`keep-workflows/src/common/core/db_utils.py`) — alerts then
  write to a private SQLite file and never appear in the shared DB/UI. Just as bad: pointing services at
  *different* Postgres databases (a real trap — the stock event-handler `.env` ships
  `…/keep_bench` while the gateway uses `…/keep`). The gateway ingests into one DB, the event-handler
  consumer writes to the other, and the alert silently never surfaces. The deploy script's shared default
  and bundled templates all use `…/keep`, and it **warns** if the gateway and event-handler `.env`s
  disagree. If you start a service by hand, point it at `postgresql://keep:keep@localhost:5432/keep`.
- **Ports must not collide.** Gateway binds **8080**, workflows **8081**, UI **3000**. The event-handler
  exposes a health endpoint and Prometheus metrics — its `.env` puts these on **8092 / 8094** to stay
  clear of the gateway/workflows. (A bare gunicorn `--bind 0.0.0.0:8080` for *both* gateway and workflows
  is a copy-paste trap — only one can own 8080; workflows is 8081.) Health is polled at `:8092/healthz`.
- **UI must point at the gateway's port.** `keep-ui/.env` `API_URL` has to be `http://localhost:8080`
  (the gateway). A stale `:8000` makes every UI request hit a dead port and the app looks broken even
  though the backend is healthy.
- **Auth — noauth still needs a token for ingestion.** Even with `AUTH_TYPE=noauth`/`NOAUTH`, the gateway
  rejects an unauthenticated `POST /alerts/event` with **`Missing API Key`**. The UI works because the
  browser session carries a bearer token for the anonymous tenant; ingestion via `curl` must send the same
  token (see *Sending a test alert*). If a repo's own `.env` forces a *different* auth type, calls will
  401 — reconcile before testing.

## Step 2 — Run the suite + triage

The 12 checks are a committed Playwright + REST suite in **`keep-ui/e2e/`**. Run it against the live stack
from the repo root you used in Step 1:

```bash
cd <root>/keep-ui && npm run test:e2e
```

Connection settings default to the local stack (UI `:3000`, gateway `:8080`, workflows `:8081`,
`x-api-key=keep-sanity-check`); override with `UI_BASE_URL` / `GATEWAY_URL` / `WORKFLOWS_URL` / `KEEP_API_KEY`
if needed. The suite **seeds and asserts backend state via REST** (no UI token needed — it uses `x-api-key`)
and **asserts rendering via the browser**; `global-setup` first re-checks health + noauth and aborts early
with a clear message if the stack isn't ready. Specs run serially (shared DB) and each check isolates with
its own unique fingerprints.

**Read the results, don't re-run blindly.** The run writes a flat, machine-readable file:

```
<root>/keep-ui/e2e/results/checks.json
# { summary:{total,passed,failed}, checks:[ {id,name,status,durationMs,error}, … ] }
```

Read `checks.json`. If `summary.failed === 0`, all 12 passed — go to Step 3. Otherwise **spend reasoning
only on the failed checks**: read each failed check's `error`, open its trace
(`e2e/results/artifacts/<test>/trace.zip` via `npx playwright show-trace <zip>`, or the HTML report at
`<root>/keep-ui/playwright-report/`), and cross-reference the service logs in `<root>/.sanity-run/*.log`
using the triage table below. Iterate on one check with
`npm run test:e2e -- e2e/specs/02-change-status.spec.ts`.

### The 12 checks (what each verifies)

| # | Spec | Verifies |
|---|---|---|
| 1 | `01-send-alert` | ingested alert lands `firing` (REST) and renders in the feed |
| 2 | `02-change-status` | status change via UI persists (REST) and re-renders |
| 3 | `03-change-assignee` | single + bulk self-assign persist for all alerts |
| 4 | `04-add-note` | note persists (enrichment) and renders |
| 5 | `05-create-incident` | incident created via UI persists (REST) and lists |
| 6 | `06-dismiss` | permanent + dismiss-until both persist |
| 7 | `07-timeline` | ordered mutations produce a monotonic, rendered timeline |
| 8 | `08-incident-preset-group` | incidents preset groups by a shared field (facets panel) |
| 9 | `09-application-column` | seeded `application` value renders in its column |
| 10 | `10-create-dashboard` | dashboard persists (REST) and renders |
| 11 | `11-create-preset` | preset persists (REST) and is selectable |
| 12 | `12-workflow` | barbor workflow runs `success` **and** flips its trigger alert to `resolved` |

To change *what* a check does, edit its spec in `keep-ui/e2e/specs/`; shared REST helpers live in
`keep-ui/e2e/fixtures/keep-api.ts`.

---

## Manual fallback — Playwright MCP

Everything below is the **legacy hand-driven path**, kept only for *reproducing a single failing check
interactively* while triaging. The automated suite (Step 2) does not use it. Requires the Playwright MCP
(`mcp__playwright__browser_*`). Note one difference: the manual path ingests with a captured **bearer
token**, whereas the suite uses `x-api-key`.

Pattern for a manual check: `browser_snapshot` to find the control → act (`browser_click` / `browser_type`
/ `browser_fill_form` / `browser_select_option`) → `browser_snapshot` again to confirm the rendered state →
`browser_take_screenshot` for evidence. Use `browser_console_messages` to catch client-side errors and
`browser_wait_for` for the async pipeline.

### Sending a test alert (fallback)

Checks 1–6 and 12 each start by ingesting an alert. Endpoint: **`POST /alerts/event`** on the gateway
(returns `202`). Required `AlertDto` fields: `name`, `status`, `severity`.

**Ingestion needs the noauth bearer token.** Even under `AUTH_TYPE=noauth` the gateway answers a tokenless
`POST` with `Missing API Key`. The UI's own requests succeed because the browser session carries a bearer
token for the anonymous tenant — reuse that same token for `curl`. It decodes to the identity
`{"tenant_id":"keep","user_id":"keep-user-for-no-auth-purposes"}` (tenant **keep**); that's how you
recognize the right one. Grab the live value once, before Check 1, and reuse it for every ingest:

- **Preferred — read it from the authenticated browser session** (you're already on the UI for the
  checks). Capture the `Authorization: Bearer …` header the UI sends on any backend XHR via
  `browser_network_requests` if your Playwright MCP exposes it; otherwise `browser_evaluate` the NextAuth
  session, e.g. `await (await fetch('/api/auth/session')).json()` and read its `accessToken`.
- Stash it in a shell var and send it on **every** ingest call:

```bash
KEEP_TOKEN='<bearer captured from the UI session>'   # decodes to tenant "keep" / keep-user-for-no-auth-purposes
```

**Use a fresh alert per mutating check — do not share one alert across checks.** Each check that
changes an alert (status, assignee, note, incident membership, dismissal) must ingest its **own** alert
with a unique `name` + `fingerprint` (e.g. `sanity-status-1`, `sanity-assign-1`, `sanity-dismiss-1`).
Sharing one alert causes cross-check interference — e.g. dismissing in check 6 would hide the alert the
earlier checks act on.

**Compute `lastReceived` relative to "now" — never hardcode a date.** A fixed date goes stale, and a
date in the future (watch local-vs-UTC offset) scrambles the timeline ordering that check 7 verifies.
Use the **current UTC time** for normal alerts; for the barbor alert, set `lastReceived` to a time
**well in the past** so its expiry has already lapsed (see below).

Base payload (substitute the current UTC timestamp and a per-check name/fingerprint):

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
curl -s -X POST http://localhost:8080/alerts/event \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $KEEP_TOKEN" \
  -d "{
    \"name\": \"sanity-status-1\",
    \"status\": \"firing\",
    \"severity\": \"critical\",
    \"source\": [\"sanity-check\"],
    \"lastReceived\": \"$NOW\",
    \"fingerprint\": \"sanity-status-1\"
  }"
```

For the **workflow check (12)** the alert must also carry the fields barbor filters on — `operator:
"bar"`, `status: "firing"`, and an **already-lapsed** `expiry_in_minutes`. Set `lastReceived` far enough
in the past that `lastReceived + expiry_in_minutes < now` (here: 1h ago with a 1-minute expiry):

```bash
PAST=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)   # GNU date; PowerShell: (Get-Date).ToUniversalTime().AddHours(-1)
curl -s -X POST http://localhost:8080/alerts/event \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $KEEP_TOKEN" \
  -d "{
    \"name\": \"barbor-trigger\",
    \"status\": \"firing\",
    \"severity\": \"warning\",
    \"operator\": \"bar\",
    \"expiry_in_minutes\": 1,
    \"lastReceived\": \"$PAST\",
    \"fingerprint\": \"barbor-trigger-1\"
  }"
```

### Async pipeline — poll, don't snap-and-fail

Ingestion is async: **Gateway → Kafka → event-handler → Postgres → UI**. A `browser_snapshot` taken
immediately after `POST /alerts/event` may show nothing yet. For every check that waits on ingested
data, **poll up to ~30s** (re-navigate/re-snapshot, or use `browser_wait_for`) before recording a
failure. A check fails only if the expected state is still absent after the retry window.

### Snapshots — one folder per run

Save a screenshot for every check as visual evidence. Create **one folder per run** under `snapshots/`
(at the repo root), named with the run's **UTC start timestamp**, colons replaced by dashes so it is
filesystem-safe on Windows:

```
snapshots/2026-06-08T13-45-22Z/
  01-send-alert.png
  02-change-status.png
  ...
  12-workflow.png
  summary.md          # the Step 3 report, co-located with its evidence
```

- Decide the run folder name **once** at the start of Step 2 (current UTC time → `YYYY-MM-DDThh-mm-ssZ`)
  and reuse it for every screenshot and the summary, so a run is fully self-contained and runs sort
  chronologically.
- File names are `NN-<check-slug>.png` where `NN` is the zero-padded check number (01–12) — the index
  maps 1:1 to the checklist below, so missing evidence is obvious at a glance.
- Take each shot with `browser_take_screenshot`, passing the path
  `snapshots/<run-id>/NN-<slug>.png` as the `filename`. If your Playwright MCP only accepts a flat
  filename (no sub-paths), encode the run id into the name instead: `<run-id>__NN-<slug>.png` and keep
  them in one `snapshots/` folder.

### Manual 12-check walkthrough (fallback)

The hand-driven version of the checks, for interactive triage. Capture the noauth bearer token first (see
above), then work through every item in order, verifying each rendered with `browser_snapshot` and saving
a `NN-<slug>.png` screenshot. Mutating checks each ingest their **own** fresh alert.

1. **Send alert** — ingest a test alert (with the `Authorization: Bearer $KEEP_TOKEN` header); confirm it
   appears in the alerts feed (poll per above).
2. **Change status** — change an alert's status; confirm the new status renders.
3. **Change assignee** — assign one alert, then select a group of alerts and bulk-assign; confirm both.
4. **Add note** — add a note to an alert; confirm it shows in the alert's activity/notes.
5. **Create incident** — create an incident (from alerts or directly); confirm it appears in incidents.
6. **Dismiss an alert** — dismiss **both** ways: permanent and dismiss-until (timed); confirm each
   dismissal state. (Legacy `dismissed: true` ≡ `dismiss_mode: permanent`.)
7. **Timeline correct** — open an alert/incident timeline; confirm events are present and ordered right.
8. **Incident preset column + group** — on the incidents preset, add a column and group by that group;
   confirm grouping renders.
9. **Application column** — add the `application` column to a preset; confirm the column shows values.
10. **Create a dashboard** — create a dashboard; confirm it saves and renders.
11. **Create a preset** — create a new preset (saved filter/view); confirm it persists and is selectable.
12. **Create + trigger a workflow** — at `/workflows`, click **Upload Workflow** and paste the barbor
    YAML below into the modal's text area (or drop it as a `.yml` file); on submit you're redirected to
    the workflow detail page. Then trigger it via its **manual** trigger (no need to wait for the 120s
    interval). First ingest the `barbor-trigger` alert above (already-lapsed expiry). Fire the workflow
    manually and confirm it **runs**: the execution results show a successful run with zero errors **and**
    — back in `/alerts/feed` — the alert's status visibly flips to **resolved** (the enrichment actually
    landed, not just that the run reported success). Poll both views per the async note.

    **Workflow-ID collision:** the YAML pins a fixed `id`. A second run can collide with the workflow
    created last time. Before creating it, **delete any existing "barbor" workflow** (or run the deploy
    with `--clean` to start from an empty DB), then create fresh.

    ```yaml
    workflow:
      id: ee8a180b-add9-4bc3-81ca-de0898878652
      name: barbor
      description: bb
      disabled: false
      triggers:
        - type: manual
        - type: interval
          value: "120"
      inputs: []
      consts: {}
      owners: []
      services: []
      steps:
        - name: get-alerts
          provider:
            type: keep
            config: "{{ providers.default-keep }}"
            with:
              filter: operator == "bar" && status == "firing" && expiry_in_minutes
              version: 2
        - name: python-step
          foreach: "{{ steps.get-alerts.results }}"
          if: (keep.to_timestamp("{{foreach.value.lastReceived}}") + ({{foreach.value.expiry_in_minutes}}*60)) < keep.to_timestamp(keep.utcnow())
          provider:
            type: python
            config: "{{ providers.default-python }}"
            with:
              code: f"{{foreach.value.name}}"
              enrich_alert:
                - key: status
                  value: resolved
                  disposable: true
      actions: []
    ```

## Step 3 — Report

Summarize the 12 checks with ✅/❌ — one line each — sourced from `checks.json` (`checks[].status` and,
for failures, `checks[].error`). Write the same summary to `summary.md` under
`<root>/snapshots/<run-id>/` (run id = the run's UTC start, colons → dashes) so the report sits with the
suite's artifacts. For each ❌ include the `error`, the likely cause (triage table), and a pointer to its
trace. Do **not** report the task complete unless `summary.failed === 0` (all 12 green).

## Triage — common failure → likely cause

| Symptom | Likely cause | Fix |
|---|---|---|
| Service won't start, "address already in use" | Port 8080/8081/8092/3000 taken, or two services bound to the same port | Kill the stale process (`deploy -Down`/`--down`), re-run; confirm gateway=8080, workflows=8081, event-handler health=8092 |
| Alert ingested but never shows in UI | event-handler (Kafka consumer) down, **or services on different DBs** (gateway `keep` vs event-handler `keep_bench`), or DB on SQLite | Check `.sanity-run/event-handler.err.log`; confirm all `.env`s use `…/keep` (the script warns on mismatch) |
| UI loads but every request fails / no data | `keep-ui/.env` `API_URL` points at the wrong port (e.g. `:8000`) | Set `API_URL=http://localhost:8080`; check `browser_console_messages` for failed calls |
| `Missing API Key` on `POST /alerts/event` | Ingesting without the noauth bearer token (the UI carries one, curl doesn't) | Capture the UI session's `Authorization: Bearer` token (decodes to tenant `keep`) and send it on every ingest — see *Sending a test alert* |
| Repos not found / wrong path on deploy | `--root` / `KEEP_ROOT` not passed (or wrong); skill guessed its own install dir | Re-ask the user for the dir containing the `keep-*` repos and pass `--root <path>` / `-KeepRoot <path>` |
| Workflow created but never runs / no alerts visible to it | Workflow service on SQLite fallback or a different DB from the gateway | Confirm workflows launched with the shared `DATABASE_CONNECTION_STRING`; check its startup log for the Postgres connection |
| Playwright tools missing / `browser_*` errors | Playwright MCP not connected | Stop, ask user to connect the MCP (Step 0) |
| Snapshot shows nothing right after ingest | Async pipeline lag, snapped too early | Poll up to ~30s before failing |
| Second run: workflow create fails on duplicate id | Fixed `id` in barbor YAML collides with prior run | Delete existing barbor workflow, or deploy `--clean` |
| 401 on `POST /alerts/event` | A repo `.env` overrides `AUTH_TYPE` away from noauth | Set `AUTH_TYPE=noauth` (or supply a valid token) |
| Dev env "already up" but checks behave oddly | Script reused a stale/misconfigured running stack | Re-run with `--clean` / `-Clean` to force a fresh deploy |

## Notes
- Deployed services keep running until you tear down with `deploy -Down` / `--down`.
- Logs + PIDs live in `<repo-root>/.sanity-run/`.

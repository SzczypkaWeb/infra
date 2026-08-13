# Runbook

A single file collecting decisions about the workflow that would otherwise be
scattered across each repo's `DECISIONS.md`, comments in workflow files, and
`e2e-tests/OUTAGE_RECOVERY_PLAN.md` (that last one stays as a one-off,
point-in-time checklist for the end of a specific GitHub Actions outage —
this file is the durable one, describing how the flow is meant to work
long-term).

State as of: 2026-08-07. Repos: `backend`, `frontend-shell`, `react-app`,
`next-app`, `shared-ui`, `e2e-tests`, `orchestrator`, `infra` (this one).
`ai-service` exists as a separate microservice (FastAPI + LangGraph,
`/classify-listing`), but isn't part of any of the pipelines below yet.

## 1. Repos and deploy targets

| Repo | Stack | Prod deploy | Staging deploy |
|---|---|---|---|
| `backend` | Nest.js + Prisma (Postgres/Supabase) | GCP Cloud Run, service `backend`, push to `main` | GCP Cloud Run, service `backend-staging`, push to `staging` |
| `frontend-shell` | React + webpack (MF host) | Azure Static Web Apps, push to `main` | Azure Static Web Apps, **named environment** `staging` (same resource, push to `staging`) |
| `react-app` | React + webpack (MF remote) | Azure Static Web Apps, push to `main` | Azure Static Web Apps, **named environment** `staging` (same resource, push to `staging`) |
| `next-app` | Next.js (marketing/SEO) | Vercel (git integration) | Vercel git branch URL, automatic, zero config — `https://next-app-git-staging-<team>.vercel.app` just from pushing to `staging` |
| `shared-ui` | Component library (Tailwind v4, tsup) | GitHub Packages (`@szczypkaweb/shared-ui`), via Changesets | — (a library, no "staging" concept) |
| `e2e-tests` | Playwright | — (tests the other environments) | — |

## 2. Where each piece of config lives

Three different places — when something's broken, the first question is
"which of these three is it missing from":

1. **GCP Secret Manager** — backend runtime secrets. Prod: `DATABASE_URL`,
   `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_CALLBACK_URL`,
   `FRONTEND_ORIGIN`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `SENTRY_DSN`.
   Staging: the same names with a `_STAGING` suffix — **must be created
   manually before `deploy-gcp-staging.yml` is used for the first time**,
   they don't exist yet.
2. **GitHub Secrets per repo** — deploy tokens, not application runtime data:
   `AZURE_STATIC_WEB_APPS_API_TOKEN`, `PACKAGES_READ_TOKEN` (registry
   `npm.pkg.github.com`), `E2E_DATABASE_URL_STAGING` (passed through to e2e —
   **not set yet**, see `deploy-gcp-staging.yml`).
3. **GitHub Environments** (`staging`/`production`/`preview`, per repo) —
   gates (required reviewers). Workflows reference them, GitHub creates them
   automatically on first use, but without manual configuration they **block
   nothing**. Not verified whether they're actually configured.

Backend → GCP auth: Workload Identity Federation (keyless, `repository`
attribute from the GitHub Actions OIDC token) — not a static service account
key. Provider:
`projects/416578348143/locations/global/workloadIdentityPools/github-pool/providers/github-provider`,
service account `github-actions-backend-deploy@szczypka-web-backend.iam.gserviceaccount.com`.

## 3. Deployment URLs: where they live and how to change them conveniently

A question that keeps coming back sooner or later: backend redirects after
login to `localhost:8080` instead of the real frontend-shell — because
nobody updated `FRONTEND_ORIGIN` in GCP Secret Manager after the first Azure
deploy. That's not a one-off - production URLs for each service live in
**four different, disconnected places**, and every change (new region, new
custom domain, moving hosting) means updating all of them manually,
separately:

1. **GCP Secret Manager** (backend, section 2) — `FRONTEND_ORIGIN` (CORS +
   post-OAuth redirect), `GOOGLE_CALLBACK_URL` (also has to be registered in
   Google Cloud Console as an authorized redirect URI — two places to keep in
   sync every time).
2. **GitHub Actions repo variable** (`frontend-shell`) — `REACT_APP_REMOTE_URL`,
   points at the deployed `react-app` (Module Federation remote).
3. **Vercel environment variable** (`next-app`, in the Vercel dashboard,
   outside this repo's files) — `NEXT_PUBLIC_APP_URL`, points at
   `frontend-shell`.
4. **Local `.env`** (`e2e-tests`) — `MARKETING_URL`/`APP_URL`/`API_URL`, has
   to be rewritten by hand every time you run against a different environment.

After changing (1), remember to force a new Cloud Run revision
(`gcloud run services update backend --region=europe-central2
--update-secrets=FRONTEND_ORIGIN=FRONTEND_ORIGIN:latest`) — `--set-secrets`
at deploy time reads the secret once, at revision creation, it doesn't
refresh on its own.

**The real, structural fix: a custom domain.** Instead of remembering/
syncing platform URLs (`*.azurestaticapps.net`, `*.run.app`, `*.vercel.app` —
which change with every new region/resource), put every service behind a
fixed subdomain: `domain.pl` (next-app), `app.domain.pl` (frontend-shell),
`api.domain.pl` (backend). Azure Static Web Apps, Cloud Run, and Vercel all
support custom domains for free (aside from the cost of the domain itself,
~a few tens of PLN/year). Result: you enter these values ONCE in all four
places above, and swap the DNS pointing underneath (Azure/GCP/Vercel)
without touching any app config — this is also exactly what's needed for the
session cookie (`Domain=.domain.pl`) to actually work between next-app and
frontend-shell (see e2e-tests/README.md, cookie section), so it'll need doing
anyway.

Until there's a domain: what exists now (manual sync + this section as a
"where to check" checklist) is the most pragmatic option — it's not worth
building automation (e.g. cross-repo URL propagation via
`repository_dispatch`) for values that will become constants anyway once a
domain is wired up.

## 4. Branch strategy

`main` = production, `staging` = pre-prod. Intent: feature branch → PR to
`staging` → merge → auto-deploy staging → e2e gate → promote to `main`
(currently in `backend/.github/workflows/deploy-gcp-staging.yml` this is a
**placeholder** `echo`, not a real auto-PR/auto-merge — the decision "should
promote be fully automatic" hasn't been made yet, deliberately).

**To verify manually:** branch protection on `main`. `infra/DECISIONS.md` has
a lone note "Require pull request before merging + Require approvals" with no
date and no repo assigned — unclear whether this was actually applied or is
just a noted plan. Without it, `main`/`staging` is just a naming convention,
nothing physically prevents a direct push to `main`.

`backend`, `react-app`, `frontend-shell` now have a working `staging` branch
pipeline (#45 done for this trio). `next-app` doesn't need its own workflow —
Vercel gives a stable per-branch URL for free, no repo config (see section 1).

## 5. shared-ui: release flow

The repeatable cycle every time a component in the library changes:

1. Change in `shared-ui` + `changeset add` (describes the change, bumps the
   version per semver)
2. commit → push to `main`
3. Release workflow (Changesets) builds and publishes to `npm.pkg.github.com`
4. In each of the three consumers (`frontend-shell`, `react-app`, `next-app`):
   `pnpm install` (pulls the new version) → `pnpm test` → `pnpm build` →
   commit the `package.json` bump → push

Step 4 isn't automated yet — each app has to do it by hand after publishing.
That's exactly the problem Dependabot/Renovate solves (proposed, not
implemented): an auto-PR bumping `@szczypkaweb/shared-ui` in each of the
three repos whenever a new version lands on the registry.

Published library subpaths (beyond the components themselves):
`./globals.css` (shared design tokens) and `./postcss.config` (shared plugin
config) — both exist specifically so these three apps don't have to keep
separate copies of the same values.

## 6. CI/CD per app

**backend** — two separate workflow files, deliberately not one with a branch
condition (zero risk that a staging change affects prod):
- `deploy-gcp.yml`: push to `main` → test (lint+jest) → build+push image
  (tags `:sha` and `:latest`) → `gcloud run deploy backend` (deploys by the
  `:sha` tag, not `:latest` — `:latest` exists only for readability in
  Artifact Registry)
- `deploy-gcp-staging.yml`: push to `staging` → test → build+push image (tag
  `staging-:sha`, no `:latest`) → `gcloud run deploy backend-staging` → e2e
  (reusable workflow from `e2e-tests`) → `promote-to-main` (placeholder,
  gated on `needs.e2e.result == 'success'`)

**Prisma migrations are part of both workflows** (`prisma migrate deploy`,
the "Run database migrations" step), run BEFORE the image build/deploy — the
code at a given SHA may already assume the new schema. `DATABASE_URL` for
migrations is fetched straight from GCP Secret Manager
(`gcloud secrets versions access`) on the runner, masked in logs, passed to
later steps via `$GITHUB_ENV` (not a step output — shorter-lived). **Requires**
that `github-actions-backend-deploy@` (the WIF service account) has the
`roles/secretmanager.secretAccessor` role on `DATABASE_URL`/`DATABASE_URL_STAGING` -
Cloud Run deploy hasn't needed this so far (`--set-secrets` only references
the secret by name), so this permission may need to be granted manually in
GCP IAM if the step fails with "Permission denied".

**react-app** — `azure-static-web-apps.yml`: push to `main` → prod deploy
(`environment: production`), push to `staging` → deploy to a persistent
**named environment** `staging` (`deployment_environment: staging`, same SWA
resource, stable URL `<default-host>-staging.<region>.azurestaticapps.net`,
no extra cost), PR → ephemeral preview deploy (`environment: preview`,
Azure's own per-PR mechanism, unrelated to the `staging` branch). After every
push: the "Surface deployed URL" step prints the URL to the Job Summary —
the value to plug in manually as `REACT_APP_REMOTE_URL` (prod) /
`REACT_APP_REMOTE_URL_STAGING` (staging) in frontend-shell. After a staging
deploy: the `e2e` job (`needs: build_and_deploy_job`,
`if: github.ref == 'refs/heads/staging'`) calls `e2e-tests` as a
`workflow_call` with `app_url`/`api_url` from repo Variables
(`FRONTEND_SHELL_STAGING_URL`, `BACKEND_STAGING_URL`) — re-validates the
whole staging stack, because Module Federation loads `remoteEntry.js` at
runtime, so a react-app-only change never forces a frontend-shell redeploy.

**frontend-shell** — `azure-static-web-apps.yml`, same pattern as react-app:
prod / staging (named environment) / PR preview. The staging build takes a
separate set of variables (`REACT_APP_REMOTE_URL_STAGING`, `API_URL_STAGING`),
so staging frontend-shell talks to staging react-app and backend, not
production. Also calls `e2e-tests` after a staging deploy (same pattern as
react-app). Has a `staticwebapp.config.json` (CORS on its own
`remoteEntry.js` + SPA fallback).

**next-app** — Vercel git integration, outside this repo (configured in the
Vercel dashboard, not in repo files). Staging = just push to the `staging`
branch, Vercel gives a stable URL on its own
(`https://next-app-git-staging-<team>.vercel.app`) with zero config. Not
wired into `e2e-tests` as a trigger (the `marketing` project doesn't depend
on the backend/frontend-shell, low priority — worth revisiting later, not
done).

**Required repo Variables/Secrets (Settings → Secrets and variables →
Actions), manually, per repo — not set anywhere yet:**

| Repo | Variables | Secrets |
|---|---|---|
| `react-app` | `FRONTEND_SHELL_STAGING_URL`, `BACKEND_STAGING_URL` | `E2E_DATABASE_URL_STAGING` (optional) |
| `frontend-shell` | `REACT_APP_REMOTE_URL_STAGING`, `API_URL_STAGING`, `FRONTEND_SHELL_STAGING_URL` | `E2E_DATABASE_URL_STAGING` (optional) |
| `backend` | `FRONTEND_SHELL_STAGING_URL` | `E2E_DATABASE_URL_STAGING` (already a known gap, see section 9) |

The URL values (`FRONTEND_SHELL_STAGING_URL`, `BACKEND_STAGING_URL`) come
from the Job Summary of each service's first successful staging deploy (see
the "Surface deployed URL..." steps above, and "Fetch DATABASE_URL..." in
`deploy-gcp-staging.yml`) — there's no automatic propagation between repos
yet (see section 3, the same trade-off as for production URLs).
`E2E_DATABASE_URL_STAGING` is the same Postgres as `DATABASE_URL_STAGING`
(section 2) — without it, the `app` project in e2e-tests is safely skipped,
the job doesn't fail.

## 7. E2E (Playwright, `e2e-tests` repo)

Three projects: `marketing` (next-app only), `app` (frontend-shell + a real
backend+DB), `flows` (cross-domain, next-app → frontend-shell).

`app` uses a Playwright "setup project" (`auth.setup.ts`) + "teardown
project" (`auth.teardown.ts`) to seed/clean the fixture user directly in
Postgres — scoped EXCLUSIVELY to the `app` project (`dependencies`/`teardown`
in `playwright.config.ts`), so `marketing`/`flows` never touch Postgres, even
indirectly. This replaces the older top-level `globalSetup`/`globalTeardown`,
which ran on EVERY run regardless of `--project` — side effect: **nightly CI
(the `schedule` in `e2e.yml`) was probably red for a long time**, because
`E2E_DATABASE_URL` was never set as a secret in this repo, and the old
`globalSetup` threw on startup regardless of which projects were actually
going to run. The new version doesn't do that.

`e2e.yml` always runs `marketing`+`flows`; `app` joins **conditionally** —
only when the `E2E_DATABASE_URL` secret is actually passed (a safe fallback,
not an error, when it's missing). Can be called as a `workflow_call`
(preferred — `needs.e2e.result` in the same CI run, see
`deploy-gcp-staging.yml`) or `repository_dispatch` (fallback, no feedback
loop).

**Current state:** #45 is done — `deploy-gcp-staging.yml`, and both Azure
workflows (react-app, frontend-shell), now actually call `e2e` after their
staging deploy (`app_url`/`api_url`/`E2E_DATABASE_URL` uncommented/wired up).
This doesn't work end-to-end yet, since none of the required repo
Variables/Secrets (table in section 6) are set — until then, `app` in
e2e-tests is safely skipped (empty `E2E_DATABASE_URL`), `marketing`+`flows`
still run.

**Requires:** `e2e-tests` (`marketplace-e2e`) must have Settings → Actions →
Access allowing access from repos in the `szczypkaweb` organization —
otherwise the cross-repo `workflow_call` gets a 404/permission error.

## 8. Rollback — GCP Cloud Run (the only environment that's actually live)

Azure: there's no equivalent of `update-traffic`/revisions — SWA only keeps
the "current" content per environment (production/staging/preview), so the
only real rollback is redeploying the previous good commit:

```bash
git checkout <PREVIOUS_GOOD_SHA> -- .
git commit -m "revert: rollback to <PREVIOUS_GOOD_SHA>"
git push origin main   # or staging, depending on the environment
```

...which just triggers the normal deploy workflow with that code state.
There's no equivalent of "switch traffic without rebuilding" like Cloud Run
has (8.1) — every rollback on Azure SWA is a full redeploy. TBD: confirm this
in practice after the first real incident, this section is theoretical
(untested).

Cloud Run keeps revision history by default (nothing auto-deletes), and
`gcloud run deploy` always references the image by its immutable `:sha` tag
(not `:latest`) — so rolling back the app itself is fast and safe, **as long
as a database schema change isn't involved**.

### 8.1. Quick rollback (previous revision still exists)

```bash
# See available revisions (prod: backend, staging: backend-staging)
gcloud run revisions list --service=backend --region=europe-central2

# Switch 100% of traffic to the previous known-good revision
gcloud run services update-traffic backend \
  --region=europe-central2 \
  --to-revisions=<REVISION_NAME>=100
```

This does NOT create a new deploy or build anything — it just switches
traffic. Fastest option, use it by default.

### 8.2. Rollback via redeploy (revision deleted / you want a fresh deploy of a specific SHA)

```bash
# Find the last good SHA - deploy history in GitHub Actions (Actions tab ->
# deploy-gcp.yml) or tags in Artifact Registry:
gcloud artifacts docker images list \
  europe-central2-docker.pkg.dev/szczypka-web-backend/backend/api \
  --include-tags

# Redeploy that specific image
gcloud run deploy backend \
  --image=europe-central2-docker.pkg.dev/szczypka-web-backend/backend/api:<PREVIOUS_SHA> \
  --region=europe-central2
```

Same for staging: `backend-staging` + tag `staging-<PREVIOUS_SHA>`.

### 8.3. WARNING: rolling back code ≠ rolling back the database

`prisma migrate deploy` is now part of both workflows (section 6), but that
does NOT mean rolling back a Cloud Run revision automatically undoes a
migration that already ran against the database — `migrate deploy` has no
"down" mode, it only applies forward. If the problem you're rolling back
involves a schema change:

1. First check whether the old code even works against the new schema (if
   the migration was backward-compatible — usually it should be — rolling
   back Cloud Run alone is enough, see 7.1/7.2).
2. If not: you need to separately roll back the migration
   (`prisma migrate resolve` + a manual `DOWN` SQL — Prisma doesn't generate
   automatic rollbacks) either BEFORE or AFTER rolling back the revision,
   depending on which is safer for the data. This always requires manual
   judgment, there's no safe command to copy-paste here.
3. Practical consequence: write backward-compatible migrations (add columns
   as nullable/with a default, don't drop/change a type in the same PR as
   code that would require it) - that's the only way "quick rollback" from
   7.1 is always enough, instead of requiring manual database intervention.

### 8.4. Supabase (database)

Free-tier Supabase projects pause after 7 days of inactivity (see
`infra/DECISIONS.md`) — if a rollback/debugging session happens after such a
gap, manually resume the project in the Supabase dashboard first, before
anything else. Supabase keeps automatic backups (plan-dependent) —
point-in-time restore from the dashboard is a last resort for a broken
migration, not the first step.

## 9. Known gaps / TODO

- **#45 done** — react-app/frontend-shell now have staging (named
  environment on Azure SWA) + an e2e trigger after each; next-app doesn't
  need a workflow (free Vercel branch URL). Every repo Variable/Secret in the
  table in section 6 is set and confirmed working: a full staging deploy
  (backend + react-app + frontend-shell) runs end-to-end, the shared `e2e`
  job gets real `app_url`/`api_url` values, and a manual Google OAuth login
  against the staging frontend succeeds (real token exchange, real DB write,
  real cross-origin cookie session). See `infra/BLOG_NOTES.md` for the full
  postmortem of what broke on the first real run.
- `roles/secretmanager.secretAccessor` for `github-actions-backend-deploy@`
  on `DATABASE_URL`/`DATABASE_URL_STAGING` — granted (project-level, covers
  both the WIF deploy SA and the default Compute Engine runtime SA - see the
  postmortem in `infra/BLOG_NOTES.md` for why both identities needed it).
- **Branch protection on `main` — done, all 8 repos.** All repos were made
  public (portfolio project - see `DECISIONS.md`), which also unlocks
  repository Rulesets on GitHub Free (classic branch protection AND
  rulesets are both Free-plan-private-repo-only otherwise). Used Rulesets
  (GitHub's recommended replacement for classic branch protection - holds
  admins to the rule too, no bypass unless explicitly listed) with: require
  PR before merge (0 approvals - solo project), block force pushes, and a
  required status check per repo: `test` (backend), `ci` (shared-ui,
  e2e-tests), `Build and Deploy Job` (frontend-shell, react-app), `Vercel`
  (next-app). `orchestrator` and `infra` have the same PR/force-push rules
  but no required check yet (see below).
- GitHub Environments (`staging`/`production`/`preview`) — exist only as
  references in workflows, without manually set required reviewers they
  currently block nothing
- `promote-to-main` in `deploy-gcp-staging.yml` — still a placeholder, not a
  real auto-PR/auto-merge. The actual staging→main promotions done so far
  (backend, react-app, frontend-shell, infra) were manual PRs.
- `orchestrator` has no automated tests or CI at all (no `pull_request`
  check configured) - found while wiring branch-protection status checks
  for the other 7 repos. Lower priority than the marketplace backend
  modules, but a real gap for a repo with this much control-flow logic
  (`nodes.py`, `graph.py`).
- `ai-service` and `infra` (Terraform) — outside `orchestrator/repos.py`, not
  covered by any of the pipelines above; Terraform itself has no CI
  (`terraform plan` on PR, OIDC instead of local credentials) — deliberately
  deferred, next in line now that branch protection is done
- Monitoring/alerting beyond Sentry (application errors) — nothing for
  uptime/availability of the Azure SWA / Cloud Run resources themselves
  (Application Insights, uptime check) — deliberately deferred, after
  Terraform CI
- Folding the manually-applied GCP IAM grants (compute SA + WIF SA secret
  access, project-level) into `modules/gcp/iam.tf` via `terraform import` —
  deliberately deferred, after monitoring
- The `app` project in e2e — wired up and confirmed running for real
  (see the "#45 done" note above), no longer just "code ready."

# Deployment — Vercel

The frontend is a SPA against Supabase and needs only the Supabase URL and
public browser key. Access email delivery runs separately in the Supabase
`send-emails` Edge Function; its sender credentials never enter the frontend.

`vercel.json` at the repo root holds the whole build contract, so the Vercel
project needs almost no dashboard configuration.

---

## Required release workflow

Commit changes and push them to GitHub first. Vercel then deploys automatically
from the repository's production branch (`main`). This is the established LIGN
workflow. Do not deploy directly from a local working tree unless the user
explicitly requests an exception. Verify the resulting Git-triggered deployment
before reporting that a release is live.

## 1. One-time setup (dashboard — cannot be scripted from here)

1. **Import the repo.** Vercel → Add New → Project → import
   `vikramskipper-cloud/lign`.
2. **Root Directory must be `app`.** `vercel.json` lives at `app/vercel.json`
   and every path in it is relative to that directory. Vercel runs the install
   and build commands *inside* the Root Directory, so a root-level config with
   `cd app` fails with `cd: app: No such file or directory` — that is exactly
   how the first two deploys failed.
3. **Framework preset: Vite** (Vercel detects this). No install or build
   command is declared: the preset's defaults are already `npm ci` and
   `npm run build`, and every command we wrote by hand was a chance to get the
   working directory wrong.
4. **Environment variables** — add to Production *and* Preview:

   | Name | Value |
   |---|---|
   | `VITE_SUPABASE_URL` | `https://hsfporioghapwghrvvzd.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | the project's publishable anon key |

   Both are `VITE_`-prefixed, so they are **compiled into the client bundle and
   are public by design**. Never put the service-role key here — it would be
   served to every visitor.

5. **Supabase Auth redirect URLs.** In Supabase → Authentication → URL
   Configuration, add the Vercel production domain and
   `https://*.vercel.app` for previews. Sign-in silently fails to redirect
   without this, and the failure looks like a broken app rather than a config
   gap.

> **Note on CI vs Vercel.** `.github/workflows/ci.yml` uses `cd app && npm ci`
> because GitHub Actions checks out to the repo root. Vercel declares no command
> at all because it already starts inside `app/`. The two differ deliberately —
> they run from different working directories. Do not "fix" one to match the
> other.

## 2. What `app/vercel.json` already does

- **Declares no install or build command.** The Vite preset's defaults
  (`npm ci`, `npm run build`, output `dist`) are already correct once Root
  Directory is `app`.
- **SPA rewrite** — every path falls through to `index.html`. Vercel checks the
  filesystem first, so hashed assets and `favicon.svg` still serve directly.
  Without this, a hard refresh on `/workspace/:id/projects` 404s.
- **Immutable caching** on `/assets/*` (content-hashed by Vite, safe to cache
  for a year) while `index.html` stays uncached, so a deploy takes effect
  immediately.
- **Security headers**: `nosniff`, `X-Frame-Options: DENY`, a strict referrer
  policy, a `Permissions-Policy` denying camera/microphone/geolocation, and
  HSTS.

## 2a. Troubleshooting: dashboard overrides win

**Settings in the Vercel dashboard take precedence over `app/vercel.json`.** If
Build & Development Settings has an *Install Command* or *Build Command*
override toggled on, that value runs and the repo config is ignored — so no
commit can fix a broken build.

Symptom: the build log shows a command that appears nowhere in the repo.

Fix: Project → Settings → Build & Development Settings, and switch **off** the
override for Install Command, Build Command and Output Directory so each falls
back to the Vite preset. Confirm Root Directory is `app` and Framework Preset
is Vite. Then Deployments → ⋯ → Redeploy, with "Use existing Build Cache"
**unchecked**.

Verify from the next build log:

```
Running "install" command: `npm ci`      ← not npm --prefix, not cd app
```

## 3. Rollback

Vercel keeps every deployment. Dashboard → Deployments → the last good one →
Promote to Production. **Instant, and it does not touch the database.**

That distinction matters: a rollback reverts the *client* only. If the bad
deploy also applied a migration, reverting the frontend does **not** revert the
schema. Roll the migration back deliberately and separately, then re-run
`ops/verify_migrations.sh`.

## 4. CI relationship

`.github/workflows/ci.yml` gates correctness (typecheck, tests, build, bundle
budget, migration drift, schema provenance). Vercel builds independently on
push. They are not wired together, so **a red CI run does not block a Vercel
deploy** — to change that, enable branch protection requiring the `app` job,
and let Vercel deploy only from `main`.

## 5. Enabling the schema gates

The `schema` CI job skips unless `SUPABASE_DB_URL` exists. Add it under
Settings → Secrets and variables → Actions, using the pooled connection string
from Supabase → Project Settings → Database.

It is a **read-only verification** credential in practice — both scripts only
SELECT — but the connection string itself is privileged. Never echo it in a
workflow step.


## 6. Access-only beta rollout (APP 024)

Apply this only to **LIGN: `hsfporioghapwghrvvzd`**. The CLI is now linked to this project. Do not apply any LIGN migration or
Auth setting to `nuesync`. See the rollout status below for completed and
pending work.

1. Authenticate with an account that can manage LIGN. Compare the live migration
   manifest before applying `20261112100000_app_024_access_only_beta.sql` from
   its file. Earlier migrations remain unchanged. The new six-argument public
   submission RPC replaces the old five-argument signature; release the frontend
   alongside it so old request forms do not keep calling the removed signature.
2. Set hosted Auth **Allow new users to sign up = off** (`disable_signup: true`).
   Keep **Email provider enabled** (`external_email_enabled: true`). Disabling
   the email provider also blocks existing users' password sign-in. Set the
   minimum password length to 8 and email OTP expiry to 3600 seconds. The local
   equivalent is `[auth].enable_signup = false` with
   `[auth.email].enable_signup = true` in `supabase/config.toml`.
3. Configure Supabase Auth SMTP using the verified sender and SendGrid
   credentials, so password recovery emails work. Add the exact production
   `<APP_URL>/set-password` URL to the Auth redirect allowlist. `APP_URL` is the
   production origin, never a browser-supplied value.
4. Store the following Edge Function secrets through Supabase's secret manager:
   `SENDGRID_API_KEY`, `EMAIL_FROM` (verified sender address), `APP_URL`, and
   `EMAIL_WORKER_TOKEN` (a new random secret). Supabase supplies
   `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` automatically. None of these
   secrets belongs in a `VITE_` variable, a commit, or a browser response.
5. Deploy with `supabase functions deploy send-emails --project-ref hsfporioghapwghrvvzd`.
   `verify_jwt = false` is intentional: the handler verifies staff JWTs itself
   and also accepts the private cron token. Anonymous and non-staff calls fail.
6. Store the same `EMAIL_WORKER_TOKEN` in Supabase Vault under
   `lign_email_worker_token`, then apply `ops/schedule_access_emails.sql`.
   It schedules a batch every minute; decisions also trigger immediate delivery.
7. Deploy the frontend. Check that LIGN staff can open `/access-requests`, see
   company and contact details, approve/decline, and resend welcome emails.
   Legacy pending requests must be resubmitted with company before approval;
   do not guess company names or bulk-deliver old approval jobs without review.
8. With a controlled recipient, verify the hosted flow: request all six fields
   → staff approval → delivered welcome email → password setup → normal sign-in
   → company workspace and owner membership. Confirm a reused/expired link
   fails, a resend works, public registration fails at the Auth API, and a new
   invited teammate can still activate and accept their invitation.

Local checks:

```
cd app
npm run typecheck
npm test
npm run build
```

With the isolated local LIGN stack running (port 58321), write its status JSON
to the ignored `ops/.tmp/access-local.json`, then from the repository root run
`node tests/access/access-flow.mjs` using Node 22 or later. This script refuses
hosted URLs and never sends email. Sender rendering and transport tests are in
`app/src/auth/__tests__/activation.test.ts`.

The email worker integration check is
`deno test -A --node-modules-dir=auto --no-lock tests/access/email-worker.test.ts`.
It intercepts every SendGrid call while exercising the actual local queue,
Auth tokens, retry behavior, and organisation activation. The optional
`tests/access/browser-flow.mjs` checks the same UI journey on port 5179;
provide Playwright through `PLAYWRIGHT_MODULE` and, if needed, a Chromium
executable through `PLAYWRIGHT_CHROMIUM_PATH`. Keep that frontend pointed at
the isolated local backend, not the hosted project.


### Live rollout status — 2026-11-12

Completed on LIGN (`hsfporioghapwghrvvzd`):

- APP 024 applied in one transaction from its exact source file, with the same
  source recorded as one migration-history statement. Source MD5:
  `ceb2759643168c6401811afbbf6756a2`.
- All **88/88** live migration bodies match the repository byte-for-byte;
  `ops/verify_migrations.sh` reports no drift or unapplied files.
- Public registration disabled and minimum new-password length set to 8.
  Existing email sign-in, MFA/TOTP, email confirmation, throttling, OTP length,
  and URL settings were preserved. Hosted Auth settings independently report
  registration disabled and email sign-in enabled.
- `send-emails` deployed, ACTIVE, version 1, `verify_jwt: false`; anonymous
  invocation returns 401. The handler performs its own staff authentication.
- Company-aware submission RPC and authenticated activation RPC deployed.
  Anonymous callers cannot activate owners; anonymous/customer callers cannot
  claim the mail queue. Anonymous request-table reads return an empty list.
- Existing records preserved. One legacy pending request lacks company details
  and must be resubmitted before approval. There are no approved requests.

Still pending:

- SendGrid sender credentials, Supabase SMTP, and the private worker token.
  The function's `APP_URL` is configured as `https://lignv11.vercel.app`; no
  sender credentials or schedule are configured, and no real email was sent.

The production Auth Site URL is now `https://lignv11.vercel.app`, and the
redirect allowlist contains `https://lignv11.vercel.app/set-password`. A
working-directory mistake briefly pushed local Auth defaults. The saved
production MFA/TOTP, confirmation, throttling and OTP settings were restored
immediately; a subsequent configuration comparison reports all remote services
up to date against the reviewed production settings. Public registration
remains disabled and the minimum new-password length remains 8.

The original local migrations use narrative timestamps while older deployed
versions use apply timestamps. A temporary deployment directory fetched remote
history for a dry run, which confirmed APP 024 was the sole pending change.
The atomic apply preserved the established single-statement source-history
format so the checksum verifier remains valid. Historical migrations and their
versions were not rewritten.


### Frontend production release — 2026-11-12

The Vercel CLI authenticated successfully and resolved the production URL to
project **`lign_v1.1`** (`prj_yHBt6pWpFXVDwMwWMB1gvR7wgDKj`) under
**`vixlo-a-projects1`** (`team_ZH9C3yBYOwaOzaI2SRdUezcM`). The project root is
`app`, the framework is Vite, and the configured build runtime is Node 24.
The repository root was linked to that existing project for upload.

The frontend was deployed from the current working checkout, including the
APP 024 changes, with `--prod --skip-domain`, verified in its staged production
environment, and promoted to **https://lignv11.vercel.app**.

- Deployment: `dpl_7CFq448fGeiPFU69vXJw6ny43gdT`.
- Staged URL: `https://lignv11-krq1bqryi-vixlo-a-projects1.vercel.app`.
- Previous production deployment: `dpl_2atZZLmCFhsyjFzDPA9wsyE7Zrtz`.
- Live entry asset: `/assets/index-B54slIic.js`, matching the verified staged
  build. The previous entry asset was `/assets/index-BrMF5x-F.js`.
- All 80 unit tests passed before release; the remote production build passed.
- Staged and public production browser checks passed: sign-in link reaches the
  six-field request form, required-field validation works, both public signup
  routes redirect to request access, missing password tokens are refused,
  anonymous admin access redirects to sign-in, and mobile layout has no
  horizontal overflow or page errors. No production data was submitted.
- The temporary automation bypass created by `vercel curl` for staged testing
  was revoked after testing. Existing deployment protection was preserved.
- `.vercelignore` excludes local credentials, dependency/build artifacts, and
  operational scratch data from uploads. `.vercel/` remains Git-ignored.

`tests/access/hosted-smoke.mjs` preserves the read-only public browser checks.
It accepts `PLAYWRIGHT_MODULE` and `PLAYWRIGHT_CHROMIUM_PATH` when Playwright
and Chromium are installed outside the repository.

Frontend and Supabase publication are now complete. SendGrid credentials,
verified sender configuration, Supabase SMTP and scheduling remain pending;
real welcome-email delivery has not been enabled or verified.

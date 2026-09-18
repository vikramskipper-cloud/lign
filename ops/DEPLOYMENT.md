# Deployment — Vercel

The app is a pure SPA against Supabase. There is no server, no API route and no
build secret: everything it needs at runtime is the Supabase URL and the
publishable anon key.

`vercel.json` at the repo root holds the whole build contract, so the Vercel
project needs almost no dashboard configuration.

---

## 1. One-time setup (dashboard — cannot be scripted from here)

1. **Import the repo.** Vercel → Add New → Project → import
   `vikramskipper-cloud/lign`.
2. **Leave Root Directory as `/`.** `vercel.json` already points the build at
   `app/`. Setting it to `app` instead would make Vercel ignore that file.
3. **Framework preset: Other.** Explicit commands in `vercel.json` beat preset
   inference for a non-root app.
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

## 2. What `vercel.json` already does

- Builds with `npm --prefix app ci && npm --prefix app run build`, publishing
  `app/dist`.
- **SPA rewrite** — every path falls through to `index.html`. Vercel checks the
  filesystem first, so hashed assets and `favicon.svg` still serve directly.
  Without this, a hard refresh on `/workspace/:id/projects` 404s.
- **Immutable caching** on `/assets/*` (content-hashed by Vite, safe to cache
  for a year) while `index.html` stays uncached, so a deploy takes effect
  immediately.
- **Security headers**: `nosniff`, `X-Frame-Options: DENY`, a strict referrer
  policy, a `Permissions-Policy` denying camera/microphone/geolocation, and
  HSTS.

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

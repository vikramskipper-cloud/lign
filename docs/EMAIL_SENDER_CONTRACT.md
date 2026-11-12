# The mail sender's contract

`public.email_outbox` is drained by `supabase/functions/send-emails/index.ts`
(APP 024). It uses SendGrid, with credentials held only by the Edge Function.
The implementation is prepared in the repository; hosted deployment and sender
configuration must be completed before claiming that emails are delivered.

## Access

Only `service_role` can read `email_outbox.payload`. Client roles hold a
column-level `SELECT` that deliberately omits it (APP 023), because the payload
carries invitation tokens — `SELECT *` as `authenticated` fails `42501`. So the
sender runs with the service key, which means **an Edge Function or a server
job, never the browser**.

## Delivery and retries

The service-only `claim_email_batch` RPC leases up to ten queued messages for
ten minutes using `FOR UPDATE SKIP LOCKED`. Claiming increments `attempts`.
Workers update only rows with their own `lock_token`. Failures retry after one
minute, up to five attempts, then become `failed`. Expired leases recover a
crashed worker's jobs. Delivery is at least once: a provider timeout after
acceptance can produce a duplicate email, but retries reuse the same link.

An authenticated LIGN platform admin can invoke delivery for one decided access
request. All other client callers are refused. The scheduled worker uses a
separate `EMAIL_WORKER_TOKEN` and drains all supported templates. A pending
public request cannot invoke delivery directly.

The generated activation URL is persisted in server-only `payload` before
sending. Successful delivery marks the row `sent` and clears `payload`, so
password and invitation tokens do not remain at rest after delivery. Neither
responses nor operator-visible errors contain these tokens.

`resend_access_welcome` is staff-only. It resets delivery attempts and removes
the previous stored activation URL so an explicit resend can mint a fresh one.
It cannot reset a job with an active delivery lease.

## Templates

| `template` | sent when | payload |
|---|---|---|
| `access_request_received` | someone submits the public request-access form | `name` |
| `access_request_approved` | a platform admin approves them | `name`, `request_id`; company is read from the approved request |
| `access_request_declined` | a platform admin declines them | `name` |
| `org_invitation` | an org owner/admin invites someone to the organisation | `invitation_id`, `email`, `role`, `context_name`, `claim_route`, `token`, `expires_at` |
| `workspace_member_invitation` | someone is invited to a workspace | as above |
| `stakeholder_invitation` | a client/external is invited to a project | as above |

`context_name` is the organisation or workspace name — what the message should
say they are being invited to. `role` is their role once they accept.

## Access-only activation

There is no public signup. Both `/sign-up` and `/signup` redirect to
`/request-access`, and the Auth server must have `disable_signup: true` while
keeping email/password authentication enabled.

For approved applicants, the sender verifies the approval and company name,
then uses Auth admin `generateLink` to create an invited account, or a recovery
link for an existing account. The welcome email opens:

```
<APP_URL>/set-password#token_hash=<hash>&type=invite&returnTo=%2Fdashboard
```

Existing accounts use `type=recovery`. Only `invite` and `recovery` are
accepted. `verifyOtp` consumes the single-use token, the user chooses and
confirms a password, and `complete_approved_access` creates their organisation
and first workspace from the approved company name. It grants owner membership
and spends the approval once. Retries return the same workspace. The user then
signs in normally with their email and new password.

The database checks verified identity and the approval against the caller's own
profile email. No client chooses an owner ID or submits a target organisation.
All six request fields, including company and phone, are required server-side.
Historical requests without a company cannot be approved until resubmitted.

Member invitations use the same password activation page, with `returnTo`
restricted to the exact `/org-invite/<token>` or `/invite/<token>` claim route.
After password setup and sign-in, the existing invitation RPC checks the email,
expiry, and token before admitting them. They receive no founder entitlement.
Existing users can also use the invitation email's direct sign-in/claim link.

## What the queue does NOT do

- **Scheduling needs hosted setup.** Apply `ops/schedule_access_emails.sql` after storing the worker token in Vault; it invokes delivery every minute.
- **No rate limiting.** `submit_access_request` is callable by `anon`, so the
  public form can be driven in a loop with distinct addresses. Postgres has
  nowhere good for a per-IP limit; this needs an edge function in front or a
  gateway rule. Until then the queue can be filled with junk, which is why the
  sender should treat a sudden spike as suspicious rather than as work.
- **No bounce handling.** `failed` only ever means the send call failed.
- **No unsubscribe.** All of these are transactional; if marketing mail is ever
  added it must not share this table.

## Required hosted configuration

See `ops/DEPLOYMENT.md` for the rollout checklist. The welcome sender needs a
verified SendGrid sender, `SENDGRID_API_KEY`, `EMAIL_FROM`, `APP_URL`, and
`EMAIL_WORKER_TOKEN`. Supabase's separate password recovery mail also needs
SMTP configuration and a redirect allowlist entry for `/set-password`.

The code does not send a test email to any real recipient. A delivered email
and browser activation on the hosted LIGN domain remain deployment checks.

# The mail sender's contract

`public.email_outbox` is a to-send list. Nothing in LIGN sends mail; a sender
added later drains this table. This is what it has to do.

## Access

Only `service_role` can read `email_outbox.payload`. Client roles hold a
column-level `SELECT` that deliberately omits it (APP 023), because the payload
carries invitation tokens — `SELECT *` as `authenticated` fails `42501`. So the
sender runs with the service key, which means **an Edge Function or a server
job, never the browser**.

## The loop

```sql
select id, to_email, template, payload
  from public.email_outbox
 where status = 'queued'
 order by created_at
 limit 50;
```

Then, per row, after a successful send:

```sql
update public.email_outbox
   set status = 'sent', sent_at = now(), payload = '{}'::jsonb
 where id = $1;
```

**Clearing `payload` is required, not tidying.** It is what keeps an invitation
token out of the database once it has been delivered; until APP 023 only
`sha256(token)` was ever stored, and the queue is the one place the plaintext
now lives. On failure, instead:

```sql
update public.email_outbox
   set status = case when attempts + 1 >= 5 then 'failed' else 'queued' end,
       attempts = attempts + 1,
       last_error = left($2, 500)
 where id = $1;
```

Keep `payload` on a retryable failure — the next attempt needs it.

## Templates

| `template` | sent when | payload |
|---|---|---|
| `access_request_received` | someone submits the public request-access form | `name` |
| `access_request_approved` | a platform admin approves them | `name` |
| `access_request_declined` | a platform admin declines them | `name` |
| `org_invitation` | an org owner/admin invites someone to the organisation | `invitation_id`, `email`, `role`, `context_name`, `claim_route`, `token`, `expires_at` |
| `workspace_member_invitation` | someone is invited to a workspace | as above |
| `stakeholder_invitation` | a client/external is invited to a project | as above |

`context_name` is the organisation or workspace name — what the message should
say they are being invited to. `role` is their role once they accept.

## Building the link

`claim_route` is the path **without** the token, so the sender never needs to
know LIGN's routing:

```
<APP_URL> + payload.claim_route + '/' + payload.token
```

giving `https://app.example.com/org-invite/<token>` or `/invite/<token>`.

## What the queue does NOT do

- **No scheduling.** Rows are queued the moment the thing happens.
- **No rate limiting.** `submit_access_request` is callable by `anon`, so the
  public form can be driven in a loop with distinct addresses. Postgres has
  nowhere good for a per-IP limit; this needs an edge function in front or a
  gateway rule. Until then the queue can be filled with junk, which is why the
  sender should treat a sudden spike as suspicious rather than as work.
- **No bounce handling.** `failed` only ever means the send call failed.
- **No unsubscribe.** All of these are transactional; if marketing mail is ever
  added it must not share this table.

## Approval does not grant access

`access_request_approved` means a platform admin said yes. It does **not**
create an account, an organisation or a membership. The applicant then signs in
and founds their own organisation, which `create_organization` permits only
against an unspent approved request for that same email (APP 022). So the
approval email should tell them to sign in and set up their company — not that
anything already exists.

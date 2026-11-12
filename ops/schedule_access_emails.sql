-- Apply ONLY to LIGN (hsfporioghapwghrvvzd), after deploying send-emails.
-- First save the same randomly generated EMAIL_WORKER_TOKEN used by the Edge
-- Function as a Vault secret named lign_email_worker_token. No key goes here.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

do $block$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'lign_email_worker_token') then
    raise exception 'Set Vault secret lign_email_worker_token before scheduling';
  end if;
end;
$block$;

select cron.schedule(
  'lign-access-email-delivery',
  '* * * * *',
  $job$
  select net.http_post(
    url := 'https://hsfporioghapwghrvvzd.supabase.co/functions/v1/send-emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'lign_email_worker_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $job$
);

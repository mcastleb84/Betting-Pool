-- Buy-in payments: PayPal, Cash App and Venmo pay buttons, plus "I paid with…" from players.
-- Run once in Supabase: SQL Editor → New query → paste all of this → Run. Safe to run again.

-- Where the organizer takes buy-ins (usernames only; each becomes a pay button).
alter table public.bp_pools add column if not exists pay_paypal  text check (pay_paypal  is null or pay_paypal  ~ '^[A-Za-z0-9_-]{1,30}$');
alter table public.bp_pools add column if not exists pay_cashapp text check (pay_cashapp is null or pay_cashapp ~ '^[A-Za-z0-9_-]{1,30}$');
alter table public.bp_pools add column if not exists pay_venmo   text check (pay_venmo   is null or pay_venmo   ~ '^[A-Za-z0-9_-]{1,30}$');

-- A player says how they sent their buy-in; the organizer still confirms by marking them Paid.
alter table public.bp_entries add column if not exists sent_via   text check (sent_via is null or sent_via in ('paypal','cashapp','venmo','other'));
alter table public.bp_entries add column if not exists sent_at    timestamptz;
-- Secret kept only on the player's phone, so nobody else can mark their entry as sent. Never readable by the public.
alter table public.bp_entries add column if not exists join_token uuid;
grant select (sent_via, sent_at) on public.bp_entries to anon, authenticated;

-- Winners can now be paid on PayPal too.
alter table public.bp_entries drop constraint if exists bp_entries_pay_app_check;
alter table public.bp_entries add constraint bp_entries_pay_app_check check (pay_app is null or pay_app in ('venmo','cashapp','paypal'));

create or replace function public.bp_mark_sent(eid uuid, tok uuid, via text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if via is not null and via not in ('paypal','cashapp','venmo','other') then raise exception 'Unknown payment app'; end if;
  update bp_entries set sent_via = via, sent_at = case when via is null then null else now() end
   where id = eid and join_token is not null and join_token = tok and paid = false;
  if not found then raise exception 'That entry can''t be updated from this device'; end if;
end $$;
revoke all on function public.bp_mark_sent(uuid, uuid, text) from public;
grant execute on function public.bp_mark_sent(uuid, uuid, text) to anon, authenticated;

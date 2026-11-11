-- Pool Board: the whole database setup in one file.
-- Supabase → SQL Editor → New query → paste ALL of this → Run. Safe to run again any time.

-- ================= pool-setup.sql =================
-- Betting pool tables. Run once in Supabase: SQL Editor → New query → paste all of this → Run.
-- Safe to run again; it only adds what's missing.

create table if not exists public.bp_pools (
  id           uuid primary key default gen_random_uuid(),
  organizer_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  buy_in       numeric(10,2) not null check (buy_in > 0 and buy_in <= 100000),
  max_players  int check (max_players is null or max_players between 2 and 500),
  splits       int[] not null default '{100}',
  pay_info     text check (pay_info is null or char_length(pay_info) <= 80),
  created_at   timestamptz not null default now()
);

create table if not exists public.bp_entries (
  id         uuid primary key default gen_random_uuid(),
  pool_id    uuid not null references public.bp_pools(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  paid       boolean not null default false,
  place      int not null default 0 check (place between 0 and 3),
  created_at timestamptz not null default now()
);
create index if not exists bp_entries_pool_idx on public.bp_entries(pool_id);

alter table public.bp_pools   enable row level security;
alter table public.bp_entries enable row level security;

grant select on public.bp_pools, public.bp_entries to anon, authenticated;
grant insert, update, delete on public.bp_pools to authenticated;
grant insert on public.bp_entries to anon, authenticated;
grant update, delete on public.bp_entries to authenticated;

-- Pools: anyone with the link can see a pool; only its organizer can create, change or delete it.
drop policy if exists "bp pools readable"   on public.bp_pools;
drop policy if exists "bp pools create"     on public.bp_pools;
drop policy if exists "bp pools edit"       on public.bp_pools;
drop policy if exists "bp pools delete"     on public.bp_pools;
create policy "bp pools readable" on public.bp_pools for select using (true);
create policy "bp pools create"   on public.bp_pools for insert to authenticated with check (organizer_id = auth.uid());
create policy "bp pools edit"     on public.bp_pools for update to authenticated using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());
create policy "bp pools delete"   on public.bp_pools for delete to authenticated using (organizer_id = auth.uid());

-- Entries: anyone can see who's in and join themselves (never as "paid" or a winner);
-- only the pool's organizer can add others, mark paid, set places or remove people.
drop policy if exists "bp entries readable" on public.bp_entries;
drop policy if exists "bp entries join"     on public.bp_entries;
drop policy if exists "bp entries organizer add"    on public.bp_entries;
drop policy if exists "bp entries organizer edit"   on public.bp_entries;
drop policy if exists "bp entries organizer remove" on public.bp_entries;
create policy "bp entries readable" on public.bp_entries for select using (true);
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0);
create policy "bp entries organizer add" on public.bp_entries for insert to authenticated
  with check (exists (select 1 from public.bp_pools p where p.id = pool_id and p.organizer_id = auth.uid()));
create policy "bp entries organizer edit" on public.bp_entries for update to authenticated
  using (exists (select 1 from public.bp_pools p where p.id = pool_id and p.organizer_id = auth.uid()))
  with check (exists (select 1 from public.bp_pools p where p.id = pool_id and p.organizer_id = auth.uid()));
create policy "bp entries organizer remove" on public.bp_entries for delete to authenticated
  using (exists (select 1 from public.bp_pools p where p.id = pool_id and p.organizer_id = auth.uid()));

-- Stop joins once a pool hits its max players (or 500).
create or replace function public.bp_check_full() returns trigger
language plpgsql security definer set search_path = public as $$
declare cap int; n int;
begin
  select coalesce(max_players, 500) into cap from bp_pools where id = new.pool_id;
  select count(*) into n from bp_entries where pool_id = new.pool_id;
  if n >= cap then raise exception 'This pool is full'; end if;
  return new;
end $$;
drop trigger if exists bp_entries_full on public.bp_entries;
create trigger bp_entries_full before insert on public.bp_entries
  for each row execute function public.bp_check_full();

-- ===== One-tap payouts (added later; safe to run on its own) =====
alter table public.bp_entries add column if not exists pay_app    text check (pay_app is null or pay_app in ('venmo','cashapp'));
alter table public.bp_entries add column if not exists pay_handle text check (pay_handle is null or pay_handle ~ '^[A-Za-z0-9_-]{1,30}$');
alter table public.bp_entries add column if not exists paid_out   boolean not null default false;

-- Joiners can't mark themselves paid out.
drop policy if exists "bp entries join" on public.bp_entries;
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0 and paid_out = false);

-- Payment usernames are hidden from the public; only the pool's organizer can read them.
revoke select on public.bp_entries from anon, authenticated;
grant select (id, pool_id, name, paid, place, paid_out, created_at) on public.bp_entries to anon, authenticated;

create or replace function public.bp_pay_handles(pid uuid)
returns table (id uuid, pay_app text, pay_handle text)
language sql stable security definer set search_path = public as $$
  select e.id, e.pay_app, e.pay_handle from bp_entries e
  join bp_pools p on p.id = e.pool_id
  where e.pool_id = pid and p.organizer_id = auth.uid();
$$;
revoke all on function public.bp_pay_handles(uuid) from public, anon;
grant execute on function public.bp_pay_handles(uuid) to authenticated;

-- ===== Points + automatic places (added later; safe to run on its own) =====
alter table public.bp_entries add column if not exists score numeric(12,2);
drop policy if exists "bp entries join" on public.bp_entries;
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0 and paid_out = false and score is null);
grant select (score) on public.bp_entries to anon, authenticated;

-- ===== Lowest-score-wins setting (added later; safe to run on its own) =====
alter table public.bp_pools add column if not exists low_wins boolean not null default false;

-- ===== Pool terms agreement (added later; safe to run on its own) =====
alter table public.bp_entries add column if not exists agreed_at timestamptz;
drop policy if exists "bp entries join" on public.bp_entries;
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0 and paid_out = false and score is null and agreed_at is not null);
grant select (agreed_at) on public.bp_entries to anon, authenticated;

-- ===== Team / player picks (added later; safe to run on its own) =====
alter table public.bp_pools   add column if not exists picks        text[] not null default '{}';
alter table public.bp_pools   add column if not exists pick_label   text not null default 'Team' check (char_length(pick_label) <= 20);
alter table public.bp_pools   add column if not exists unique_picks boolean not null default false;
alter table public.bp_pools   add column if not exists winning_pick text;
alter table public.bp_entries add column if not exists pick text check (pick is null or char_length(pick) <= 40);
grant select (pick) on public.bp_entries to anon, authenticated;

-- Joiners must choose one of the pool's listed picks (or none, if the pool has no picks).
drop policy if exists "bp entries join" on public.bp_entries;
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0 and paid_out = false and score is null and agreed_at is not null
    and exists (select 1 from public.bp_pools p where p.id = pool_id
                and ((cardinality(p.picks) = 0 and pick is null) or pick = any(p.picks))));

-- "Each choice can only be picked once"
create or replace function public.bp_check_pick() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.pick is not null and exists (select 1 from bp_pools where id = new.pool_id and unique_picks)
     and exists (select 1 from bp_entries where pool_id = new.pool_id and pick = new.pick and id <> new.id) then
    raise exception 'That pick is already taken';
  end if;
  return new;
end $$;
drop trigger if exists bp_entries_pick on public.bp_entries;
create trigger bp_entries_pick before insert or update of pick on public.bp_entries
  for each row execute function public.bp_check_pick();

-- ===== Several picks per player (added later; safe to run on its own) =====
alter table public.bp_pools   add column if not exists picks_each int not null default 1 check (picks_each between 1 and 64);
alter table public.bp_entries add column if not exists chosen text[] not null default '{}';
update public.bp_entries set chosen = array[pick] where pick is not null and cardinality(chosen) = 0;
grant select (chosen) on public.bp_entries to anon, authenticated;

-- Joiners must choose exactly the number of picks the pool asks for, all from its list.
drop policy if exists "bp entries join" on public.bp_entries;
create policy "bp entries join" on public.bp_entries for insert to anon, authenticated
  with check (paid = false and place = 0 and paid_out = false and score is null and agreed_at is not null and pick is null
    and exists (select 1 from public.bp_pools p where p.id = pool_id
                and ((cardinality(p.picks) = 0 and cardinality(chosen) = 0)
                  or (cardinality(chosen) = p.picks_each and chosen <@ p.picks))));

-- "Each choice can only be picked once" now checks every pick a player makes.
create or replace function public.bp_check_pick() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if cardinality(coalesce(new.chosen,'{}')) > 0 and exists (select 1 from bp_pools where id = new.pool_id and unique_picks)
     and exists (select 1 from bp_entries where pool_id = new.pool_id and id <> new.id and chosen && new.chosen) then
    raise exception 'That pick is already taken';
  end if;
  return new;
end $$;
drop trigger if exists bp_entries_pick on public.bp_entries;
create trigger bp_entries_pick before insert or update of chosen on public.bp_entries
  for each row execute function public.bp_check_pick();

-- ================= sports-setup.sql =================
-- Sport tabs for the betting pool (Football, Basketball, Baseball, Hockey, Golf, Tennis, Other),
-- plus the tournament name and tour for golf and tennis pools.
-- Run once in Supabase: SQL Editor → New query → paste all of this → Run. Safe to run again.
alter table public.bp_pools add column if not exists sport text not null default 'custom';
alter table public.bp_pools add column if not exists event text;
alter table public.bp_pools add column if not exists tour  text;
alter table public.bp_pools drop constraint if exists bp_pools_sport_check;
alter table public.bp_pools add constraint bp_pools_sport_check check (sport in ('custom','nfl','nba','mlb','nhl','golf','tennis'));
alter table public.bp_pools drop constraint if exists bp_pools_event_check;
alter table public.bp_pools add constraint bp_pools_event_check check (event is null or char_length(event) <= 80);
alter table public.bp_pools drop constraint if exists bp_pools_tour_check;
alter table public.bp_pools add constraint bp_pools_tour_check check (tour is null or tour in ('pga','lpga','eur','atp','wta'));

-- ================= chat-setup.sql =================
-- Game chat for the betting pool. Run once in Supabase: SQL Editor → New query → paste all of this → Run.
-- Needs pool-setup.sql to have been run first. Safe to run again.

create table if not exists public.bp_messages (
  id         uuid primary key default gen_random_uuid(),
  pool_id    uuid not null references public.bp_pools(id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 30),
  body       text not null check (char_length(btrim(body)) between 1 and 280),
  client_id  text check (client_id is null or char_length(client_id) <= 40),
  sender_id  uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists bp_messages_pool_idx on public.bp_messages(pool_id, created_at desc);

alter table public.bp_messages enable row level security;
grant select, insert on public.bp_messages to anon, authenticated;
grant delete on public.bp_messages to authenticated;

-- Anyone with the pool link can read and post; only the pool's organizer can delete messages.
drop policy if exists "bp chat readable"  on public.bp_messages;
drop policy if exists "bp chat post"      on public.bp_messages;
drop policy if exists "bp chat moderate"  on public.bp_messages;
create policy "bp chat readable" on public.bp_messages for select using (true);
create policy "bp chat post" on public.bp_messages for insert to anon, authenticated
  with check (created_at > now() - interval '1 minute'
    and (sender_id is null or sender_id = auth.uid())
    and exists (select 1 from public.bp_pools p where p.id = pool_id));
create policy "bp chat moderate" on public.bp_messages for delete to authenticated
  using (exists (select 1 from public.bp_pools p where p.id = pool_id and p.organizer_id = auth.uid()));

-- Flood guard: at most 20 messages in any pool per 10 seconds.
create or replace function public.bp_chat_flood() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  if (select count(*) from bp_messages where pool_id = new.pool_id and created_at > now() - interval '10 seconds') >= 20 then
    raise exception 'Chat is busy, slow down';
  end if;
  return new;
end $$;
drop trigger if exists bp_messages_flood on public.bp_messages;
create trigger bp_messages_flood before insert on public.bp_messages
  for each row execute function public.bp_chat_flood();

-- Live updates: new messages appear instantly for everyone with the pool open.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bp_messages') then
    alter publication supabase_realtime add table public.bp_messages;
  end if;
end $$;

-- ================= payments-setup.sql =================
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

-- ===== Winners add where to get paid (added later; safe to run again) =====
-- A winner can set their own PayPal, Cash App or Venmo from their phone so the organizer can pay them in one tap.
create or replace function public.bp_set_payout(eid uuid, tok uuid, app text, handle text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if app not in ('paypal','cashapp','venmo') then raise exception 'Unknown payment app'; end if;
  if handle !~ '^[A-Za-z0-9_-]{1,30}$' then raise exception 'Use letters, numbers, - or _ in the username'; end if;
  update bp_entries set pay_app = app, pay_handle = handle
   where id = eid and join_token is not null and join_token = tok and paid_out = false;
  if not found then raise exception 'That entry can''t be updated from this device'; end if;
end $$;
revoke all on function public.bp_set_payout(uuid, uuid, text, text) from public;
grant execute on function public.bp_set_payout(uuid, uuid, text, text) to anon, authenticated;


-- ================= fix-access.sql =================
alter table public.bp_entries add column if not exists score numeric(12,2);
alter table public.bp_entries add column if not exists agreed_at timestamptz;
alter table public.bp_entries add column if not exists pick text;
alter table public.bp_entries add column if not exists chosen text[] not null default '{}';
alter table public.bp_entries add column if not exists sent_via text;
alter table public.bp_entries add column if not exists sent_at timestamptz;
grant select (id, pool_id, name, paid, place, paid_out, score, pick, chosen, agreed_at, created_at, sent_via, sent_at)
  on public.bp_entries to anon, authenticated;
grant insert on public.bp_entries to anon, authenticated;
grant update, delete on public.bp_entries to authenticated;
grant select on public.bp_pools to anon, authenticated;
notify pgrst, 'reload schema';

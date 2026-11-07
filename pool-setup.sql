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

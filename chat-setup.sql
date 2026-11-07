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

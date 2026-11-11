-- Fixes "permission denied for table bp_entries". Paste all of this into Supabase → SQL Editor → Run.
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

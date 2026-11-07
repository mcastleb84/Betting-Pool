-- Sport tabs for the betting pool (Football, Basketball, Baseball, Hockey, Golf, Tennis, Other).
-- Run once in Supabase: SQL Editor → New query → paste all of this → Run. Safe to run again.
alter table public.bp_pools add column if not exists sport text not null default 'custom'
  check (sport in ('custom','nfl','nba','mlb','nhl','golf','tennis'));
notify pgrst, 'reload schema';

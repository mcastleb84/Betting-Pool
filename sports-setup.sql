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
notify pgrst, 'reload schema';

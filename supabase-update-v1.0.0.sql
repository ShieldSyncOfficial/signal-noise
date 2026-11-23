-- =====================================================================
--  SIGNAL//NOISE — database update for game v1.0.0
--  Run ONCE in Supabase: Dashboard → SQL Editor → New query → paste → Run.
--  • keeps 5 sample BOT scores (removes Nightjar, Packet, Lantern, Honeypot, Rookie)
--  • leaderboard returns your own full row, so the game can show it under the top 15
--  • older careers uploaded after the fact keep their original finish date
--  Safe to run more than once.
-- =====================================================================
delete from public.players where bot and username in ('BOT-Nightjar', 'BOT-Packet', 'BOT-Lantern', 'BOT-Honeypot', 'BOT-Rookie');

-- the old leaderboard function had a different default; drop it so the new one replaces it cleanly
drop function if exists public.sn_leaderboard(text, text, int, uuid);
-- ---------------------------------------------------------------- runs (v1.0.0: accepts ended_at for backfilled careers)
create or replace function public.sn_post_run(p_token uuid, p_run jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pid uuid := sn_auth(p_token); v_id text := left(coalesce(p_run->>'id', ''), 32);
        v_diff text := coalesce(p_run->>'diff', 'standard'); v_status text := coalesce(p_run->>'status', 'active');
        v_when timestamptz; n int;
begin
  if v_id !~ '^[A-Za-z0-9_-]{6,32}$' then return jsonb_build_object('error', 'bad_run'); end if;
  if v_diff not in ('beginner', 'standard', 'veteran', 'advanced') then v_diff := 'standard'; end if;
  if v_status not in ('active', 'ended') then v_status := 'active'; end if;
  begin v_when := least(now(), coalesce((p_run->>'ended_at')::timestamptz, now())); exception when others then v_when := now(); end;
  insert into runs as r (id, player_id, diff, seed, status, cause, shifts, tier, acc, decisions, prevented, boss_won, sla, grade_pts, last_grade, started_at, updated_at)
  values (v_id, v_pid, v_diff, left(p_run->>'seed', 24), v_status,
          case when p_run->>'cause' in ('burnout', 'terminated', 'breach', 'retired', 'resigned') then p_run->>'cause' end,
          least(greatest(coalesce((p_run->>'shifts')::int, 0), 0), 500),
          least(greatest(coalesce((p_run->>'tier')::int, 0), 0), 4),
          least(greatest(coalesce((p_run->>'acc')::int, 0), 0), 100),
          least(greatest(coalesce((p_run->>'decisions')::int, 0), 0), 50000),
          least(greatest(coalesce((p_run->>'prevented')::int, 0), 0), 5000),
          least(greatest(coalesce((p_run->>'boss_won')::int, 0), 0), 500),
          least(greatest(coalesce((p_run->>'sla')::int, 0), 0), 50000),
          least(greatest(coalesce((p_run->>'grade_pts')::int, 0), 0), 100 * 500),
          left(p_run->>'last_grade', 2),
          least(now(), coalesce((p_run->>'started_at')::timestamptz, now())),
          case when v_status = 'ended' then v_when else now() end)
  on conflict (id) do update set
          status = excluded.status, cause = excluded.cause, shifts = excluded.shifts, tier = excluded.tier,
          acc = excluded.acc, decisions = excluded.decisions, prevented = excluded.prevented,
          boss_won = excluded.boss_won, sla = excluded.sla, grade_pts = excluded.grade_pts,
          last_grade = excluded.last_grade, updated_at = now()
    where r.player_id = v_pid and r.status = 'active';     -- only your own, unfinished runs can change
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;

-- p_kind: 'runs' (every run, live) or 'careers' (finished runs only). Best entry per player.
-- v1.0.0: 'me' now carries your full row, so it can be shown under the top 15.
create or replace function public.sn_leaderboard(p_kind text, p_diff text default null, p_limit int default 15, p_player uuid default null) returns jsonb
language sql security definer set search_path = public as $$
  with base as (
    select r.*, p.username, p.bot from runs r join players p on p.id = r.player_id
     where not r.hidden and not p.banned
       and (coalesce(p_kind, 'runs') = 'runs' or r.status = 'ended')
       and (p_diff is null or r.diff = p_diff)
  ), best as (
    select distinct on (player_id) * from base order by player_id, score desc, updated_at asc
  ), ranked as (
    select *, rank() over (order by score desc, updated_at asc) as rk from best
  ), shaped as (
    select rk, player_id, jsonb_build_object(
              'id', id, 'player_id', player_id, 'name', username, 'bot', bot, 'diff', diff, 'status', status, 'cause', cause,
              'shifts', shifts, 'tier', tier, 'acc', acc, 'prevented', prevented, 'boss_won', boss_won, 'last_grade', last_grade,
              'score', score, 'rank', rk, 'updated_at', updated_at, 'started_at', started_at) as j
      from ranked
  )
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(j order by rk) from (select * from shaped order by rk limit least(greatest(coalesce(p_limit, 15), 1), 200)) t), '[]'::jsonb),
    'total', (select count(*) from ranked),
    'me', (select j from shaped where player_id = p_player),
    'updated_at', (select max(updated_at) from base),
    'now', now());
$$;

grant execute on function public.sn_post_run(uuid, jsonb), public.sn_leaderboard(text, text, int, uuid) to anon, authenticated;

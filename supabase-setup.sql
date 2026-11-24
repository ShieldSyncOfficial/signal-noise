-- =====================================================================
--  SIGNAL//NOISE — Supabase backend setup
--  Run this ONCE in your Supabase project: Dashboard → SQL Editor → New query → paste → Run.
--  Safe to re-run: it creates what's missing and replaces the functions.
--
--  What it creates
--    players   usernames (unique, case-insensitive) + hashed 4-digit passcodes
--    sessions  login tokens (one per device)
--    saves     each player's cloud save (whole profile + run in progress)
--    runs      one row per run: live total while active, final score when ended
--              → Runs leaderboard = all runs · Careers leaderboard = ended runs
--  Security
--    Row Level Security is ON and the public (anon) key can't read or write
--    any table directly. Everything goes through the sn_* functions below,
--    which check the player's session token. Passcodes are bcrypt-hashed.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tables
create table if not exists public.players (
  id              uuid primary key default gen_random_uuid(),
  username        text not null,
  pass_hash       text,
  created_at      timestamptz not null default now(),
  last_login      timestamptz,
  failed_attempts int not null default 0,
  locked_until    timestamptz,
  banned          boolean not null default false,   -- moderation: true hides the player everywhere and blocks login
  bot             boolean not null default false    -- sample entries (can't log in)
);
create unique index if not exists players_username_lower on public.players (lower(username));

create table if not exists public.sessions (
  token      uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create index if not exists sessions_player on public.sessions (player_id);

create table if not exists public.saves (
  player_id  uuid primary key references public.players(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.runs (
  id         text primary key,
  player_id  uuid not null references public.players(id) on delete cascade,
  diff       text not null default 'standard',
  seed       text,
  status     text not null default 'active',       -- active | ended
  cause      text,                                  -- burnout | terminated | breach | retired | resigned
  shifts     int  not null default 0,
  tier       int  not null default 0,
  acc        int  not null default 0,
  decisions  int  not null default 0,
  prevented  int  not null default 0,
  boss_won   int  not null default 0,
  sla        int  not null default 0,
  grade_pts  int  not null default 0,
  last_grade text,
  score      int  not null default 0,               -- always recalculated by the server (trigger below)
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  hidden     boolean not null default false         -- moderation: true removes this run from the leaderboards
);
create index if not exists runs_score  on public.runs (score desc);
create index if not exists runs_player on public.runs (player_id);

alter table public.players  enable row level security;
alter table public.sessions enable row level security;
alter table public.saves    enable row level security;
alter table public.runs     enable row level security;
revoke all on public.players, public.sessions, public.saves, public.runs from anon, authenticated;

-- ---------------------------------------------------------------- scoring
-- Same formula as careerScore() in index.html. The server is authoritative.
create or replace function public.sn_runs_score() returns trigger
language plpgsql set search_path = public as $$
declare base numeric; mult numeric;
begin
  mult := case new.diff when 'beginner' then 0.6 when 'veteran' then 1.3 when 'advanced' then 1.6 else 1.0 end;
  base := new.shifts * 100 + new.prevented * 40 + new.boss_won * 150 + new.tier * 200
        + case when new.decisions >= 10 then new.acc * 3 else 0 end
        - new.sla * 5 + new.grade_pts
        + case when new.cause = 'retired' then 500 else 0 end;
  new.score := greatest(0, round(greatest(0, base) * mult));
  return new;
end $$;
drop trigger if exists runs_score_trg on public.runs;
create trigger runs_score_trg before insert or update on public.runs
  for each row execute function public.sn_runs_score();

-- ---------------------------------------------------------------- helpers
create or replace function public.sn_auth(p_token uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_pid uuid;
begin
  select s.player_id into v_pid from sessions s join players p on p.id = s.player_id
   where s.token = p_token and not p.banned and s.created_at > now() - interval '180 days';
  if v_pid is null then raise exception 'bad_session'; end if;
  update sessions set last_seen = now() where token = p_token;
  return v_pid;
end $$;

-- ---------------------------------------------------------------- accounts
create or replace function public.sn_available(p_username text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('available', not exists (select 1 from players where lower(username) = lower(trim(p_username))));
$$;

create or replace function public.sn_register(p_username text, p_passcode text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_name text := regexp_replace(trim(coalesce(p_username, '')), '\s+', ' ', 'g'); v_pid uuid; v_tok uuid;
begin
  if v_name !~ '^[A-Za-z0-9_. -]{2,16}$' then return jsonb_build_object('error', 'bad_username'); end if;
  if coalesce(p_passcode, '') !~ '^[0-9]{4}$' then return jsonb_build_object('error', 'bad_passcode'); end if;
  if exists (select 1 from players where lower(username) = lower(v_name)) then return jsonb_build_object('error', 'username_taken'); end if;
  insert into players (username, pass_hash, last_login) values (v_name, crypt(p_passcode, gen_salt('bf', 8)), now()) returning id into v_pid;
  insert into sessions (player_id) values (v_pid) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'player_id', v_pid, 'username', v_name);
exception when unique_violation then
  return jsonb_build_object('error', 'username_taken');
end $$;

create or replace function public.sn_login(p_username text, p_passcode text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p players; v_tok uuid; s saves;
begin
  select * into p from players where lower(username) = lower(trim(coalesce(p_username, '')));
  if p.id is null or p.bot or p.pass_hash is null then return jsonb_build_object('error', 'bad_login'); end if;
  if p.banned then return jsonb_build_object('error', 'banned'); end if;
  if p.locked_until is not null and p.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', p.locked_until);
  end if;
  if crypt(coalesce(p_passcode, ''), p.pass_hash) <> p.pass_hash then
    update players set failed_attempts = failed_attempts + 1,
           locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
     where id = p.id;
    update players set failed_attempts = 0 where id = p.id and failed_attempts >= 5;
    return jsonb_build_object('error', 'bad_login');
  end if;
  update players set failed_attempts = 0, locked_until = null, last_login = now() where id = p.id;
  insert into sessions (player_id) values (p.id) returning token into v_tok;
  select * into s from saves where player_id = p.id;
  return jsonb_build_object('token', v_tok, 'player_id', p.id, 'username', p.username, 'save', s.data, 'save_updated', s.updated_at);
end $$;

create or replace function public.sn_logout(p_token uuid) returns jsonb
language sql security definer set search_path = public as $$
  delete from sessions where token = p_token; select jsonb_build_object('ok', true);
$$;

create or replace function public.sn_change_passcode(p_token uuid, p_old text, p_new text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_pid uuid := sn_auth(p_token); v_hash text;
begin
  select pass_hash into v_hash from players where id = v_pid;
  if crypt(coalesce(p_old, ''), v_hash) <> v_hash then return jsonb_build_object('error', 'bad_login'); end if;
  if coalesce(p_new, '') !~ '^[0-9]{4}$' then return jsonb_build_object('error', 'bad_passcode'); end if;
  update players set pass_hash = crypt(p_new, gen_salt('bf', 8)) where id = v_pid;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- cloud saves
create or replace function public.sn_save(p_token uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pid uuid := sn_auth(p_token);
begin
  if pg_column_size(p_data) > 2000000 then return jsonb_build_object('error', 'too_large'); end if;
  insert into saves (player_id, data, updated_at) values (v_pid, p_data, now())
  on conflict (player_id) do update set data = excluded.data, updated_at = now();
  return jsonb_build_object('ok', true, 'updated_at', now());
end $$;

create or replace function public.sn_load(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pid uuid := sn_auth(p_token); s saves;
begin
  select * into s from saves where player_id = v_pid;
  return jsonb_build_object('data', s.data, 'updated_at', s.updated_at);
end $$;

-- ---------------------------------------------------------------- runs
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

drop function if exists public.sn_leaderboard(text, text, int, uuid);
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


-- ---------------------------------------------------------------- permissions
revoke execute on function public.sn_auth(uuid) from public, anon, authenticated;
revoke execute on function public.sn_runs_score() from public, anon, authenticated;
grant execute on function
  public.sn_available(text), public.sn_register(text, text), public.sn_login(text, text), public.sn_logout(uuid),
  public.sn_change_passcode(uuid, text, text), public.sn_save(uuid, jsonb), public.sn_load(uuid),
  public.sn_post_run(uuid, jsonb), public.sn_leaderboard(text, text, int, uuid)
  to anon, authenticated;

-- ================================================================ FEEDBACK (v1.1.0)
-- Players send bug reports / suggestions from Settings → Send feedback, optionally
-- with up to 3 screenshots or screen recordings (25 MB total).
-- Review them in Table Editor → feedback (or the feedback_inbox view) and
-- Storage → feedback (one folder per report id).
create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  kind        text not null check (kind in ('bug', 'idea', 'other')),
  title       text not null,
  body        text not null,
  contact     text,
  player_id   uuid references public.players(id) on delete set null,
  username    text,
  version     text,
  device      jsonb not null default '{}'::jsonb,
  files       jsonb not null default '[]'::jsonb,
  status      text not null default 'new' check (status in ('new', 'reviewing', 'planned', 'done', 'wontfix')),
  owner_note  text,
  ip_hash     text
);
create index if not exists feedback_created on public.feedback (created_at desc);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

-- Private storage bucket for attachments (images and videos only, 25 MB per file).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback', 'feedback', false, 26214400, array['image/*', 'video/*'])
on conflict (id) do update set public = false, file_size_limit = 26214400, allowed_mime_types = array['image/*', 'video/*'];

-- Uploads are only allowed to the exact file paths handed out by sn_feedback_submit, within an hour.
create or replace function public.sn_fb_can_upload(p_name text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  begin v_id := split_part(p_name, '/', 1)::uuid; exception when others then return false; end;
  return exists (select 1 from feedback f where f.id = v_id and f.created_at > now() - interval '1 hour'
                 and exists (select 1 from jsonb_array_elements(f.files) x where x->>'path' = p_name));
end $$;
revoke execute on function public.sn_fb_can_upload(text) from public;
grant execute on function public.sn_fb_can_upload(text) to anon, authenticated;

drop policy if exists "feedback uploads" on storage.objects;
create policy "feedback uploads" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'feedback' and public.sn_fb_can_upload(name));

create or replace function public.sn_feedback_submit(p_report jsonb, p_token uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  v_kind text := coalesce(p_report->>'kind', 'other');
  v_title text := left(btrim(coalesce(p_report->>'title', '')), 120);
  v_body text := left(btrim(coalesce(p_report->>'body', '')), 5000);
  v_files jsonb := coalesce(p_report->'files', '[]'::jsonb);
  v_hdr json; v_ip text; v_hash text; v_pid uuid; v_user text; v_id uuid := gen_random_uuid();
  v_out jsonb := '[]'::jsonb; v_total bigint := 0; f jsonb; v_n int := 0; v_name text;
begin
  if v_kind not in ('bug', 'idea', 'other') then v_kind := 'other'; end if;
  if length(v_title) < 3 then raise exception 'Please add a short title.'; end if;
  if length(v_body) < 10 then raise exception 'Please describe it in a bit more detail.'; end if;
  if jsonb_typeof(v_files) <> 'array' or jsonb_array_length(v_files) > 3 then raise exception 'Up to 3 attachments.'; end if;

  -- light spam protection: 5 reports per person (IP) per day, 300 per day overall
  begin v_hdr := current_setting('request.headers', true)::json; exception when others then v_hdr := null; end;
  v_ip := coalesce(v_hdr->>'cf-connecting-ip', split_part(coalesce(v_hdr->>'x-forwarded-for', ''), ',', 1));
  if coalesce(v_ip, '') <> '' then
    v_hash := encode(digest(v_ip || 'signal-noise', 'sha256'), 'hex');
    if (select count(*) from feedback where ip_hash = v_hash and created_at > now() - interval '1 day') >= 5 then
      raise exception 'Thanks! You''ve sent 5 reports today. Please try again tomorrow.';
    end if;
  end if;
  if (select count(*) from feedback where created_at > now() - interval '1 day') >= 300 then
    raise exception 'The feedback inbox is full for today. Please try again tomorrow.';
  end if;

  if p_token is not null then
    v_pid := sn_auth(p_token);
    if v_pid is not null then select username into v_user from players where id = v_pid; end if;
  end if;

  for f in select * from jsonb_array_elements(v_files) loop
    v_n := v_n + 1;
    if coalesce(f->>'type', '') !~ '^(image|video)/' then raise exception 'Attachments must be images or videos.'; end if;
    v_total := v_total + coalesce((f->>'size')::bigint, 0);
    v_name := left(regexp_replace(coalesce(f->>'name', 'file'), '[^A-Za-z0-9._-]+', '_', 'g'), 60);
    v_out := v_out || jsonb_build_object('path', v_id || '/' || v_n || '-' || v_name, 'name', f->>'name', 'type', f->>'type', 'size', (f->>'size')::bigint, 'uploaded', false);
  end loop;
  if v_total > 26214400 then raise exception 'Attachments are limited to 25 MB in total.'; end if;

  insert into feedback (id, kind, title, body, contact, player_id, username, version, device, files, ip_hash)
  values (v_id, v_kind, v_title, v_body, nullif(left(btrim(coalesce(p_report->>'contact', '')), 120), ''), v_pid, v_user,
          left(p_report->>'version', 20), coalesce(p_report->'device', '{}'::jsonb), v_out, v_hash);
  return jsonb_build_object('ok', true, 'id', v_id, 'paths', (select coalesce(jsonb_agg(x->>'path'), '[]'::jsonb) from jsonb_array_elements(v_out) x));
end $$;

-- Marks which attachments actually finished uploading.
create or replace function public.sn_feedback_done(p_id uuid, p_paths text[]) returns jsonb
language sql volatile security definer set search_path = public as $$
  update feedback set files = (select coalesce(jsonb_agg(case when x->>'path' = any(p_paths) then jsonb_set(x, '{uploaded}', 'true') else x end), '[]'::jsonb) from jsonb_array_elements(files) x)
  where id = p_id and created_at > now() - interval '1 hour';
  select jsonb_build_object('ok', true);
$$;
grant execute on function public.sn_feedback_submit(jsonb, uuid), public.sn_feedback_done(uuid, text[]) to anon, authenticated;

-- Owner's inbox: newest first, with attachment counts. (Not visible to players.)
create or replace view public.feedback_inbox as
  select created_at, status, kind, title, body, coalesce(username, '(anonymous)') as player, contact, version,
         jsonb_array_length(files) as attachments,
         (select count(*) from jsonb_array_elements(files) x where (x->>'uploaded')::boolean) as uploaded,
         device->>'screen' as screen, device->>'ua' as browser, owner_note, id
  from public.feedback order by created_at desc;
revoke all on public.feedback_inbox from anon, authenticated;


-- ---------------------------------------------------------------- sample (BOT) entries
-- Five sample scores so the boards aren't empty at launch. Delete with:
--   delete from players where bot;
insert into players (username, bot) values
  ('BOT-Sentinel', true), ('BOT-Cipher', true), ('BOT-Halogen', true), ('BOT-Grepster', true), ('BOT-Patch', true)
on conflict do nothing;
insert into runs (id, player_id, diff, seed, status, cause, shifts, tier, acc, decisions, prevented, boss_won, sla, grade_pts, last_grade, started_at, updated_at)
select v.id, p.id, v.diff, v.seed, 'ended', v.cause, v.shifts, v.tier, v.acc, v.decisions, v.prevented, v.boss_won, v.sla, v.gp, v.lg, v.ts - interval '3 days', v.ts
from (values
  ('bot01', 'BOT-Sentinel', 'advanced', 'BOT-SENT01', 'retired',    31, 4, 91, 820, 22, 7, 14, 2300, 'A', timestamptz '2026-11-19 22:41+00'),
  ('bot02', 'BOT-Cipher',   'veteran',  'BOT-CIPH02', 'breach',     26, 3, 89, 640, 17, 5, 11, 1750, 'B', timestamptz '2026-11-18 03:12+00'),
  ('bot04', 'BOT-Halogen',  'standard', 'BOT-HALO04', 'burnout',    24, 3, 92, 540, 15, 4,  9, 1700, 'A', timestamptz '2026-11-17 15:30+00'),
  ('bot07', 'BOT-Grepster', 'beginner', 'BOT-GREP07', 'burnout',    20, 2, 95, 300, 10, 3,  2, 1600, 'A', timestamptz '2026-11-15 19:48+00'),
  ('bot10', 'BOT-Patch',    'beginner', 'BOT-PATC10', 'resigned',    4, 0, 76,  55,  1, 0,  4,  130, 'D', timestamptz '2026-11-10 09:30+00')
) as v(id, name, diff, seed, cause, shifts, tier, acc, decisions, prevented, boss_won, sla, gp, lg, ts)
join players p on p.username = v.name
on conflict (id) do nothing;

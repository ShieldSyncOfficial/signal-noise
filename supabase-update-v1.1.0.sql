-- =====================================================================
-- SIGNAL//NOISE · database update for v1.1.0
-- Adds player feedback / bug reports with screenshot & video attachments.
-- Run once in Supabase → SQL Editor (paste everything → Run). Safe to re-run.
-- Requires the v1.0.0 setup/update to have been run already.
-- =====================================================================

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

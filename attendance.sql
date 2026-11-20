-- UNO Airways: xodimlar davomati (eshik telefoni orqali)
-- Supabase → SQL Editor → shu faylni to'liq joylab → Run. Qayta ishga tushirish xavfsiz.
-- (setup.sql oldin ishga tushirilgan bo'lishi kerak; telegram.sql bo'lsa, xabarlar Telegram'ga ham boradi)

create extension if not exists pg_net;

-- yashirin sozlamalar (telegram.sql bilan bir xil; bu yerda ham yaratiladi)
create table if not exists public.uno_private (key text primary key, value text);
alter table public.uno_private enable row level security;
revoke all on public.uno_private from anon, authenticated;
create or replace function public.uno_priv(k text) returns text
language sql stable security definer set search_path = public as $$
  select value from public.uno_private where key = k;
$$;
revoke all on function public.uno_priv(text) from public, anon, authenticated;

-- ===== jadvallar =====
create table if not exists public.uno_staff (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text not null default '',
  pin text not null,
  shift_start time not null default '10:00',
  shift_end time not null default '23:00',
  days int[] not null default '{1,2,3,4,5,6,7}',   -- 1 = dushanba … 7 = yakshanba
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists uno_staff_pin_active on public.uno_staff(pin) where active;
alter table public.uno_staff add column if not exists team text not null default '';

create table if not exists public.uno_att_devices (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Eshik',
  token text not null unique,
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen timestamptz
);

create table if not exists public.uno_att (
  id bigserial primary key,
  staff_id uuid not null references public.uno_staff(id) on delete cascade,
  kind text not null check (kind in ('in','out')),
  at timestamptz not null default now(),
  late_min int not null default 0,      -- kelganda: smena boshidan necha daqiqa keyin
  early_min int not null default 0,     -- ketganda: smena tugashidan necha daqiqa oldin
  worked_min int,                       -- ketganda: shu kelishdan beri ishlagan daqiqa
  photo text,                           -- kichik selfi (data:image/jpeg;base64,…)
  device_id uuid references public.uno_att_devices(id) on delete set null,
  offline boolean not null default false,
  manual boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.uno_att add column if not exists photo_key uuid not null default gen_random_uuid();
alter table public.uno_att add column if not exists tg_text text;
alter table public.uno_att add column if not exists notified boolean not null default true;
create index if not exists uno_att_staff_at on public.uno_att(staff_id, at desc);
create index if not exists uno_att_pending on public.uno_att(created_at) where not notified;
create index if not exists uno_att_at on public.uno_att(at desc);

create table if not exists public.uno_att_alerts (staff_id uuid not null references public.uno_staff(id) on delete cascade, day date not null, kind text not null, primary key (staff_id, day, kind));
create table if not exists public.uno_att_fails (device_id uuid, at timestamptz not null default now());

-- ===== ruxsatlar: faqat admin ko'radi va o'zgartiradi; eshik telefoni faqat funksiya orqali =====
alter table public.uno_staff enable row level security;
alter table public.uno_att_devices enable row level security;
alter table public.uno_att enable row level security;
alter table public.uno_att_alerts enable row level security;
alter table public.uno_att_fails enable row level security;
revoke all on public.uno_staff, public.uno_att_devices, public.uno_att, public.uno_att_alerts, public.uno_att_fails from anon;
grant select, insert, update, delete on public.uno_staff, public.uno_att_devices, public.uno_att to authenticated;
grant usage, select on sequence public.uno_att_id_seq to authenticated;

drop policy if exists uno_staff_admin on public.uno_staff;
create policy uno_staff_admin on public.uno_staff for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());
drop policy if exists uno_att_devices_admin on public.uno_att_devices;
create policy uno_att_devices_admin on public.uno_att_devices for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());
drop policy if exists uno_att_admin on public.uno_att;
create policy uno_att_admin on public.uno_att for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());

-- ===== yordamchi =====
create or replace function public.uno_att_cfg(k text, def text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(public.uno_priv('att_' || k), ''), def);
$$;
revoke all on function public.uno_att_cfg(text, text) from public, anon, authenticated;

create or replace function public.uno_tz() returns text language sql stable security definer set search_path = public as $$
  select public.uno_att_cfg('tz', 'Asia/Tashkent');
$$;

create or replace function public.uno_esc2(s text) returns text language sql immutable as $$
  select replace(replace(replace(coalesce(s,''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
$$;

create or replace function public.uno_dur(m int) returns text language sql immutable as $$
  select case when coalesce(m,0) < 60 then coalesce(m,0) || ' daq'
              else (m / 60) || ' soat' || case when m % 60 > 0 then ' ' || (m % 60) || ' daq' else '' end end;
$$;

-- davomat xabari: alohida guruh (att_chat) bo'lsa o'shanga, bo'lmasa ofitsiantlar guruhiga
create or replace function public.uno_att_tg(p_text text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare tok text := public.uno_priv('tg_token'); chat text := coalesce(nullif(public.uno_priv('att_chat'),''), public.uno_priv('tg_chat'));
begin
  if coalesce(public.uno_priv('att_tg'), 'on') = 'off' then return; end if;
  if coalesce(tok,'') = '' or coalesce(chat,'') = '' then return; end if;
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/sendMessage',
    body := jsonb_build_object('chat_id', chat, 'text', p_text, 'parse_mode', 'HTML', 'disable_web_page_preview', true),
    headers := '{"Content-Type":"application/json"}'::jsonb);
exception when others then
  raise warning 'telegram: %', sqlerrm;
end $$;
revoke all on function public.uno_att_tg(text) from public, anon, authenticated;

-- suratli xabar (Telegram suratni ochiq havoladan yuklab oladi)
create or replace function public.uno_att_tg_photo(p_url text, p_caption text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare tok text := public.uno_priv('tg_token'); chat text := coalesce(nullif(public.uno_priv('att_chat'),''), public.uno_priv('tg_chat'));
begin
  if coalesce(public.uno_priv('att_tg'), 'on') = 'off' then return; end if;
  if coalesce(tok,'') = '' or coalesce(chat,'') = '' then return; end if;
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/sendPhoto',
    body := jsonb_build_object('chat_id', chat, 'photo', p_url, 'caption', left(p_caption, 1000), 'parse_mode', 'HTML'),
    headers := '{"Content-Type":"application/json"}'::jsonb);
exception when others then
  raise warning 'telegram: %', sqlerrm;
end $$;
revoke all on function public.uno_att_tg_photo(text, text) from public, anon, authenticated;

-- selfi suratlar uchun papka: eshik telefoni faqat yangi belgining bir martalik kaliti bilan, 10 daqiqa ichida yuklay oladi
insert into storage.buckets (id, name, public, file_size_limit)
values ('uno-att', 'uno-att', true, 400000)
on conflict (id) do update set public = true, file_size_limit = 400000;

create or replace function public.uno_att_can_upload(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.uno_att
                 where photo_key::text = regexp_replace(coalesce(p_name,''), '\.jpg$', '')
                   and created_at > now() - interval '10 minutes');
$$;
grant execute on function public.uno_att_can_upload(text) to anon, authenticated;
drop policy if exists uno_att_photo_insert on storage.objects;
create policy uno_att_photo_insert on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'uno-att' and public.uno_att_can_upload(name));
drop policy if exists uno_att_photo_delete on storage.objects;
create policy uno_att_photo_delete on storage.objects for delete to authenticated using (bucket_id = 'uno-att' and public.uno_is_admin());

-- ===== admin: shu telefonni eshik terminali qilish =====
create or replace function public.uno_att_register(p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.uno_att_devices;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_att_devices(name, token)
  values (coalesce(nullif(trim(p_name),''), 'Eshik'), replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
  returning * into d;
  return jsonb_build_object('id', d.id, 'token', d.token, 'name', d.name);
end $$;

-- ===== admin: sozlamalar =====
create or replace function public.uno_att_settings() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return jsonb_build_object('grace', public.uno_att_cfg('grace','10')::int, 'absent', public.uno_att_cfg('absent','30')::int,
    'chat', coalesce(public.uno_priv('att_chat'),''), 'tg', coalesce(public.uno_priv('att_tg'),'on'),
    'tg_ready', coalesce(public.uno_priv('tg_token'),'') <> '' and coalesce(public.uno_priv('tg_chat'),'') <> '');
end $$;

create or replace function public.uno_att_set(p_grace int, p_absent int, p_chat text, p_tg text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_private(key, value) values
    ('att_grace', greatest(0, least(120, coalesce(p_grace,10)))::text),
    ('att_absent', greatest(5, least(600, coalesce(p_absent,30)))::text),
    ('att_chat', coalesce(trim(p_chat),'')),
    ('att_tg', case when p_tg = 'off' then 'off' else 'on' end)
  on conflict (key) do update set value = excluded.value;
end $$;

-- ===== eshik telefoni: qurilmani tekshirish =====
create or replace function public.uno_att_hello(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.uno_att_devices;
begin
  select * into d from public.uno_att_devices where token = p_token and not revoked;
  if d.id is null then return jsonb_build_object('ok', false); end if;
  update public.uno_att_devices set last_seen = now() where id = d.id;
  perform public.uno_att_check_absent();
  return jsonb_build_object('ok', true, 'name', d.name, 'now', now());
end $$;

-- ===== eshik telefoni: PIN bilan kelish/ketishni belgilash =====
drop function if exists public.uno_att_punch(text, text, text, timestamptz);
create or replace function public.uno_att_punch(p_token text, p_pin text, p_photo text default null, p_at timestamptz default null, p_wait boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  newid bigint; pkey uuid;
  d public.uno_att_devices; s public.uno_staff; last public.uno_att;
  ts timestamptz := now(); tz text := public.uno_tz(); loc timestamp; sched timestamp; send timestamp;
  k text; late int := 0; early int := 0; worked int; grace int := public.uno_att_cfg('grace','10')::int;
  txt text; offline boolean := false; fails int;
begin
  select * into d from public.uno_att_devices where token = p_token and not revoked;
  if d.id is null then return jsonb_build_object('ok', false, 'err', 'bad_device'); end if;

  select count(*) into fails from public.uno_att_fails where device_id = d.id and at > now() - interval '5 minutes';
  if fails >= 12 then return jsonb_build_object('ok', false, 'err', 'too_many'); end if;

  select * into s from public.uno_staff where pin = trim(coalesce(p_pin,'')) and active;
  if s.id is null then
    insert into public.uno_att_fails(device_id) values (d.id);
    delete from public.uno_att_fails where at < now() - interval '1 day';
    return jsonb_build_object('ok', false, 'err', 'bad_pin');
  end if;

  -- internetsiz belgilangan bo'lsa, telefondagi vaqt olinadi (2 kundan eski emas, kelajakda emas)
  if p_at is not null and p_at < now() - interval '20 seconds' and p_at > now() - interval '2 days' then ts := p_at; offline := true; end if;
  loc := ts at time zone tz;

  select * into last from public.uno_att where staff_id = s.id and at <= ts order by at desc limit 1;
  -- ikki marta bosilib ketsa (2 daqiqa ichida) qayta yozilmaydi
  if last.id is not null and ts - last.at < interval '2 minutes' then
    return jsonb_build_object('ok', true, 'dup', true, 'kind', last.kind, 'name', s.name, 'at', last.at, 'late', last.late_min, 'grace', grace, 'worked', last.worked_min);
  end if;
  k := case when last.kind = 'in' and ts - last.at < interval '18 hours' then 'out' else 'in' end;

  if k = 'in' then
    if extract(isodow from loc)::int = any(s.days) then
      sched := loc::date + s.shift_start;
      -- tungi smena: yarim tundan keyin kelsa, kechagi smena hisoblanadi
      if loc < sched - interval '12 hours' then sched := sched - interval '1 day'; end if;
      late := greatest(0, floor(extract(epoch from (loc - sched)) / 60))::int;
      if late > 12 * 60 then late := 0; end if;
    end if;
  else
    worked := greatest(0, floor(extract(epoch from (ts - last.at)) / 60))::int;
    sched := (last.at at time zone tz)::date + s.shift_end;
    if s.shift_end <= s.shift_start then sched := sched + interval '1 day'; end if;
    early := greatest(0, floor(extract(epoch from (sched - loc)) / 60))::int;
    if early > 12 * 60 then early := 0; end if;
  end if;

  update public.uno_att_devices set last_seen = now() where id = d.id;

  if k = 'in' then
    txt := case when late > grace then '🔴 <b>' || uno_esc2(s.name) || '</b> ' || to_char(loc,'HH24:MI') || ' da keldi — <b>' || uno_dur(late) || ' kechikdi</b>'
                else '🟢 <b>' || uno_esc2(s.name) || '</b> ' || to_char(loc,'HH24:MI') || ' da keldi' end;
  else
    txt := '🔵 <b>' || uno_esc2(s.name) || '</b> ' || to_char(loc,'HH24:MI') || ' da ketdi · ishladi: ' || uno_dur(worked)
           || case when early > grace then ' · <b>' || uno_dur(early) || ' erta ketdi</b>' else '' end;
  end if;
  if s.team <> '' or s.role <> '' then
    txt := txt || E'\n<i>' || uno_esc2(concat_ws(' · ', nullif(s.team,''), nullif(s.role,''))) || '</i>';
  end if;
  txt := txt || E'\n📅 ' || to_char(loc,'DD.MM.YYYY HH24:MI');
  if offline then txt := txt || E'\n(internetsiz belgilangan, keyin yuborildi)'; end if;

  insert into public.uno_att(staff_id, kind, at, late_min, early_min, worked_min, photo, device_id, offline, tg_text, notified)
  values (s.id, k, ts, late, early, worked, left(p_photo, 120000), d.id, offline, txt, not p_wait)
  returning id, photo_key into newid, pkey;
  -- surat yuklanishi kutilsa, xabar uno_att_notify da (surat bilan) yuboriladi
  if not p_wait then perform public.uno_att_tg(txt); end if;

  return jsonb_build_object('ok', true, 'kind', k, 'name', s.name, 'at', ts, 'late', late, 'grace', grace, 'worked', worked, 'early', early,
                            'key', case when p_wait then pkey end);
end $$;

-- ===== eshik telefoni: surat yuklandi (yoki yuklanmadi) — Telegram'ga xabar =====
create or replace function public.uno_att_notify(p_token text, p_key uuid, p_has_photo boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.uno_att_devices; r public.uno_att; base text := coalesce(nullif(public.uno_priv('sb_url'),''), 'https://eaxavnixuqgwashplnhz.supabase.co');
begin
  select * into d from public.uno_att_devices where token = p_token and not revoked;
  if d.id is null then return jsonb_build_object('ok', false); end if;
  update public.uno_att set notified = true where photo_key = p_key and device_id = d.id and not notified returning * into r;
  if r.id is null then return jsonb_build_object('ok', true, 'already', true); end if;
  if p_has_photo then perform public.uno_att_tg_photo(base || '/storage/v1/object/public/uno-att/' || p_key::text || '.jpg', r.tg_text);
  else perform public.uno_att_tg(r.tg_text); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ===== kelmaganlarni tekshirish (har 5 daqiqada; eshik telefoni va admin panel ham chaqiradi) =====
create or replace function public.uno_att_check_absent() returns int
language plpgsql security definer set search_path = public as $$
declare tz text := public.uno_tz(); loc timestamp := now() at time zone public.uno_tz(); absent int := public.uno_att_cfg('absent','30')::int;
        r record; sched timestamp; n int := 0; txt text := '';
begin
  for r in select * from public.uno_staff where active loop
    sched := loc::date + r.shift_start;
    if not (extract(isodow from loc)::int = any(r.days)) then continue; end if;
    if loc < sched + make_interval(mins => absent) or loc > sched + interval '6 hours' then continue; end if;
    if exists (select 1 from public.uno_att a where a.staff_id = r.id and a.kind = 'in' and a.at >= (sched - interval '6 hours') at time zone tz) then continue; end if;
    begin
      insert into public.uno_att_alerts(staff_id, day, kind) values (r.id, loc::date, 'absent');
    exception when unique_violation then continue;
    end;
    n := n + 1;
    txt := txt || E'\n• <b>' || uno_esc2(r.name) || '</b>' || case when coalesce(nullif(r.team,''), nullif(r.role,'')) is not null then ' (' || uno_esc2(coalesce(nullif(r.team,''), r.role)) || ')' else '' end
               || ' — smena ' || to_char(r.shift_start,'HH24:MI') || ' da boshlangan';
  end loop;
  if n > 0 then perform public.uno_att_tg('⚠️ <b>Hali ishga kelmadi:</b>' || txt); end if;
  -- surati kelmay qolgan belgilar: 2 daqiqadan keyin suratsiz yuboriladi
  for r in update public.uno_att set notified = true where not notified and created_at < now() - interval '2 minutes' returning tg_text loop
    perform public.uno_att_tg(r.tg_text);
  end loop;
  delete from public.uno_att_alerts where day < (loc::date - 40);
  return n;
end $$;
revoke all on function public.uno_att_check_absent() from public, anon;
grant execute on function public.uno_att_check_absent() to authenticated;

-- har 5 daqiqada avtomatik tekshirish (pg_cron bo'lmasa, o'tkazib yuboriladi)
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then raise notice 'pg_cron yoqilmadi: %', sqlerrm; return;
  end;
  begin
    perform cron.unschedule('uno-att-absent');
  exception when others then null;
  end;
  perform cron.schedule('uno-att-absent', '*/5 * * * *', 'select public.uno_att_check_absent()');
exception when others then raise notice 'cron: %', sqlerrm;
end $$;

grant execute on function public.uno_att_hello(text) to anon, authenticated;
grant execute on function public.uno_att_punch(text, text, text, timestamptz, boolean) to anon, authenticated;
grant execute on function public.uno_att_notify(text, uuid, boolean) to anon, authenticated;
grant execute on function public.uno_att_register(text) to authenticated;
grant execute on function public.uno_att_settings() to authenticated;
grant execute on function public.uno_att_set(int, int, text, text) to authenticated;

notify pgrst, 'reload schema';

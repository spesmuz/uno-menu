-- UNO Airways: davomat — kirish oynasi (smena boshidan N soat faqat "keldi") va jarimalar.
-- Supabase → SQL Editor → shu faylni joylab → Run. Avval attendance.sql ishlagan bo'lishi kerak. Qayta ishga tushirish xavfsiz.
--
-- Qoidalar (admin panel → Davomat → Sozlamalar'da o'zgartiriladi):
--   * smena boshlanishidan 5 soat ichida terminalga kelgan har bir belgi faqat KELISH deb olinadi (ikkinchi marta bossa "allaqachon belgilangan");
--     5 soatdan keyin (yoki smena bo'lmagan kunda kelgandan 5 soat o'tgach) belgi KETISH deb olinadi;
--   * kechikish: har to'liq soat uchun 50 000 so'm (1 soat — 50 000, 2 soat 10 daq — 100 000);
--   * smena kuni kelmasa (5 soat ichida belgilanmasa): 200 000 so'm;
--   * har bir jarima admin panelda "Sababli" (o'chadi) yoki "Tasdiqlash" deb hal qilinadi.

create table if not exists public.uno_att_fines (
  id         bigserial primary key,
  staff_id   uuid not null references public.uno_staff(id) on delete cascade,
  day        date not null,
  kind       text not null check (kind in ('late','absent')),
  minutes    int not null default 0,
  amount     int not null default 0,
  status     text not null default 'pending' check (status in ('pending','confirmed','excused')),
  att_id     bigint references public.uno_att(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (staff_id, day, kind)
);
create index if not exists uno_att_fines_day on public.uno_att_fines(day desc);
-- to'lov: jarima "To'landi" deb belgilanguncha xodimning qarzi bo'lib turadi
alter table public.uno_att_fines add column if not exists paid_at timestamptz;

create or replace function public.uno_att_debt(p_staff uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount),0)::int from public.uno_att_fines where staff_id = p_staff and status <> 'excused' and paid_at is null;
$$;
revoke all on function public.uno_att_debt(uuid) from public, anon;
alter table public.uno_att_fines enable row level security;
revoke all on public.uno_att_fines from anon;
grant select, update, delete on public.uno_att_fines to authenticated;
drop policy if exists uno_att_fines_admin on public.uno_att_fines;
create policy uno_att_fines_admin on public.uno_att_fines for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());

-- jarimalar faqat shu fayl ishga tushirilgandan keyingi smenalarga qo'yiladi
insert into public.uno_private(key, value) values ('att_fines_since', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
  on conflict (key) do nothing;

create or replace function public.uno_money(n int) returns text language sql immutable as $$
  select replace(to_char(coalesce(n,0), 'FM999G999G999'), ',', ' ') || ' so''m';
$$;

-- ===== sozlamalar (eski maydonlar + oyna va jarima summalari) =====
create or replace function public.uno_att_settings() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return jsonb_build_object('grace', public.uno_att_cfg('grace','10')::int, 'absent', public.uno_att_cfg('absent','30')::int,
    'chat', coalesce(public.uno_priv('att_chat'),''), 'tg', coalesce(public.uno_priv('att_tg'),'on'),
    'tg_ready', coalesce(public.uno_priv('tg_token'),'') <> '' and coalesce(public.uno_priv('tg_chat'),'') <> '',
    'window', public.uno_att_cfg('window','300')::int,
    'fine_hour', public.uno_att_cfg('fine_hour','50000')::int,
    'fine_absent', public.uno_att_cfg('fine_absent','200000')::int,
    'since', public.uno_priv('att_fines_since'),
    'fines', true);
end $$;

create or replace function public.uno_att_set_fines(p_window int, p_fine_hour int, p_fine_absent int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_private(key, value) values
    ('att_window', greatest(30, least(720, coalesce(p_window,300)))::text),
    ('att_fine_hour', greatest(0, least(10000000, coalesce(p_fine_hour,50000)))::text),
    ('att_fine_absent', greatest(0, least(10000000, coalesce(p_fine_absent,200000)))::text)
  on conflict (key) do update set value = excluded.value;
end $$;
revoke all on function public.uno_att_set_fines(int,int,int) from public, anon;
grant execute on function public.uno_att_set_fines(int,int,int) to authenticated;

-- ===== admin: davomatni "yangidan boshlash" — shu paytdan oldingi smenalar uchun "kelmadi" jarimasi yozilmaydi =====
create or replace function public.uno_att_restart() returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_private(key, value) values ('att_fines_since', t) on conflict (key) do update set value = excluded.value;
  delete from public.uno_att_alerts;
  return jsonb_build_object('ok', true, 'since', t);
end $$;
revoke all on function public.uno_att_restart() from public, anon;
grant execute on function public.uno_att_restart() to authenticated;

-- ===== admin: jarimani hal qilish =====
create or replace function public.uno_att_fine_decide(p_id bigint, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.uno_att_fines; s public.uno_staff;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  if p_status not in ('pending','confirmed','excused') then raise exception 'bad_status'; end if;
  update public.uno_att_fines set status = p_status, decided_at = case when p_status = 'pending' then null else now() end
   where id = p_id returning * into f;
  if f.id is null then return jsonb_build_object('ok', false); end if;
  if p_status = 'excused' then
    select * into s from public.uno_staff where id = f.staff_id;
    begin
      perform public.uno_att_tg('✅ <b>' || uno_esc2(s.name) || '</b> — ' || to_char(f.day,'DD.MM.YYYY') || ' dagi jarima ('
        || public.uno_money(f.amount) || ') <b>sababli</b> deb olib tashlandi.');
    exception when others then null; end;
  end if;
  return jsonb_build_object('ok', true, 'status', f.status);
end $$;
revoke all on function public.uno_att_fine_decide(bigint,text) from public, anon;
grant execute on function public.uno_att_fine_decide(bigint,text) to authenticated;

-- ===== admin: jarima to'landi (bitta jarima yoki xodimning hamma qarzi) =====
create or replace function public.uno_att_fine_paid(p_id bigint, p_paid boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.uno_att_fines;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  update public.uno_att_fines set paid_at = case when p_paid then now() end,
         status = case when p_paid and status = 'pending' then 'confirmed' else status end
   where id = p_id returning * into f;
  if f.id is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'debt', public.uno_att_debt(f.staff_id));
end $$;
revoke all on function public.uno_att_fine_paid(bigint,boolean) from public, anon;
grant execute on function public.uno_att_fine_paid(bigint,boolean) to authenticated;

create or replace function public.uno_att_pay_all(p_staff uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.uno_staff; total int; n int;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  select * into s from public.uno_staff where id = p_staff;
  total := public.uno_att_debt(p_staff);
  update public.uno_att_fines set paid_at = now(), status = case when status = 'pending' then 'confirmed' else status end
   where staff_id = p_staff and status <> 'excused' and paid_at is null;
  get diagnostics n = row_count;
  if n > 0 then
    begin
      perform public.uno_att_tg('💰 <b>' || uno_esc2(s.name) || '</b> jarimani to''ladi: <b>' || public.uno_money(total) || '</b> (' || n || ' ta).');
    exception when others then null; end;
  end if;
  return jsonb_build_object('ok', true, 'paid', total, 'count', n);
end $$;
revoke all on function public.uno_att_pay_all(uuid) from public, anon;
grant execute on function public.uno_att_pay_all(uuid) to authenticated;

-- ===== terminal: PIN bilan kelish/ketish (kirish oynasi + jarima) =====
create or replace function public.uno_att_punch(p_token text, p_pin text, p_photo text default null, p_at timestamptz default null, p_wait boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  newid bigint; pkey uuid;
  d public.uno_att_devices; s public.uno_staff; last public.uno_att;
  ts timestamptz := now(); tz text := public.uno_tz(); loc timestamp; sched timestamp; send timestamp; anchor timestamp;
  k text; late int := 0; early int := 0; worked int; grace int := public.uno_att_cfg('grace','10')::int;
  win int := public.uno_att_cfg('window','300')::int; fh int := public.uno_att_cfg('fine_hour','50000')::int;
  fine int := 0; fine_h int := 0; sday date; scheduled boolean := false;
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

  if p_at is not null and p_at < now() - interval '20 seconds' and p_at > now() - interval '2 days' then ts := p_at; offline := true; end if;
  loc := ts at time zone tz;

  -- bugungi smena boshlanishi (tungi smena: yarim tundan keyin kelsa — kechagi smena)
  sched := loc::date + s.shift_start;
  if loc < sched - interval '12 hours' then sched := sched - interval '1 day'; end if;
  scheduled := extract(isodow from sched)::int = any(s.days);
  sday := sched::date;

  select * into last from public.uno_att where staff_id = s.id and at <= ts order by at desc limit 1;
  if last.id is not null and ts - last.at < interval '2 minutes' then
    return jsonb_build_object('ok', true, 'dup', true, 'kind', last.kind, 'name', s.name, 'at', last.at, 'late', last.late_min, 'grace', grace, 'worked', last.worked_min,
      'fine', (select coalesce(sum(amount),0) from public.uno_att_fines where staff_id = s.id and day = sday and status <> 'excused'),
      'debt', public.uno_att_debt(s.id));
  end if;

  -- oldingi smenada "ketdi" belgilanmay qolgan bo'lsa, yangi smenaga kelish — ketish emas, KELISH
  if last.kind = 'in' and ts - last.at < interval '18 hours'
     and not ((last.at at time zone tz) < sched - interval '6 hours' and loc >= sched - interval '6 hours') then
    -- kirish oynasi: smena boshidan (yoki kelgan vaqtdan, smena bo'lmasa) N daqiqa ichida qayta belgilansa — ketish emas
    anchor := case when scheduled and (last.at at time zone tz) >= sched - interval '6 hours' then sched else (last.at at time zone tz) end;
    if loc < anchor + make_interval(mins => win) and coalesce(current_setting('uno.force_out', true), '') <> '1' then
      return jsonb_build_object('ok', true, 'dup', true, 'already_in', true, 'kind', 'in', 'name', s.name, 'at', last.at, 'late', last.late_min, 'grace', grace,
        'out_from', (anchor + make_interval(mins => win)) at time zone tz,
        'fine', (select coalesce(sum(amount),0) from public.uno_att_fines where staff_id = s.id and day = sday and status <> 'excused'),
      'debt', public.uno_att_debt(s.id));
    end if;
    k := 'out';
  else
    k := 'in';
  end if;

  if k = 'in' then
    if scheduled then
      late := greatest(0, floor(extract(epoch from (loc - sched)) / 60))::int;
      if late > 12 * 60 then late := 0; end if;
    end if;
  else
    worked := greatest(0, floor(extract(epoch from (ts - last.at)) / 60))::int;
    send := (last.at at time zone tz)::date + s.shift_end;
    if s.shift_end <= s.shift_start then send := send + interval '1 day'; end if;
    early := greatest(0, floor(extract(epoch from (send - loc)) / 60))::int;
    if early > 12 * 60 then early := 0; end if;
  end if;

  update public.uno_att_devices set last_seen = now() where id = d.id;

  -- har to'liq kechikkan soat uchun (1 soat kechiksa — 1 × summa, 2 soat 10 daqiqa — 2 × summa)
  if k = 'in' and fh > 0 and late >= 60 then
    fine_h := floor(late / 60.0)::int; fine := fine_h * fh;
  end if;

  if k = 'in' then
    txt := case when late > grace then '🔴 <b>' || uno_esc2(s.name) || '</b> ' || to_char(loc,'HH24:MI') || ' da keldi — <b>' || uno_dur(late) || ' kechikdi</b>'
                else '🟢 <b>' || uno_esc2(s.name) || '</b> ' || to_char(loc,'HH24:MI') || ' da keldi' end;
    if fine > 0 then txt := txt || E'\n💸 Jarima: <b>' || public.uno_money(fine) || '</b> (' || fine_h || ' soat × ' || public.uno_money(fh) || ')'; end if;
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

  if k = 'in' and scheduled then
    -- kech bo'lsa ham keldi: "kelmadi" jarimasi o'rniga kechikish jarimasi
    delete from public.uno_att_fines where staff_id = s.id and day = sday and kind = 'absent' and status = 'pending';
    if fine > 0 then
      insert into public.uno_att_fines(staff_id, day, kind, minutes, amount, att_id) values (s.id, sday, 'late', late, fine, newid)
        on conflict (staff_id, day, kind) do nothing;
    end if;
  end if;

  if not p_wait then perform public.uno_att_tg(txt); end if;

  return jsonb_build_object('ok', true, 'kind', k, 'name', s.name, 'at', ts, 'late', late, 'grace', grace, 'worked', worked, 'early', early,
                            'fine', fine, 'fine_hours', fine_h, 'fine_hour', fh, 'debt', public.uno_att_debt(s.id),
                            'key', case when p_wait then pkey end);
end $$;
revoke all on function public.uno_att_punch(text,text,text,timestamptz,boolean) from public;
grant execute on function public.uno_att_punch(text,text,text,timestamptz,boolean) to anon, authenticated;

-- ===== terminal: xodim "Ketishni belgilash" tugmasini bosdi (oyna ichida ham ketishni qayd qiladi) =====
create or replace function public.uno_att_punch_out(p_token text, p_pin text, p_photo text default null, p_wait boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform set_config('uno.force_out', '1', true);
  r := public.uno_att_punch(p_token, p_pin, p_photo, null, p_wait);
  perform set_config('uno.force_out', '', true);
  return r;
end $$;
revoke all on function public.uno_att_punch_out(text,text,text,boolean) from public;
grant execute on function public.uno_att_punch_out(text,text,text,boolean) to anon, authenticated;

-- ===== kelmaganlar: ogohlantirish + oyna tugagach "kelmadi" jarimasi =====
create or replace function public.uno_att_check_absent() returns int
language plpgsql security definer set search_path = public as $$
declare tz text := public.uno_tz(); loc timestamp := now() at time zone public.uno_tz(); absent int := public.uno_att_cfg('absent','30')::int;
        win int := public.uno_att_cfg('window','300')::int; fa int := public.uno_att_cfg('fine_absent','200000')::int;
        since timestamptz := coalesce(nullif(public.uno_priv('att_fines_since'),'')::timestamptz, now());
        r record; sched timestamp; n int := 0; txt text := ''; ftxt text := ''; nf int := 0; fid bigint;
begin
  for r in select * from public.uno_staff where active loop
    for sched in select (loc::date + r.shift_start) union all select (loc::date - 1 + r.shift_start) loop
      if not (extract(isodow from sched)::int = any(r.days)) then continue; end if;
      if exists (select 1 from public.uno_att a where a.staff_id = r.id and a.kind = 'in'
                  and a.at >= (sched - interval '6 hours') at time zone tz and a.at < (sched + interval '12 hours') at time zone tz) then continue; end if;
      -- ogohlantirish: smenadan N daqiqa o'tdi, hali yo'q (faqat bugungi smena)
      if sched::date = loc::date and loc >= sched + make_interval(mins => absent) and loc <= sched + interval '6 hours' then
        begin
          insert into public.uno_att_alerts(staff_id, day, kind) values (r.id, sched::date, 'absent');
          n := n + 1;
          txt := txt || E'\n• <b>' || uno_esc2(r.name) || '</b>' || case when coalesce(nullif(r.team,''), nullif(r.role,'')) is not null then ' (' || uno_esc2(coalesce(nullif(r.team,''), r.role)) || ')' else '' end
                     || ' — smena ' || to_char(r.shift_start,'HH24:MI') || ' da boshlangan';
        exception when unique_violation then null;
        end;
      end if;
      -- jarima: kirish oynasi tugadi, kelmadi
      if fa > 0 and loc >= sched + make_interval(mins => win) and loc < sched + interval '30 hours'
         and (sched + make_interval(mins => win)) at time zone tz >= since then
        fid := null;
        insert into public.uno_att_fines(staff_id, day, kind, minutes, amount) values (r.id, sched::date, 'absent', 0, fa)
          on conflict (staff_id, day, kind) do nothing returning id into fid;
        if fid is not null then
          nf := nf + 1;
          ftxt := ftxt || E'\n• <b>' || uno_esc2(r.name) || '</b> — ' || to_char(sched,'DD.MM') || ', smena ' || to_char(r.shift_start,'HH24:MI');
        end if;
      end if;
    end loop;
  end loop;
  -- kelgan bo'lsa ham yozilib qolgan "kelmadi" jarimalarini olib tashlash
  delete from public.uno_att_fines f using public.uno_staff sx
   where f.kind = 'absent' and f.status = 'pending' and sx.id = f.staff_id
     and exists (select 1 from public.uno_att a where a.staff_id = f.staff_id and a.kind = 'in'
                  and a.at >= ((f.day + sx.shift_start) - interval '6 hours') at time zone tz
                  and a.at <  ((f.day + sx.shift_start) + interval '12 hours') at time zone tz);
  if n > 0 then perform public.uno_att_tg('⚠️ <b>Hali ishga kelmadi:</b>' || txt); end if;
  if nf > 0 then perform public.uno_att_tg('💸 <b>Kelmadi — jarima ' || public.uno_money(fa) || ':</b>' || ftxt
                                           || E'\nSababli bo''lsa: admin panel → Davomat → Jarimalar → «Sababli».'); end if;
  for r in update public.uno_att set notified = true where not notified and created_at < now() - interval '2 minutes' returning tg_text loop
    perform public.uno_att_tg(r.tg_text);
  end loop;
  delete from public.uno_att_alerts where day < (loc::date - 40);
  return n;
end $$;
revoke all on function public.uno_att_check_absent() from public, anon;
grant execute on function public.uno_att_check_absent() to authenticated;

-- ===== bir martalik tuzatish: "ketdi" belgilanmay qolgani uchun KELISH "ketish" bo'lib yozilgan belgilarni qayta hisoblash =====
do $$
declare tz text := public.uno_tz(); sr record; ar record; pk text; pat timestamptz; loc timestamp; sched timestamp; scheduled boolean;
        k text; late int; early int; worked int; send timestamp; fh int := public.uno_att_cfg('fine_hour','50000')::int; nfix int := 0;
begin
  for sr in select * from public.uno_staff loop
    pk := null; pat := null;
    for ar in select * from public.uno_att where staff_id = sr.id and at >= timestamptz '2026-11-01' order by at loop
      loc := ar.at at time zone tz;
      sched := loc::date + sr.shift_start;
      if loc < sched - interval '12 hours' then sched := sched - interval '1 day'; end if;
      scheduled := extract(isodow from sched)::int = any(sr.days);
      if pk = 'in' and ar.at - pat < interval '18 hours'
         and not ((pat at time zone tz) < sched - interval '6 hours' and loc >= sched - interval '6 hours') then k := 'out'; else k := 'in'; end if;
      if k <> ar.kind then
        late := 0; early := 0; worked := null;
        if k = 'in' then
          if scheduled then late := greatest(0, floor(extract(epoch from (loc - sched)) / 60))::int; if late > 720 then late := 0; end if; end if;
        else
          worked := greatest(0, floor(extract(epoch from (ar.at - pat)) / 60))::int;
          send := (pat at time zone tz)::date + sr.shift_end; if sr.shift_end <= sr.shift_start then send := send + interval '1 day'; end if;
          early := greatest(0, floor(extract(epoch from (send - loc)) / 60))::int; if early > 720 then early := 0; end if;
        end if;
        update public.uno_att set kind = k, late_min = late, early_min = early, worked_min = worked where id = ar.id;
        nfix := nfix + 1;
        if k = 'in' and scheduled and fh > 0 and late >= 60 then
          insert into public.uno_att_fines(staff_id, day, kind, minutes, amount, att_id) values (sr.id, sched::date, 'late', late, floor(late/60.0)::int * fh, ar.id)
            on conflict (staff_id, day, kind) do nothing;
        end if;
        if k = 'out' then delete from public.uno_att_fines where att_id = ar.id and status = 'pending'; end if;
      end if;
      pk := k; pat := ar.at;
    end loop;
  end loop;
  -- kelgan kunlar uchun yozilgan "kelmadi" jarimalari
  delete from public.uno_att_fines f using public.uno_staff sx
   where f.kind = 'absent' and f.status = 'pending' and sx.id = f.staff_id
     and exists (select 1 from public.uno_att a where a.staff_id = f.staff_id and a.kind = 'in'
                  and a.at >= ((f.day + sx.shift_start) - interval '6 hours') at time zone tz
                  and a.at <  ((f.day + sx.shift_start) + interval '12 hours') at time zone tz);
  raise notice 'tuzatildi: % ta belgi', nfix;
end $$;

notify pgrst, 'reload schema';

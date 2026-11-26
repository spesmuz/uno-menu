-- UNO Airways — ofitsiantlar ROTATSIYASI (stollar taqsimoti), davomat bilan bog'langan
-- Asos: 4 ta PDF (1/2-guruh × Biznes/Comfort). Guruhlar har kuni hudud almashadi, "Kun" har kuni +1.
-- Har kuni 18:00 da: kelmagan ofitsiantning stollari shu hududdagi o'z guruhidagi kelganlarga
-- QO'SHNI stollar bo'yicha bo'lib beriladi (faqat o'sha kun uchun; asosiy ro'yxat o'zgarmaydi),
-- natija Telegram guruhga yuboriladi va terminalda ko'rinadi.
-- Supabase → SQL Editor → shu faylni to'liq joylab Run. Qayta ishga tushirish xavfsiz.

create table if not exists public.uno_rot (id int primary key default 1 check (id = 1), cfg jsonb not null, updated_at timestamptz not null default now());
create table if not exists public.uno_rot_day (day date primary key, plan jsonb not null, made_at timestamptz not null default now(), sent boolean not null default false);
alter table public.uno_rot enable row level security;
alter table public.uno_rot_day enable row level security;
drop policy if exists uno_rot_admin on public.uno_rot;
create policy uno_rot_admin on public.uno_rot for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());
drop policy if exists uno_rot_day_admin on public.uno_rot_day;
create policy uno_rot_day_admin on public.uno_rot_day for all to authenticated using (public.uno_is_admin()) with check (public.uno_is_admin());

create or replace function public.uno_rot_norm(s text) returns text language sql immutable as $$
  select lower(regexp_replace(translate(coalesce(s,''), 'xXʻʼ‘’''`', 'hh'), '[^[:alpha:]]', '', 'g'));
$$;

-- PDF'dagi asosiy ro'yxat (bir marta); ismlar xodimlarga avtomatik bog'lanadi, qolganini admin paneldan tanlaysiz
insert into public.uno_rot(id, cfg) values (1, $J${"anchor": "2026-11-26", "biznes_first": 0, "groups": [{"name": "1-guruh", "members": ["Asadbek", "Abdulaziz", "Sarvarbek", "Xusanbo'y", "Islomjon", "O'g'iloy", "Jasur", "Durdona", "Egamberdi", "Axliyor"], "zones": {"Biznes": ["1,2,3", "4,5,6", "7,8,9", "10,11,12", "13,14,15", "16,17,18", "19,20", "21,22", "23,24", "Konferensiya, VIP 1 va VIP 2"], "Comfort": ["1,2,3", "4,5,6", "7,8,9", "10,11", "12,13", "14,15", "16,17", "18,19", "Balkon", "Family"]}}, {"name": "2-guruh", "members": ["Asliddin", "Shoxruz", "Murodjon", "Farjona", "Xasanboy", "Azizbek", "Diyorbek", "Qodirxon", "Shaxrizoda", "Baxrom", "Bobur"], "zones": {"Biznes": ["1,2,3", "4,5,6", "7,8,9", "10,11,12", "13,14", "15,16", "17,18", "19,20", "21,22", "23,24", "Konferensiya, VIP 1 va VIP 2"], "Comfort": ["1,2,3", "4,5", "6,7", "8,9", "10,11", "12,13", "14,15", "16,17", "18,19", "Balkon", "Family"]}}], "map": {}}$J$::jsonb) on conflict (id) do nothing;

create or replace function public.uno_rot_automap() returns void language plpgsql security definer set search_path = public as $$
declare c jsonb; g jsonb; m text; sid uuid; mp jsonb;
begin
  select cfg into c from public.uno_rot where id = 1; if c is null then return; end if;
  mp := coalesce(c->'map', '{}'::jsonb);
  for g in select * from jsonb_array_elements(c->'groups') loop
    for m in select * from jsonb_array_elements_text(g->'members') loop
      if mp ? m then continue; end if;
      select id into sid from public.uno_staff where active and public.uno_rot_norm(name) = public.uno_rot_norm(m) limit 1;
      if sid is not null then mp := mp || jsonb_build_object(m, sid::text); end if;
    end loop;
  end loop;
  update public.uno_rot set cfg = jsonb_set(cfg, '{map}', mp) where id = 1;
end $$;
select public.uno_rot_automap();

-- smena kuni: tun yarmidan keyin 06:00 gacha — oldingi kun (14:00–02:00 smena = 1 kun)
create or replace function public.uno_rot_today() returns date language sql stable as $$
  select ((now() at time zone public.uno_tz()) - interval '6 hours')::date;
$$;

-- p_final=false: asosiy reja (hamma keladi deb); true: davomat bo'yicha qayta taqsimlangan
create or replace function public.uno_rot_plan(p_day date, p_final boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; tz text := public.uno_tz(); g jsonb; gi int := 0; d int; n int; k int; zone text; slots jsonb; mem jsonb;
        out_groups jsonb := '[]'::jsonb; rows jsonb; i int; j int; who int; nm text; sid text; pres boolean[]; unm boolean[];
        h_m int[]; h_t int[]; l_m int[]; l_t text[]; e_m int[]; e_t text[]; ab_t int[]; ab_l text[]; slot text; tok text;
        best_d int; best_c int; best_m int; best_i int; dd int; cnt int; x int; t int; any_num boolean; ext text; mine text;
        st0 timestamptz; st1 timestamptz;
begin
  select cfg into c from public.uno_rot where id = 1; if c is null then return null; end if;
  d := p_day - (c->>'anchor')::date;
  st0 := (p_day + time '06:00') at time zone tz; st1 := (p_day + 1 + time '06:00') at time zone tz;
  for g in select * from jsonb_array_elements(c->'groups') loop
    mem := g->'members'; n := jsonb_array_length(mem);
    zone := case when ((d % 2 + 2) % 2 = 0) = (gi = coalesce((c->>'biznes_first')::int,0)) then 'Biznes' else 'Comfort' end;
    slots := g->'zones'->zone; k := ((d % n) + n) % n;
    pres := '{}'; unm := '{}';
    for j in 0..n-1 loop
      sid := c->'map'->>(mem->>j);
      unm := unm || (sid is null);
      pres := pres || (not p_final or sid is null or exists (select 1 from public.uno_att a where a.staff_id = sid::uuid and a.kind = 'in' and a.at >= st0 and a.at < st1));
    end loop;
    -- asosiy taqsimot: i-slot → (i-k) mod n-a'zo
    h_m := '{}'; h_t := '{}'; l_m := '{}'; l_t := '{}'; e_m := '{}'; e_t := '{}'; ab_t := '{}'; ab_l := '{}';
    for i in 0..n-1 loop
      who := ((i - k) % n + n) % n; slot := slots->>i;
      if slot ~ '[[:alpha:]]' then
        if pres[who+1] then l_m := l_m || who; l_t := l_t || slot; else ab_l := ab_l || slot; end if;
      else
        foreach tok in array string_to_array(slot, ',') loop
          t := nullif(trim(tok),'')::int; if t is null then continue; end if;
          if pres[who+1] then h_m := h_m || who; h_t := h_t || t; else ab_t := ab_t || t; end if;
        end loop;
      end if;
    end loop;
    -- kelmaganlarning raqamli stollari: eng yaqin (qo'shni) stol egasiga, teng bo'lsa kamroq stollisiga
    while coalesce(array_length(ab_t,1),0) > 0 loop
      best_d := null; best_m := null; best_i := null; best_c := null;
      for i in 1..array_length(ab_t,1) loop
        for j in 0..n-1 loop
          if not pres[j+1] then continue; end if;
          dd := null;
          for x in 1..coalesce(array_length(h_m,1),0) loop if h_m[x] = j then dd := least(coalesce(dd, 99999), abs(h_t[x] - ab_t[i])); end if; end loop;
          if dd is null then continue; end if;
          cnt := 0; for x in 1..coalesce(array_length(h_m,1),0) loop if h_m[x] = j then cnt := cnt + 1; end if; end loop;
          for x in 1..coalesce(array_length(l_m,1),0) loop if l_m[x] = j then cnt := cnt + 1; end if; end loop;
          if best_d is null or dd < best_d or (dd = best_d and cnt < best_c) then best_d := dd; best_c := cnt; best_m := j; best_i := i; end if;
        end loop;
      end loop;
      if best_m is null then exit; end if;
      h_m := h_m || best_m; h_t := h_t || ab_t[best_i]; e_m := e_m || best_m; e_t := e_t || ab_t[best_i]::text;
      ab_t := ab_t[1:best_i-1] || ab_t[best_i+1:];
    end loop;
    -- Balkon / Family / Konferensiya-VIP: eng kam stolli kelgan ofitsiantga
    for i in 1..coalesce(array_length(ab_l,1),0) loop
      best_m := null; best_c := null;
      for j in 0..n-1 loop
        if not pres[j+1] then continue; end if;
        cnt := 0; for x in 1..coalesce(array_length(h_m,1),0) loop if h_m[x] = j then cnt := cnt + 1; end if; end loop;
        for x in 1..coalesce(array_length(l_m,1),0) loop if l_m[x] = j then cnt := cnt + 1; end if; end loop;
        if best_c is null or cnt < best_c then best_c := cnt; best_m := j; end if;
      end loop;
      if best_m is not null then l_m := l_m || best_m; l_t := l_t || ab_l[i]; e_m := e_m || best_m; e_t := e_t || ab_l[i]; end if;
    end loop;
    rows := '[]'::jsonb;
    for i in 0..n-1 loop
      who := ((i - k) % n + n) % n; nm := mem->>who;
      ext := null; for x in 1..coalesce(array_length(e_m,1),0) loop if e_m[x] = who then ext := coalesce(ext || ',', '') || e_t[x]; end if; end loop;
      rows := rows || jsonb_build_object('name', nm, 'staff_id', c->'map'->>nm, 'base', slots->>i, 'present', pres[who+1], 'unmapped', unm[who+1], 'extra', ext);
    end loop;
    out_groups := out_groups || jsonb_build_object('group', g->>'name', 'zone', zone, 'kun', k + 1, 'days', n, 'rows', rows,
      'left', (select coalesce(string_agg(v::text, ','), '') from unnest(ab_t) v) || case when coalesce(array_length(ab_l,1),0) > 0 and not exists(select 1 from unnest(pres) p where p) then ',' || array_to_string(ab_l, ',') else '' end);
    gi := gi + 1;
  end loop;
  return jsonb_build_object('day', p_day, 'final', p_final, 'groups', out_groups);
end $$;
revoke all on function public.uno_rot_plan(date, boolean) from public, anon, authenticated;

create or replace function public.uno_rot_text(p jsonb) returns text language plpgsql immutable as $$
declare g jsonb; r jsonb; txt text;
begin
  txt := '🔄 <b>Rotatsiya — ' || to_char((p->>'day')::date, 'DD.MM.YYYY') || '</b>' || case when (p->>'final')::boolean then ' (davomat bo''yicha)' else ' (asosiy reja)' end;
  for g in select * from jsonb_array_elements(p->'groups') loop
    txt := txt || E'\n\n<b>' || uno_esc2(g->>'group') || ' · ' || (g->>'zone') || ' · ' || (g->>'kun') || '-kun</b>';
    for r in select * from jsonb_array_elements(g->'rows') loop
      if (r->>'present')::boolean then
        txt := txt || E'\n' || uno_esc2(r->>'name') || ' — ' || uno_esc2(r->>'base') || case when coalesce(r->>'extra','') <> '' then ' <b>+ ' || uno_esc2(r->>'extra') || '</b>' else '' end;
      else
        txt := txt || E'\n❌ <s>' || uno_esc2(r->>'name') || '</s> — kelmadi (' || uno_esc2(r->>'base') || ')';
      end if;
    end loop;
    if coalesce(g->>'left','') <> '' then txt := txt || E'\n⚠️ Taqsimlanmadi: ' || uno_esc2(g->>'left'); end if;
  end loop;
  return txt;
end $$;

-- har 5 daqiqada: 18:00 dan keyin bugungi yakuniy taqsimotni bir marta tuzib, Telegramga yuboradi
create or replace function public.uno_rot_run() returns void language plpgsql security definer set search_path = public as $$
declare dday date := public.uno_rot_today(); loc timestamp := now() at time zone public.uno_tz(); p jsonb;
begin
  if not exists (select 1 from public.uno_rot) then return; end if;
  if loc < dday + time '18:00' then return; end if;
  if exists (select 1 from public.uno_rot_day where day = dday) then return; end if;
  p := public.uno_rot_plan(dday, true);
  insert into public.uno_rot_day(day, plan, sent) values (dday, p, true) on conflict (day) do nothing;
  begin perform public.uno_att_tg(public.uno_rot_text(p)); exception when others then null; end;
end $$;
revoke all on function public.uno_rot_run() from public, anon, authenticated;

-- admin: ko'rish (saqlangan yakuniy yoki hozirgi holat), qayta taqsimlash, sozlamalar
create or replace function public.uno_rot_get(p_day date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dday date := coalesce(p_day, public.uno_rot_today()); p jsonb; saved jsonb;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  select plan into saved from public.uno_rot_day where day = dday;
  if saved is not null then return saved || jsonb_build_object('saved', true); end if;
  p := public.uno_rot_plan(dday, dday <= public.uno_rot_today());
  return p || jsonb_build_object('saved', false, 'live', dday = public.uno_rot_today());
end $$;
revoke all on function public.uno_rot_get(date) from public, anon;
grant execute on function public.uno_rot_get(date) to authenticated;

create or replace function public.uno_rot_redo(p_send boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dday date := public.uno_rot_today(); p jsonb;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  p := public.uno_rot_plan(dday, true);
  insert into public.uno_rot_day(day, plan, sent) values (dday, p, p_send) on conflict (day) do update set plan = excluded.plan, made_at = now(), sent = excluded.sent or public.uno_rot_day.sent;
  if p_send then begin perform public.uno_att_tg(public.uno_rot_text(p)); exception when others then null; end; end if;
  return p || jsonb_build_object('saved', true);
end $$;
revoke all on function public.uno_rot_redo(boolean) from public, anon;
grant execute on function public.uno_rot_redo(boolean) to authenticated;

create or replace function public.uno_rot_cfg() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  perform public.uno_rot_automap();
  return (select cfg from public.uno_rot where id = 1);
end $$;
revoke all on function public.uno_rot_cfg() from public, anon;
grant execute on function public.uno_rot_cfg() to authenticated;

create or replace function public.uno_rot_set(p_cfg jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  if jsonb_typeof(p_cfg->'groups') <> 'array' or (p_cfg->>'anchor') is null then raise exception 'bad_cfg'; end if;
  insert into public.uno_rot(id, cfg, updated_at) values (1, p_cfg, now()) on conflict (id) do update set cfg = excluded.cfg, updated_at = now();
  delete from public.uno_rot_day where day >= public.uno_rot_today() and not sent;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.uno_rot_set(jsonb) from public, anon;
grant execute on function public.uno_rot_set(jsonb) to authenticated;

-- terminal uchun: shu xodimning bugungi hududi va stollari
create or replace function public.uno_rot_for(p_staff uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare dday date := public.uno_rot_today(); p jsonb; g jsonb; r jsonb;
begin
  select plan into p from public.uno_rot_day where day = dday;
  if p is null then p := public.uno_rot_plan(dday, false); end if;
  if p is null then return null; end if;
  for g in select * from jsonb_array_elements(p->'groups') loop
    for r in select * from jsonb_array_elements(g->'rows') loop
      if r->>'staff_id' = p_staff::text then
        return (g->>'zone') || ' · stollar: ' || (r->>'base') || coalesce(' + ' || (r->>'extra'), '');
      end if;
    end loop;
  end loop;
  return null;
end $$;
revoke all on function public.uno_rot_for(uuid) from public, anon, authenticated;

do $$
begin
  begin perform cron.unschedule('uno-rot'); exception when others then null; end;
  perform cron.schedule('uno-rot', '*/5 * * * *', 'select public.uno_rot_run()');
exception when others then raise notice 'cron: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

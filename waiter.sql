-- UNO Airways: ofitsiant ilovasi — PIN bilan kirish va rotatsiya bo'yicha stollarni avtomatik biriktirish
-- Ofitsiant Davomat PIN-kodi bilan kiradi. Ilova bugungi rotatsiyadan uning hududi va stollarini o'zi oladi:
-- o'z stollaridan kelgan chaqiruvlar faqat unda jiringlaydi; hech kimga biriktirilmagan stollar chaqiruvi hammaga boradi.
-- Kerak: attendance.sql, rotation.sql, calls.sql. Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.

create table if not exists public.uno_waiter_sessions (
  token      text primary key,
  staff_id   uuid not null references public.uno_staff(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create table if not exists public.uno_waiter_fail (at timestamptz not null default now());
alter table public.uno_waiter_sessions enable row level security;
alter table public.uno_waiter_fail enable row level security;
revoke all on public.uno_waiter_sessions from anon, authenticated;
revoke all on public.uno_waiter_fail from anon, authenticated;

-- hudud nomlarini bir xil ko'rinishga keltirish: BUSINESS / Biznes → biznes, COMFORT / Komfort → comfort, …
create or replace function public.uno_zone_key(s text) returns text language sql immutable as $$
  select case
    when z like 'biz%' or z like 'bus%' then 'biznes'
    when z like 'kom%' or z like 'com%' then 'comfort'
    when z like 'fam%' then 'family'
    when z like 'bal%' then 'balkon'
    when z like 'vip%' then 'vip'
    when z like 'kon%' or z like 'conf%' then 'konf'
    else z end
  from (select lower(regexp_replace(coalesce(s,''), '[^[:alpha:]]', '', 'g')) as z) q
$$;

-- shu chaqiruv (stol) shu ofitsiantnikimi: p_zone — rotatsiyadagi hududi (Biznes/Comfort), p_tables — "1,2,3" yoki "Balkon" yoki "Konferensiya, VIP 1 va VIP 2"
create or replace function public.uno_tbl_match(p_table_no text, p_zone text, p_tables text) returns boolean
language plpgsql immutable as $$
declare cz text := public.uno_zone_key(regexp_replace(coalesce(p_table_no,''), '[0-9]', '', 'g'));
        num int := nullif(substring(coalesce(p_table_no,'') from '([0-9]+)'), '')::int;
        wz text := public.uno_zone_key(p_zone); lab text := lower(coalesce(p_tables,'')); nums int[] := '{}'; tok text;
begin
  if coalesce(p_tables,'') = '' then return false; end if;
  foreach tok in array string_to_array(p_tables, ',') loop
    if trim(tok) <> '' and trim(tok) !~ '[^0-9]' and length(trim(tok)) <= 4 then nums := nums || trim(tok)::int; end if;
  end loop;
  if cz in ('biznes','comfort') then return cz = wz and num = any(nums); end if;
  if cz = '' then return num is not null and num = any(nums); end if;          -- QR-kod: faqat raqam (hudud yo'q)
  if cz = 'family' then return lab like '%famil%'; end if;
  if cz = 'balkon' then return lab like '%balk%' or lab like '%balc%'; end if;
  if cz = 'konf'   then return lab like '%konf%' or lab like '%conf%'; end if;
  if cz = 'vip' then
    if lab not like '%vip%' then return false; end if;
    if num is null or lab !~ 'vip\s*[0-9]' then return true; end if;            -- "VIP" (raqamsiz) — butun VIP hududi
    return (lab || ' ') ~ ('vip\s*' || num || '[^0-9]');   -- " " at the end instead of an end-of-text sign (the Supabase editor misreads it)
  end if;
  return false;
end $$;

-- bugungi biriktirish: 18:00 dan keyin saqlangan yakuniy (davomat bo'yicha) reja, undan oldin asosiy reja
create or replace function public.uno_waiter_assign() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dday date := public.uno_rot_today(); p jsonb; g jsonb; r jsonb; out jsonb := '[]'::jsonb;
begin
  select plan into p from public.uno_rot_day where day = dday;
  if p is null then p := public.uno_rot_plan(dday, false); end if;
  if p is null then return out; end if;
  for g in select * from jsonb_array_elements(p->'groups') loop
    for r in select * from jsonb_array_elements(g->'rows') loop
      out := out || jsonb_build_object('staff_id', r->>'staff_id', 'name', r->>'name', 'zone', g->>'zone', 'group', g->>'group',
        'present', coalesce((r->>'present')::boolean, true),
        'tables', case when coalesce((r->>'present')::boolean, true) then coalesce(r->>'tables', r->>'base') end,
        'final', coalesce((p->>'final')::boolean, false));
    end loop;
  end loop;
  return out;
end $$;
revoke all on function public.uno_waiter_assign() from public, anon, authenticated;

-- shu stol bugun kimniki (ismlar) — Telegram xabari uchun
create or replace function public.uno_call_owner_names(p_table_no text) returns text
language sql stable security definer set search_path = public as $$
  select string_agg(a->>'name', ', ')
  from jsonb_array_elements(public.uno_waiter_assign()) a
  where public.uno_tbl_match(p_table_no, a->>'zone', a->>'tables')
$$;
revoke all on function public.uno_call_owner_names(text) from public, anon, authenticated;

-- kirish: Davomat PIN-kodi (10 daqiqada 20 marta xato bo'lsa vaqtincha yopiladi)
create or replace function public.uno_waiter_login(p_pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.uno_staff; tok text;
begin
  if (select count(*) from public.uno_waiter_fail where at > now() - interval '10 minutes') >= 20 then
    return jsonb_build_object('ok', false, 'err', 'locked');
  end if;
  select * into s from public.uno_staff where pin = trim(coalesce(p_pin,'')) and active limit 1;
  if s.id is null then
    insert into public.uno_waiter_fail default values;
    delete from public.uno_waiter_fail where at < now() - interval '1 day';
    return jsonb_build_object('ok', false, 'err', 'bad_pin');
  end if;
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.uno_waiter_sessions(token, staff_id) values (tok, s.id);
  delete from public.uno_waiter_sessions where last_seen < now() - interval '60 days';
  return jsonb_build_object('ok', true, 'token', tok, 'name', s.name);
end $$;
revoke all on function public.uno_waiter_login(text) from public;
grant execute on function public.uno_waiter_login(text) to anon, authenticated;

-- admin ofitsiant telefonini aniq xodimga bog'laydi (admin panel → Stollar va QR): ofitsiant PIN terishi shart emas
create or replace function public.uno_waiter_bind(p_staff uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.uno_staff; tok text;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  select * into s from public.uno_staff where id = p_staff and active;
  if s.id is null then raise exception 'no_staff'; end if;
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.uno_waiter_sessions(token, staff_id) values (tok, s.id);
  return jsonb_build_object('ok', true, 'token', tok, 'name', s.name);
end $$;
revoke all on function public.uno_waiter_bind(uuid) from public, anon;
grant execute on function public.uno_waiter_bind(uuid) to authenticated;

create or replace function public.uno_waiter_logout(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.uno_waiter_sessions where token = p_token;
$$;
revoke all on function public.uno_waiter_logout(text) from public;
grant execute on function public.uno_waiter_logout(text) to anon, authenticated;

-- ilova shu bilan ishlaydi: kimligim, bugungi stollarim va oxirgi 12 soatdagi chaqiruvlar (mine = meniki, common = hech kimniki emas)
create or replace function public.uno_waiter_calls(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.uno_staff; asg jsonb; me jsonb; c record; a jsonb; owners text[]; mine boolean; calls jsonb := '[]'::jsonb;
begin
  select st.* into s from public.uno_waiter_sessions ws join public.uno_staff st on st.id = ws.staff_id
   where ws.token = p_token and st.active;
  if s.id is null then return jsonb_build_object('ok', false, 'err', 'logged_out'); end if;
  update public.uno_waiter_sessions set last_seen = now() where token = p_token and last_seen < now() - interval '1 minute';
  asg := public.uno_waiter_assign();
  select x into me from jsonb_array_elements(asg) x where x->>'staff_id' = s.id::text limit 1;
  for c in select * from public.uno_calls where created_at > now() - interval '12 hours' order by created_at desc limit 100 loop
    owners := '{}'; mine := false;
    for a in select * from jsonb_array_elements(asg) loop
      if public.uno_tbl_match(c.table_no, a->>'zone', a->>'tables') then
        owners := owners || (a->>'name');
        if a->>'staff_id' = s.id::text then mine := true; end if;
      end if;
    end loop;
    calls := calls || jsonb_build_object('id', c.id, 'table_no', c.table_no, 'kind', c.kind, 'total', c.total, 'items', c.items,
      'status', c.status, 'accepted_by', c.accepted_by, 'created_at', c.created_at, 'accepted_at', c.accepted_at,
      'mine', mine, 'common', coalesce(array_length(owners, 1), 0) = 0, 'owners', to_jsonb(owners));
  end loop;
  return jsonb_build_object('ok', true, 'name', s.name, 'day', public.uno_rot_today(), 'now', now(),
    'me', coalesce(me, jsonb_build_object('unmapped', true)), 'calls', calls);
end $$;
revoke all on function public.uno_waiter_calls(text) from public;
grant execute on function public.uno_waiter_calls(text) to anon, authenticated;

-- qabul qilish: ism xodimlar ro'yxatidan olinadi
create or replace function public.uno_waiter_accept(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.uno_staff; n int;
begin
  select st.* into s from public.uno_waiter_sessions ws join public.uno_staff st on st.id = ws.staff_id where ws.token = p_token and st.active;
  if s.id is null then return jsonb_build_object('ok', false, 'err', 'logged_out'); end if;
  update public.uno_calls set status = 'accepted', accepted_by = left(s.name, 40), accepted_at = now() where id = p_id and status = 'new';
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'accepted', n > 0);
end $$;
revoke all on function public.uno_waiter_accept(text, bigint) from public;
grant execute on function public.uno_waiter_accept(text, bigint) to anon, authenticated;

-- Telegram xabarida stol kimga biriktirilgani ham ko'rinadi: "🔔 Biznes 5-stol — ofitsiant chaqiryapti · 👤 Asadbek"
create or replace function public.uno_calls_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare txt text; it jsonb; site text := coalesce(public.uno_priv('site_url'), 'https://spesmuz.github.io/uno-menu/'); who text;
begin
  if new.kind = 'bill' then
    txt := '🧾 <b>' || uno_tg_esc(new.table_no) || '-stol</b> — hisob so''rayapti';
    if new.items is not null and jsonb_typeof(new.items) = 'array' then
      txt := txt || E'\n';
      for it in select * from jsonb_array_elements(new.items) loop
        txt := txt || E'\n• ' || uno_tg_esc(it->>'n') || ' × ' || coalesce(it->>'q','1');
      end loop;
    end if;
    if new.total is not null then txt := txt || E'\n\n<b>Jami (xizmat haqi bilan): ' || uno_money(new.total) || '</b>'; end if;
  else
    txt := '🔔 <b>' || uno_tg_esc(new.table_no) || '-stol</b> — ofitsiant chaqiryapti';
  end if;
  if to_regproc('public.uno_call_owner_names') is not null then   -- waiter.sql o'rnatilgan bo'lsa: stol kimga biriktirilgani
    begin who := public.uno_call_owner_names(new.table_no); exception when others then who := null; end;
    txt := txt || E'\n👤 ' || case when coalesce(who,'') <> '' then uno_tg_esc(who) else 'biriktirilmagan stol — kim bo''sh bo''lsa' end;
  end if;
  perform public.uno_tg_send(txt, jsonb_build_object('inline_keyboard',
    jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '✅ Qabul qildim', 'url', site || 'ofitsiant.html?accept=' || new.id)))));
  return null;
end $$;

notify pgrst, 'reload schema';

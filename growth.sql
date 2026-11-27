-- UNO Airways: bonus (keshbek), tug'ilgan kun, do'st taklifi, tashrifdan keyingi fikr, taom statistikasi
-- Supabase → SQL Editor → shu faylni to'liq joylab → Run. Qayta ishga tushirish xavfsiz.
-- (setup.sql, telegram.sql va customers.sql oldin ishga tushirilgan bo'lishi kerak)

-- telefon raqamning oxirgi 9 raqami: +998 91 881 69 79 → 918816979
create or replace function public.uno_ph9(p text) returns text language sql immutable as $$
  select right(regexp_replace(coalesce(p,''),'[^0-9]','','g'), 9)
$$;

-- admin paneldagi sozlama (settings/main → grow) dan butun son: bonus foizi, taklif bonusi
create or replace function public.uno_cfg_int(k text, def int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(regexp_replace(coalesce((select data->'grow'->>k from public.uno_docs where path = 'settings/main'), ''), '[^0-9]', '', 'g'), '')::int, def)
$$;

-- ---------- mijoz: tug'ilgan kun va kim taklif qilgani ----------
alter table public.uno_customers add column if not exists birthday date;
alter table public.uno_customers add column if not exists ref_by   text;   -- taklif qilgan do'stning raqami (oxirgi 9 raqam)

-- ---------- tug'ilgan kun: bir marta kiritiladi, keyin faqat admin o'zgartiradi ----------
-- Sana telefon raqamga bog'lanadi: ilovani qayta o'rnatib yoki boshqa telefondan o'sha raqam bilan kirib, sanani almashtirib bo'lmaydi.
alter table public.uno_customers add column if not exists birthday_at timestamptz;   -- sana birinchi marta qachon kiritilgan
update public.uno_customers set birthday_at = coalesce(updated_at, now()) where birthday is not null and birthday_at is null;

-- shu qurilma yoki shu raqam bo'yicha avval kiritilgan (qulflangan) sana
create or replace function public.uno_bday_locked(p_device text) returns date
language sql stable security definer set search_path = public as $$
  with me as (select public.uno_ph9(phone) as ph from public.uno_customers where device = btrim(coalesce(p_device,'')))
  select c.birthday from public.uno_customers c, me
   where c.birthday is not null and (c.device = btrim(coalesce(p_device,'')) or (length(me.ph) = 9 and public.uno_ph9(c.phone) = me.ph))
   order by c.birthday_at nulls last, c.updated_at limit 1
$$;
revoke all on function public.uno_bday_locked(text) from public, anon, authenticated;

create or replace function public.uno_customer_extra(p_device text, p_birthday date default null, p_ref text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare dev text := btrim(coalesce(p_device,'')); c record; me text; r text := public.uno_ph9(p_ref); locked date;
begin
  select * into c from public.uno_customers where device = dev;
  if not found then raise exception 'no_profile'; end if;
  me := public.uno_ph9(c.phone);
  if p_birthday is not null and (p_birthday < date '1920-01-01' or p_birthday > current_date) then raise exception 'bad_birthday'; end if;
  locked := public.uno_bday_locked(dev);
  if p_birthday is not null and locked is not null and p_birthday <> locked then raise exception 'bday_locked'; end if;
  if length(r) = 9 then
    if r = me then raise exception 'self_ref'; end if;
    if c.ref_by is null and not exists (select 1 from public.uno_customers where public.uno_ph9(phone) = r) then raise exception 'bad_ref'; end if;
  end if;
  update public.uno_customers set
    birthday    = coalesce(locked, p_birthday, birthday),
    birthday_at = case when birthday_at is null and coalesce(locked, p_birthday) is not null then now() else birthday_at end,
    ref_by      = case when ref_by is null and length(r) = 9 then r else ref_by end,
    updated_at  = now()
  where device = dev;
  return jsonb_build_object('ok', true, 'birthday', coalesce(locked, p_birthday, c.birthday));
end $$;
revoke all on function public.uno_customer_extra(text,date,text) from public;
grant execute on function public.uno_customer_extra(text,date,text) to anon, authenticated;

-- ilova o'z mehmonining qulflangan sanasini oladi (qayta o'rnatilganda ham tiklanadi)
create or replace function public.uno_my_birthday(p_device text) returns text
language sql stable security definer set search_path = public as $$
  select to_char(public.uno_bday_locked(p_device), 'YYYY-MM-DD')
$$;
revoke all on function public.uno_my_birthday(text) from public;
grant execute on function public.uno_my_birthday(text) to anon, authenticated;

-- admin: pasportni ko'rib sanani tuzatadi yoki o'chiradi (bo'sh = o'chirish, mehmon qayta kirita oladi)
create or replace function public.uno_admin_set_birthday(p_phone text, p_birthday date) returns int
language plpgsql security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); n int;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  if length(ph) <> 9 then raise exception 'bad_phone'; end if;
  if p_birthday is not null and (p_birthday < date '1920-01-01' or p_birthday > current_date) then raise exception 'bad_birthday'; end if;
  update public.uno_customers set birthday = p_birthday, birthday_at = case when p_birthday is null then null else now() end, updated_at = now()
   where public.uno_ph9(phone) = ph;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.uno_admin_set_birthday(text,date) from public, anon;
grant execute on function public.uno_admin_set_birthday(text,date) to authenticated;

-- ---------- bonus ----------
create table if not exists public.uno_bonus (
  phone      text primary key,                         -- oxirgi 9 raqam
  balance    int  not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.uno_bonus_tx (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  phone      text not null,
  amount     int  not null,                            -- + yig'ildi, − ishlatildi
  check_sum  int,                                      -- chek summasi (yig'ilganda)
  kind       text not null,                            -- earn / spend / ref
  note       text
);
create index if not exists uno_bonus_tx_phone on public.uno_bonus_tx(phone, created_at desc);
alter table public.uno_bonus    enable row level security;
alter table public.uno_bonus_tx enable row level security;
revoke all on public.uno_bonus, public.uno_bonus_tx from anon, authenticated;
drop policy if exists uno_bonus_admin on public.uno_bonus;
create policy uno_bonus_admin on public.uno_bonus for select using (public.uno_is_admin());
drop policy if exists uno_bonus_tx_admin on public.uno_bonus_tx;
create policy uno_bonus_tx_admin on public.uno_bonus_tx for select using (public.uno_is_admin());
grant select on public.uno_bonus, public.uno_bonus_tx to authenticated;

-- ---------- UNO Miles: darajalar (tashriflar soniga qarab) ----------
-- Economy: boshlang'ich; Business: tierB marta kelgandan keyin; First Class: tierF marta. Har darajaning o'z bonus foizi.
create or replace function public.uno_miles_visits(ph text) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.uno_bonus_tx where phone = ph and kind = 'earn'
$$;
create or replace function public.uno_miles_tier(v int) returns text language sql stable security definer set search_path = public as $$
  select case when v >= public.uno_cfg_int('tierF', 15) then 'first' when v >= public.uno_cfg_int('tierB', 5) then 'business' else 'economy' end
$$;
create or replace function public.uno_miles_pct(t text) returns int language sql stable security definer set search_path = public as $$
  select least(greatest(case t when 'first' then public.uno_cfg_int('pctF', 10) when 'business' then public.uno_cfg_int('pctB', 7) else public.uno_cfg_int('bonusPct', 5) end, 0), 50)
$$;

-- mehmon o'z balansini ko'radi: faqat shu qurilmaning profilidagi raqam bo'yicha
create or replace function public.uno_bonus_me(p_device text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ph text; bal int; tx jsonb;
begin
  select public.uno_ph9(phone) into ph from public.uno_customers where device = btrim(coalesce(p_device,''));
  if ph is null or length(ph) <> 9 then return jsonb_build_object('balance', 0, 'tx', '[]'::jsonb, 'pct', public.uno_cfg_int('bonusPct', 5)); end if;
  select balance into bal from public.uno_bonus where phone = ph;
  select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'amount', amount, 'kind', kind) order by created_at desc), '[]'::jsonb) into tx
    from (select created_at, amount, kind from public.uno_bonus_tx where phone = ph order by created_at desc limit 10) t;
  return jsonb_build_object('balance', coalesce(bal, 0), 'tx', tx, 'pct', public.uno_miles_pct(public.uno_miles_tier(public.uno_miles_visits(ph))),
    'ref', public.uno_cfg_int('refBonus', 20000), 'visits', public.uno_miles_visits(ph), 'tier', public.uno_miles_tier(public.uno_miles_visits(ph)),
    'tierB', public.uno_cfg_int('tierB', 5), 'tierF', public.uno_cfg_int('tierF', 15),
    'pctE', public.uno_miles_pct('economy'), 'pctB', public.uno_miles_pct('business'), 'pctF', public.uno_miles_pct('first'));
end $$;
revoke all on function public.uno_bonus_me(text) from public;
grant execute on function public.uno_bonus_me(text) to anon, authenticated;

-- ichki: chekdan bonus (admin yoki kassir chaqiradi)
create or replace function public.uno_bonus_earn_core(p_phone text, p_sum int, p_note text, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); v int; tier text; pct int; amt int; rb text; rbonus int := 0; bal int; tier2 text;
begin
  if length(ph) <> 9 then raise exception 'bad_phone'; end if;
  if p_sum is null or p_sum <= 0 or p_sum > 100000000 then raise exception 'bad_sum'; end if;
  v := public.uno_miles_visits(ph); tier := public.uno_miles_tier(v); pct := public.uno_miles_pct(tier);
  amt := floor(p_sum * pct / 100.0);
  insert into public.uno_bonus as b (phone, balance) values (ph, amt)
    on conflict (phone) do update set balance = b.balance + amt, updated_at = now()
    returning balance into bal;
  insert into public.uno_bonus_tx (phone, amount, check_sum, kind, note) values (ph, amt, p_sum, 'earn', left(coalesce(p_by || ': ', '') || coalesce(p_note, ''), 200));
  if v = 0 then
    select ref_by into rb from public.uno_customers where public.uno_ph9(phone) = ph and ref_by is not null order by created_at limit 1;
    if rb is not null and rb <> ph then
      rbonus := public.uno_cfg_int('refBonus', 20000);
      if rbonus > 0 then
        insert into public.uno_bonus as b (phone, balance) values (rb, rbonus)
          on conflict (phone) do update set balance = b.balance + rbonus, updated_at = now();
        insert into public.uno_bonus_tx (phone, amount, kind, note) values (rb, rbonus, 'ref', 'Taklif: ' || ph);
      end if;
    end if;
  end if;
  tier2 := public.uno_miles_tier(v + 1);
  return jsonb_build_object('amount', amt, 'balance', bal, 'pct', pct, 'tier', tier2, 'up', tier2 <> tier, 'visits', v + 1, 'ref', rb, 'ref_bonus', rbonus);
end $$;
revoke all on function public.uno_bonus_earn_core(text,int,text,text) from public, anon, authenticated;

create or replace function public.uno_bonus_spend_core(p_phone text, p_amount int, p_note text, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); bal int;
begin
  if length(ph) <> 9 then raise exception 'bad_phone'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'bad_sum'; end if;
  update public.uno_bonus set balance = balance - p_amount, updated_at = now() where phone = ph and balance >= p_amount returning balance into bal;
  if not found then raise exception 'not_enough'; end if;
  insert into public.uno_bonus_tx (phone, amount, kind, note) values (ph, -p_amount, 'spend', left(coalesce(p_by || ': ', '') || coalesce(p_note, ''), 200));
  return jsonb_build_object('balance', bal);
end $$;
revoke all on function public.uno_bonus_spend_core(text,int,text,text) from public, anon, authenticated;

create or replace function public.uno_bonus_info(p_phone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); bal int; v int; tx jsonb;
begin
  select balance into bal from public.uno_bonus where phone = ph;
  v := public.uno_miles_visits(ph);
  select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'amount', amount, 'kind', kind, 'check_sum', check_sum) order by created_at desc), '[]'::jsonb) into tx
    from (select * from public.uno_bonus_tx where phone = ph order by created_at desc limit 10) t;
  return jsonb_build_object('phone', ph, 'balance', coalesce(bal, 0), 'visits', v, 'tier', public.uno_miles_tier(v), 'tx', tx);
end $$;
revoke all on function public.uno_bonus_info(text) from public, anon, authenticated;

-- admin paneldan
create or replace function public.uno_bonus_earn(p_phone text, p_sum int, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin if not public.uno_is_admin() then raise exception 'forbidden'; end if; return public.uno_bonus_earn_core(p_phone, p_sum, p_note, 'admin'); end $$;
revoke all on function public.uno_bonus_earn(text,int,text) from public;
grant execute on function public.uno_bonus_earn(text,int,text) to authenticated;

create or replace function public.uno_bonus_spend(p_phone text, p_amount int, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin if not public.uno_is_admin() then raise exception 'forbidden'; end if; return public.uno_bonus_spend_core(p_phone, p_amount, p_note, 'admin'); end $$;
revoke all on function public.uno_bonus_spend(text,int,text) from public;
grant execute on function public.uno_bonus_spend(text,int,text) to authenticated;

-- ---------- tashrifdan keyingi fikr ----------
create table if not exists public.uno_feedback (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  device     text,
  name       text,
  phone      text,
  booking_id bigint,
  stars      int not null check (stars between 1 and 5),
  comment    text
);
alter table public.uno_feedback enable row level security;
revoke all on public.uno_feedback from anon, authenticated;
drop policy if exists uno_feedback_admin on public.uno_feedback;
create policy uno_feedback_admin on public.uno_feedback for all using (public.uno_is_admin()) with check (public.uno_is_admin());
grant select, delete on public.uno_feedback to authenticated;

create or replace function public.uno_feedback_add(p_device text, p_stars int, p_comment text default null,
                                                   p_name text default null, p_phone text default null, p_booking bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare dev text := left(btrim(coalesce(p_device,'')), 80); cm text := left(btrim(coalesce(p_comment,'')), 800); fid bigint;
begin
  if length(dev) < 8 then raise exception 'bad device'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'bad stars'; end if;
  if (select count(*) from public.uno_feedback where device = dev and created_at > now() - interval '1 day') >= 5 then raise exception 'too_many'; end if;
  insert into public.uno_feedback (device, name, phone, booking_id, stars, comment)
    values (dev, left(p_name, 80), left(p_phone, 30), p_booking, p_stars, nullif(cm, ''))
    returning id into fid;
  -- past baho yoki izoh bo'lsa — darhol Telegram guruhga
  if p_stars <= 3 or cm <> '' then
    perform public.uno_tg_send(
      (case when p_stars <= 3 then '⚠️ ' else '💬 ' end) || '<b>Mehmon fikri</b> ' || repeat('⭐', p_stars) || ' (' || p_stars || '/5)' ||
      coalesce(chr(10) || '👤 ' || nullif(public.uno_tg_esc(p_name), ''), '') ||
      coalesce(chr(10) || '📞 ' || nullif(public.uno_tg_esc(p_phone), ''), '') ||
      coalesce(chr(10) || '📅 Bron #' || p_booking, '') ||
      coalesce(chr(10) || '💬 ' || nullif(public.uno_tg_esc(cm), ''), ''));
  end if;
  return jsonb_build_object('id', fid);
end $$;
revoke all on function public.uno_feedback_add(text,int,text,text,text,bigint) from public;
grant execute on function public.uno_feedback_add(text,int,text,text,text,bigint) to anon, authenticated;

-- ---------- taom statistikasi: qaysi taom ko'p ko'riladi / ochiladi ----------
create table if not exists public.uno_stats (
  day   date not null,
  dish  text not null,
  views int  not null default 0,     -- menyuda o'rtada 2 soniyadan ko'p turdi
  opens int  not null default 0,     -- batafsil ochildi
  primary key (day, dish)
);
alter table public.uno_stats enable row level security;
revoke all on public.uno_stats from anon, authenticated;
drop policy if exists uno_stats_admin on public.uno_stats;
create policy uno_stats_admin on public.uno_stats for select using (public.uno_is_admin());
grant select on public.uno_stats to authenticated;

create or replace function public.uno_stat_add(p_counts jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; n int := 0; d date := (now() at time zone 'Asia/Tashkent')::date; vv int; oo int;
begin
  if p_counts is null or jsonb_typeof(p_counts) <> 'object' then return; end if;
  for k, v in select * from jsonb_each(p_counts) loop
    n := n + 1; exit when n > 60;
    if length(k) between 1 and 80 then
      vv := least(greatest(coalesce((v->>'v')::int, 0), 0), 30);
      oo := least(greatest(coalesce((v->>'o')::int, 0), 0), 10);
      if vv + oo > 0 then
        insert into public.uno_stats as s (day, dish, views, opens) values (d, k, vv, oo)
          on conflict (day, dish) do update set views = s.views + vv, opens = s.opens + oo;
      end if;
    end if;
  end loop;
end $$;
revoke all on function public.uno_stat_add(jsonb) from public;
grant execute on function public.uno_stat_add(jsonb) to anon, authenticated;

-- ---------- sovg'a sertifikati ("Boarding Pass") ----------
create table if not exists public.uno_gifts (
  code       text primary key,                     -- UNO-XXXX-XXXX
  amount     int  not null check (amount > 0),
  balance    int  not null check (balance >= 0),
  name       text,                                 -- kimga
  phone      text,
  note       text,
  expires    date,
  created_at timestamptz not null default now()
);
create table if not exists public.uno_gift_tx (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  code       text not null,
  amount     int  not null,
  by_who     text
);
alter table public.uno_gifts   enable row level security;
alter table public.uno_gift_tx enable row level security;
revoke all on public.uno_gifts, public.uno_gift_tx from anon, authenticated;
drop policy if exists uno_gifts_admin on public.uno_gifts;
create policy uno_gifts_admin on public.uno_gifts for select using (public.uno_is_admin());
drop policy if exists uno_gift_tx_admin on public.uno_gift_tx;
create policy uno_gift_tx_admin on public.uno_gift_tx for select using (public.uno_is_admin());
grant select on public.uno_gifts, public.uno_gift_tx to authenticated;

create or replace function public.uno_gift_norm(c text) returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(c,''), '[^A-Za-z0-9]', '', 'g'))
$$;

create or replace function public.uno_gift_create(p_amount int, p_name text default null, p_phone text default null, p_note text default null, p_months int default 12)
returns jsonb language plpgsql security definer set search_path = public as $$
declare al text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; c text; i int; tries int := 0;
begin
  if not public.uno_is_admin() then raise exception 'forbidden'; end if;
  if p_amount is null or p_amount < 1000 or p_amount > 100000000 then raise exception 'bad_sum'; end if;
  loop
    c := 'UNO';
    for i in 1..8 loop c := c || substr(al, 1 + floor(random() * length(al))::int, 1); end loop;
    exit when not exists (select 1 from public.uno_gifts where code = c);
    tries := tries + 1; if tries > 20 then raise exception 'retry'; end if;
  end loop;
  insert into public.uno_gifts (code, amount, balance, name, phone, note, expires)
    values (c, p_amount, p_amount, left(p_name, 80), left(p_phone, 30), left(p_note, 200), current_date + make_interval(months => greatest(coalesce(p_months, 12), 1)));
  return jsonb_build_object('code', c, 'amount', p_amount, 'expires', current_date + make_interval(months => greatest(coalesce(p_months, 12), 1)));
end $$;
revoke all on function public.uno_gift_create(int,text,text,text,int) from public;
grant execute on function public.uno_gift_create(int,text,text,text,int) to authenticated;

-- har kim kod bo'yicha qoldiqni ko'ra oladi (kodni bilish = sertifikat egasi)
create or replace function public.uno_gift_check(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g record;
begin
  select * into g from public.uno_gifts where code = public.uno_gift_norm(p_code);
  if not found then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'code', g.code, 'amount', g.amount, 'balance', g.balance, 'name', g.name, 'expires', g.expires, 'expired', g.expires < current_date);
end $$;
revoke all on function public.uno_gift_check(text) from public;
grant execute on function public.uno_gift_check(text) to anon, authenticated;

create or replace function public.uno_gift_redeem_core(p_code text, p_amount int, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c text := public.uno_gift_norm(p_code); bal int; ex date;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'bad_sum'; end if;
  select expires into ex from public.uno_gifts where code = c;
  if not found then raise exception 'no_gift'; end if;
  if ex < current_date then raise exception 'expired'; end if;
  update public.uno_gifts set balance = balance - p_amount where code = c and balance >= p_amount returning balance into bal;
  if not found then raise exception 'not_enough'; end if;
  insert into public.uno_gift_tx (code, amount, by_who) values (c, -p_amount, p_by);
  return jsonb_build_object('balance', bal);
end $$;
revoke all on function public.uno_gift_redeem_core(text,int,text) from public, anon, authenticated;

create or replace function public.uno_gift_redeem(p_code text, p_amount int)
returns jsonb language plpgsql security definer set search_path = public as $$
begin if not public.uno_is_admin() then raise exception 'forbidden'; end if; return public.uno_gift_redeem_core(p_code, p_amount, 'admin'); end $$;
revoke all on function public.uno_gift_redeem(text,int) from public;
grant execute on function public.uno_gift_redeem(text,int) to authenticated;

-- ---------- kassa: kassir PIN-kod bilan kiradi (faqat bonus va sertifikat) ----------
create table if not exists public.uno_cashier_fails (at timestamptz not null default now());
alter table public.uno_cashier_fails enable row level security;
revoke all on public.uno_cashier_fails from anon, authenticated;

create or replace function public.uno_cashier_set_pin(p_pin text)
returns void language plpgsql security definer set search_path = public as $$
declare salt text := md5(random()::text || clock_timestamp()::text);
begin
  if not public.uno_is_admin() then raise exception 'forbidden'; end if;
  if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then raise exception 'bad_pin'; end if;
  insert into public.uno_private(key, value) values ('cashier_pin', salt || ':' || encode(sha256(convert_to(salt || p_pin, 'UTF8')), 'hex'))
    on conflict (key) do update set value = excluded.value;
end $$;
revoke all on function public.uno_cashier_set_pin(text) from public;
grant execute on function public.uno_cashier_set_pin(text) to authenticated;

create or replace function public.uno_cashier_has_pin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.uno_priv('cashier_pin'), '') <> ''
$$;
grant execute on function public.uno_cashier_has_pin() to anon, authenticated;

-- PIN tekshiruvi: 10 daqiqada 8 marta xato bo'lsa, kassa vaqtincha yopiladi
create or replace function public.uno_cashier_ok(p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := public.uno_priv('cashier_pin'); salt text; h text;
begin
  if coalesce(v, '') = '' then raise exception 'no_pin'; end if;
  if (select count(*) from public.uno_cashier_fails where at > now() - interval '10 minutes') >= 8 then raise exception 'locked'; end if;
  salt := split_part(v, ':', 1); h := split_part(v, ':', 2);
  if encode(sha256(convert_to(salt || coalesce(p_pin, ''), 'UTF8')), 'hex') <> h then
    insert into public.uno_cashier_fails default values;
    raise exception 'bad_pin';
  end if;
end $$;
revoke all on function public.uno_cashier_ok(text) from public, anon, authenticated;

create or replace function public.uno_kassa(p_pin text, p_action text, p_phone text default null, p_sum int default null, p_code text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.uno_cashier_ok(p_pin);
  delete from public.uno_cashier_fails where at < now() - interval '1 day';
  if p_action = 'login'   then return jsonb_build_object('ok', true); end if;
  if p_action = 'info'    then return public.uno_bonus_info(p_phone); end if;
  if p_action = 'earn'    then return public.uno_bonus_earn_core(p_phone, p_sum, null, 'kassa'); end if;
  if p_action = 'spend'   then return public.uno_bonus_spend_core(p_phone, p_sum, null, 'kassa'); end if;
  if p_action = 'gift'    then return public.uno_gift_check(p_code); end if;
  if p_action = 'redeem'  then return public.uno_gift_redeem_core(p_code, p_sum, 'kassa'); end if;
  raise exception 'bad_action';
end $$;
revoke all on function public.uno_kassa(text,text,text,int,text) from public;
grant execute on function public.uno_kassa(text,text,text,int,text) to anon, authenticated;

-- admin uchun ham mehmon balansi (darajasi bilan)
create or replace function public.uno_bonus_admin_info(p_phone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin if not public.uno_is_admin() then raise exception 'forbidden'; end if; return public.uno_bonus_info(p_phone); end $$;
revoke all on function public.uno_bonus_admin_info(text) from public;
grant execute on function public.uno_bonus_admin_info(text) to authenticated;

-- ---------- bron manbasi uzunroq bo'lishi uchun (masalan: "Sayt (telefon) · instagram") ----------
create or replace function public.uno_booking_create(
  p_name text, p_phone text, p_at timestamptz, p_guests int,
  p_zone text default null, p_occasion text default null, p_note text default null, p_source text default 'ios')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  nm text := left(trim(coalesce(p_name,'')), 80);
  ph text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  bid bigint; txt text;
begin
  if length(nm) < 2 then raise exception 'bad_name'; end if;
  if length(regexp_replace(ph,'[^0-9]','','g')) < 9 then raise exception 'bad_phone'; end if;
  if p_at is null or p_at < now() - interval '10 minutes' or p_at > now() + interval '400 days' then raise exception 'bad_time'; end if;
  if p_guests is null or p_guests < 1 or p_guests > 350 then raise exception 'bad_guests'; end if;
  if (select count(*) from public.uno_bookings where phone = ph and created_at > now() - interval '10 minutes') >= 3 then raise exception 'too_many'; end if;
  if (select count(*) from public.uno_bookings where created_at > now() - interval '1 minute') >= 20 then raise exception 'too_many'; end if;

  insert into public.uno_bookings(name, phone, at, guests, zone, occasion, note, source)
  values (nm, ph, p_at, p_guests, left(p_zone,40), left(p_occasion,40), left(trim(coalesce(p_note,'')),1500), left(coalesce(p_source,'ios'),50))
  returning id into bid;

  txt := '📅 <b>Yangi bron #' || bid || '</b>' || chr(10) ||
         '👤 ' || public.uno_tg_esc(nm) || chr(10) ||
         '📞 ' || public.uno_tg_esc(ph) || chr(10) ||
         '🕒 ' || to_char(p_at at time zone 'Asia/Tashkent', 'DD.MM.YYYY HH24:MI') || chr(10) ||
         '👥 ' || p_guests || ' kishi' ||
         coalesce(chr(10) || '🏷 ' || nullif(public.uno_tg_esc(p_zone),''), '') ||
         coalesce(chr(10) || '🎉 ' || nullif(public.uno_tg_esc(p_occasion),''), '') ||
         coalesce(chr(10) || '💬 ' || nullif(public.uno_tg_esc(trim(p_note)),''), '') ||
         chr(10) || '📱 ' || case when p_source = 'ios' then 'iPhone ilovasi' else public.uno_tg_esc(p_source) end;
  perform public.uno_tg_send(txt);
  return jsonb_build_object('id', bid);
end $$;
revoke all on function public.uno_booking_create(text,text,timestamptz,int,text,text,text,text) from public;
grant execute on function public.uno_booking_create(text,text,timestamptz,int,text,text,text,text) to anon, authenticated;

-- ---------- haftalik hisobot: har dushanba 09:00 (Toshkent) Telegram guruhga ----------
create or replace function public.uno_weekly_report() returns text
language plpgsql security definer set search_path = public as $$
declare t text; n int; g int; a numeric; s1 int; s2 int; r record; since timestamptz := now() - interval '7 days'; part text;
begin
  t := '📊 <b>UNO Airways — haftalik hisobot</b>' || chr(10) || to_char((now() - interval '7 days') at time zone 'Asia/Tashkent', 'DD.MM') || ' — ' || to_char(now() at time zone 'Asia/Tashkent', 'DD.MM.YYYY') || chr(10);
  begin
    select count(*), coalesce(sum(guests),0) into n, g from public.uno_bookings where created_at > since and coalesce(note,'') not like '💍 BANKET%';
    t := t || chr(10) || '📅 Stol bronlari: <b>' || n || '</b> (' || g || ' mehmon)';
    select count(*) into n from public.uno_bookings where created_at > since and coalesce(note,'') like '💍 BANKET%';
    t := t || chr(10) || '💍 To''y / banket arizalari: <b>' || n || '</b>';
  exception when others then null; end;
  begin
    select count(*), coalesce(sum(total),0) into n, a from public.uno_orders where created_at > since and status <> 'cancelled';
    t := t || chr(10) || '🛵 Yetkazib berish: <b>' || n || '</b> ta, ' || public.uno_money(a);
  exception when others then null; end;
  begin
    select count(*), avg(stars) into n, a from public.uno_feedback where created_at > since;
    t := t || chr(10) || '⭐ Mehmon fikrlari: <b>' || n || '</b>' || case when n > 0 then ', o''rtacha <b>' || round(a, 1) || '</b>' else '' end;
    select count(*) into n from public.uno_feedback where created_at > since and stars <= 3;
    if n > 0 then t := t || ' (past baho: ' || n || ')'; end if;
  exception when others then null; end;
  begin
    select coalesce(sum(amount) filter (where kind = 'earn'),0), coalesce(-sum(amount) filter (where kind = 'spend'),0) into s1, s2 from public.uno_bonus_tx where created_at > since;
    select count(*) into n from public.uno_bonus_tx where created_at > since and kind = 'earn';
    t := t || chr(10) || '💳 Bonus: ' || n || ' ta tashrif, yozildi ' || public.uno_money(s1) || ', ishlatildi ' || public.uno_money(s2);
  exception when others then null; end;
  begin
    select count(*) into n from public.uno_customers where created_at > since;
    t := t || chr(10) || '👤 Yangi mijozlar (ilova): <b>' || n || '</b>';
  exception when others then null; end;
  begin
    part := '';
    for r in select coalesce(d.data->>'name', s.dish) as nm, sum(s.views) as v from public.uno_stats s left join public.uno_docs d on d.path = 'dishes/' || s.dish
             where s.day > (now() at time zone 'Asia/Tashkent')::date - 7 and s.dish not like 'src:%' group by 1 order by 2 desc limit 5 loop
      part := part || chr(10) || '   • ' || public.uno_tg_esc(r.nm) || ' — ' || r.v;
    end loop;
    if part <> '' then t := t || chr(10) || chr(10) || '🔥 Eng ko''p ko''rilgan taomlar:' || part; end if;
    part := '';
    for r in select substr(dish, 5) as src, sum(views) as v from public.uno_stats where day > (now() at time zone 'Asia/Tashkent')::date - 7 and dish like 'src:%' group by 1 order by 2 desc limit 6 loop
      part := part || chr(10) || '   • ' || public.uno_tg_esc(r.src) || ' — ' || r.v;
    end loop;
    if part <> '' then t := t || chr(10) || chr(10) || '🧭 Mehmonlar qayerdan kirdi:' || part; end if;
  exception when others then null; end;
  perform public.uno_tg_send(t);
  return t;
end $$;
revoke all on function public.uno_weekly_report() from public, anon, authenticated;

create or replace function public.uno_weekly_report_now() returns text
language plpgsql security definer set search_path = public as $$
begin if not public.uno_is_admin() then raise exception 'forbidden'; end if; return public.uno_weekly_report(); end $$;
revoke all on function public.uno_weekly_report_now() from public;
grant execute on function public.uno_weekly_report_now() to authenticated;

do $$
begin
  begin create extension if not exists pg_cron; exception when others then raise notice 'pg_cron yoqilmadi: %', sqlerrm; return; end;
  begin perform cron.unschedule('uno-weekly'); exception when others then null; end;
  perform cron.schedule('uno-weekly', '0 4 * * 1', 'select public.uno_weekly_report()');   -- 04:00 UTC = 09:00 Toshkent, dushanba
exception when others then raise notice 'cron: %', sqlerrm;
end $$;

-- ---------- Telegram Mini App: botdagi "Menyu" tugmasi saytni ilova kabi ochadi ----------
create or replace function public.uno_tg_miniapp_setup()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare tok text := public.uno_priv('tg_token'); site text := coalesce(nullif(public.uno_priv('site_url'),''), 'https://spesmuz.github.io/uno-menu/'); u text;
begin
  if not public.uno_is_admin() then raise exception 'forbidden'; end if;
  if coalesce(tok,'') = '' then raise exception 'no_bot'; end if;
  u := site || case when position('?' in site) > 0 then '&' else '?' end || 'src=telegram';
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/setChatMenuButton',
    body := jsonb_build_object('menu_button', jsonb_build_object('type','web_app','text','🍽 Menyu','web_app', jsonb_build_object('url', u))),
    headers := '{"Content-Type":"application/json"}'::jsonb);
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/setMyShortDescription',
    body := jsonb_build_object('short_description', 'UNO Airways Restaurante — menyu, stol bron qilish, bonuslar. Farg''ona, S. Temur 30'),
    headers := '{"Content-Type":"application/json"}'::jsonb);
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/setMyDescription',
    body := jsonb_build_object('description', '✈️ UNO Airways Restaurante — turk va yevropa oshxonasi, har kuni jonli musiqa.' || chr(10) || chr(10) || 'Pastdagi «🍽 Menyu» tugmasini bosing: menyu, stol bron qilish, to''y/banket arizasi va bonuslaringiz.' || chr(10) || '📞 +998 91 881 69 79'),
    headers := '{"Content-Type":"application/json"}'::jsonb);
  return jsonb_build_object('ok', true, 'url', u);
end $$;
revoke all on function public.uno_tg_miniapp_setup() from public;
grant execute on function public.uno_tg_miniapp_setup() to authenticated;

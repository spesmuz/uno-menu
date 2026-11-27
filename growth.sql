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

create or replace function public.uno_customer_extra(p_device text, p_birthday date default null, p_ref text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare dev text := btrim(coalesce(p_device,'')); c record; me text; r text := public.uno_ph9(p_ref);
begin
  select * into c from public.uno_customers where device = dev;
  if not found then raise exception 'no_profile'; end if;
  me := public.uno_ph9(c.phone);
  if p_birthday is not null and (p_birthday < date '1920-01-01' or p_birthday > current_date) then raise exception 'bad_birthday'; end if;
  if length(r) = 9 then
    if r = me then raise exception 'self_ref'; end if;
    if c.ref_by is null and not exists (select 1 from public.uno_customers where public.uno_ph9(phone) = r) then raise exception 'bad_ref'; end if;
  end if;
  update public.uno_customers set
    birthday   = coalesce(p_birthday, birthday),
    ref_by     = case when ref_by is null and length(r) = 9 then r else ref_by end,
    updated_at = now()
  where device = dev;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.uno_customer_extra(text,date,text) from public;
grant execute on function public.uno_customer_extra(text,date,text) to anon, authenticated;

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
  return jsonb_build_object('balance', coalesce(bal, 0), 'tx', tx, 'pct', public.uno_cfg_int('bonusPct', 5), 'ref', public.uno_cfg_int('refBonus', 20000));
end $$;
revoke all on function public.uno_bonus_me(text) from public;
grant execute on function public.uno_bonus_me(text) to anon, authenticated;

-- admin (kassa): chek summasidan bonus yozadi; mehmonning birinchi bonusida uni taklif qilgan do'stga ham bonus
create or replace function public.uno_bonus_earn(p_phone text, p_sum int, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); pct int; amt int; first boolean; rb text; rbonus int := 0; bal int;
begin
  if not public.uno_is_admin() then raise exception 'forbidden'; end if;
  if length(ph) <> 9 then raise exception 'bad_phone'; end if;
  if p_sum is null or p_sum <= 0 or p_sum > 100000000 then raise exception 'bad_sum'; end if;
  pct := least(greatest(public.uno_cfg_int('bonusPct', 5), 0), 50);
  amt := floor(p_sum * pct / 100.0);
  first := not exists (select 1 from public.uno_bonus_tx where phone = ph and kind = 'earn');
  insert into public.uno_bonus as b (phone, balance) values (ph, amt)
    on conflict (phone) do update set balance = b.balance + amt, updated_at = now()
    returning balance into bal;
  insert into public.uno_bonus_tx (phone, amount, check_sum, kind, note) values (ph, amt, p_sum, 'earn', left(p_note, 200));
  if first then
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
  return jsonb_build_object('amount', amt, 'balance', bal, 'pct', pct, 'ref', rb, 'ref_bonus', rbonus);
end $$;
revoke all on function public.uno_bonus_earn(text,int,text) from public;
grant execute on function public.uno_bonus_earn(text,int,text) to authenticated;

-- admin (kassa): bonusdan to'lash
create or replace function public.uno_bonus_spend(p_phone text, p_amount int, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ph text := public.uno_ph9(p_phone); bal int;
begin
  if not public.uno_is_admin() then raise exception 'forbidden'; end if;
  if length(ph) <> 9 then raise exception 'bad_phone'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'bad_sum'; end if;
  update public.uno_bonus set balance = balance - p_amount, updated_at = now() where phone = ph and balance >= p_amount returning balance into bal;
  if not found then raise exception 'not_enough'; end if;
  insert into public.uno_bonus_tx (phone, amount, kind, note) values (ph, -p_amount, 'spend', left(p_note, 200));
  return jsonb_build_object('balance', bal);
end $$;
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

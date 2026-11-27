-- UNO Airways: tug'ilgan kun sanasini qulflash (growth.sql dagi bilan bir xil; faqat shu qismni yangilash uchun)
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.

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

-- ---------- tug'ilgan kun sovg'asi: quti faqat tug'ilgan kuni ochiladi (sana serverda, Toshkent vaqti bilan tekshiriladi) ----------
create or replace function public.uno_bday_gift(p_device text, p_lang text default 'uz') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b date := public.uno_bday_locked(p_device); g jsonb; today date := (now() at time zone 'Asia/Tashkent')::date;
        y int; nxt date; tx text; l text := lower(coalesce(p_lang,'uz'));
begin
  select data->'grow' into g from public.uno_docs where path = 'settings/main';
  if coalesce((g->>'bdayOn')::boolean, false) is not true then return jsonb_build_object('on', false); end if;
  if b is null then return jsonb_build_object('on', true, 'has', false); end if;
  y := extract(year from today)::int;
  -- 29-fevral: kabisa bo'lmagan yili 28-fevralda ochiladi
  nxt := make_date(y, extract(month from b)::int, least(extract(day from b)::int, extract(day from (make_date(y, extract(month from b)::int, 1) + interval '1 month - 1 day'))::int));
  if nxt < today then
    y := y + 1;
    nxt := make_date(y, extract(month from b)::int, least(extract(day from b)::int, extract(day from (make_date(y, extract(month from b)::int, 1) + interval '1 month - 1 day'))::int));
  end if;
  if nxt = today then
    tx := coalesce(nullif(case when l in ('ru','en') then g->>('bdayText_' || l) end, ''), nullif(g->>'bdayText', ''), '');
    return jsonb_build_object('on', true, 'has', true, 'open', true, 'days', 0, 'birthday', b, 'today', today, 'text', tx,
      'name', (select name from public.uno_customers where device = btrim(coalesce(p_device,''))));
  end if;
  return jsonb_build_object('on', true, 'has', true, 'open', false, 'days', nxt - today, 'birthday', b, 'today', today);
end $$;
revoke all on function public.uno_bday_gift(text,text) from public;
grant execute on function public.uno_bday_gift(text,text) to anon, authenticated;

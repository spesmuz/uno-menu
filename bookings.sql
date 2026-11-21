-- UNO Airways: iPhone ilovasidan stol bron qilish → Telegram guruhga xabar
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.
-- (setup.sql va telegram.sql oldin ishga tushirilgan bo'lishi kerak)

create table if not exists public.uno_bookings (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null,
  phone       text not null,
  at          timestamptz not null,
  guests      int  not null,
  zone        text,
  occasion    text,
  note        text,
  source      text not null default 'ios',
  status      text not null default 'new'      -- new / confirmed / cancelled
);
create index if not exists uno_bookings_at on public.uno_bookings(at);
alter table public.uno_bookings enable row level security;
revoke all on public.uno_bookings from anon, authenticated;

drop policy if exists uno_bookings_admin on public.uno_bookings;
create policy uno_bookings_admin on public.uno_bookings for all
  using (public.uno_is_admin()) with check (public.uno_is_admin());
grant select, update, delete on public.uno_bookings to authenticated;

-- mijoz (ilova) bron yuboradi: tekshiradi, saqlaydi, Telegram'ga yuboradi
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
  if p_at is null or p_at < now() - interval '10 minutes' or p_at > now() + interval '180 days' then raise exception 'bad_time'; end if;
  if p_guests is null or p_guests < 1 or p_guests > 350 then raise exception 'bad_guests'; end if;
  -- bitta raqamdan ketma-ket ko'p bron bo'lmasin
  if (select count(*) from public.uno_bookings where phone = ph and created_at > now() - interval '10 minutes') >= 3 then
    raise exception 'too_many';
  end if;
  if (select count(*) from public.uno_bookings where created_at > now() - interval '1 minute') >= 20 then
    raise exception 'too_many';
  end if;

  insert into public.uno_bookings(name, phone, at, guests, zone, occasion, note, source)
  values (nm, ph, p_at, p_guests, left(p_zone,40), left(p_occasion,40), left(trim(coalesce(p_note,'')),500), left(coalesce(p_source,'ios'),20))
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

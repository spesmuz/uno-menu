-- UNO Airways: yetkazib berish buyurtmalari → Telegram guruhga
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.
-- (setup.sql va telegram.sql oldin ishga tushirilgan bo'lishi kerak)

create table if not exists public.uno_orders (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null,
  phone       text not null,
  address     text not null,
  lat         double precision,
  lng         double precision,
  note        text,
  pay         text not null default 'cash',      -- cash / card
  items       jsonb not null,                     -- [{id,name,price,qty}]
  subtotal    bigint not null,
  fee         bigint not null default 0,
  total       bigint not null,
  lang        text,
  source      text not null default 'web',
  status      text not null default 'new'         -- new / accepted / onway / done / cancelled
);
create index if not exists uno_orders_created on public.uno_orders(created_at desc);
alter table public.uno_orders enable row level security;
revoke all on public.uno_orders from anon, authenticated;
drop policy if exists uno_orders_admin on public.uno_orders;
create policy uno_orders_admin on public.uno_orders for all
  using (public.uno_is_admin()) with check (public.uno_is_admin());
grant select, update, delete on public.uno_orders to authenticated;

-- mijoz buyurtma beradi. Narxlar bazadagi menyudan olinadi (telefondan kelgan narxga ishonilmaydi).
create or replace function public.uno_order_create(
  p_name text, p_phone text, p_address text, p_items jsonb,
  p_lat double precision default null, p_lng double precision default null,
  p_note text default null, p_pay text default 'cash', p_lang text default null, p_source text default 'web')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st jsonb; dl jsonb; fee bigint; minsum bigint;
  nm text := left(trim(coalesce(p_name,'')), 80);
  ph text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  ad text := left(trim(coalesce(p_address,'')), 300);
  it jsonb; d jsonb; q int; price bigint; sub bigint := 0; lines jsonb := '[]'::jsonb; txt text := ''; oid bigint; tot bigint; maplink text := '';
begin
  select data into st from public.uno_docs where path = 'settings/main';
  dl := coalesce(st->'delivery', '{}'::jsonb);
  if coalesce((dl->>'on')::boolean, false) is not true then raise exception 'delivery_off'; end if;
  fee := greatest(0, coalesce((dl->>'fee')::bigint, 0));
  minsum := greatest(0, coalesce((dl->>'min')::bigint, 0));
  if length(nm) < 2 then raise exception 'bad_name'; end if;
  if length(regexp_replace(ph,'[^0-9]','','g')) < 9 then raise exception 'bad_phone'; end if;
  if length(ad) < 5 and p_lat is null then raise exception 'bad_address'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 60 then raise exception 'bad_items'; end if;
  if (select count(*) from public.uno_orders where phone = ph and created_at > now() - interval '10 minutes') >= 3
     or (select count(*) from public.uno_orders where created_at > now() - interval '1 minute') >= 20 then
    raise exception 'too_many';
  end if;

  for it in select * from jsonb_array_elements(p_items) loop
    q := least(99, greatest(0, coalesce((it->>'qty')::int, 0)));
    if q = 0 then continue; end if;
    select data into d from public.uno_docs where path = 'dishes/' || (it->>'id');
    if d is null then continue; end if;
    price := greatest(0, coalesce(round((d->>'price')::numeric)::bigint, 0));
    sub := sub + price * q;
    lines := lines || jsonb_build_array(jsonb_build_object('id', it->>'id', 'name', d->>'name', 'price', price, 'qty', q));
    txt := txt || chr(10) || '• ' || public.uno_tg_esc(d->>'name') || ' × ' || q || ' — ' || to_char(price*q, 'FM999G999G999') || ' so''m';
  end loop;
  if jsonb_array_length(lines) = 0 then raise exception 'bad_items'; end if;
  if sub < minsum then raise exception 'min_sum:%', minsum; end if;
  tot := sub + fee;

  insert into public.uno_orders(name, phone, address, lat, lng, note, pay, items, subtotal, fee, total, lang, source)
  values (nm, ph, ad, p_lat, p_lng, left(trim(coalesce(p_note,'')),500), case when p_pay='card' then 'card' else 'cash' end,
          lines, sub, fee, tot, left(p_lang,5), left(coalesce(p_source,'web'),20))
  returning id into oid;

  if p_lat is not null and p_lng is not null then
    maplink := chr(10) || '🗺 <a href="https://maps.google.com/?q=' || p_lat || ',' || p_lng || '">Xaritada ochish</a>';
  end if;
  begin
    perform public.uno_tg_send(
      '🛵 <b>Yetkazib berish #' || oid || '</b>' || chr(10) ||
      '👤 ' || public.uno_tg_esc(nm) || chr(10) ||
      '📞 ' || public.uno_tg_esc(ph) || chr(10) ||
      '📍 ' || public.uno_tg_esc(coalesce(nullif(ad,''),'—')) || maplink ||
      coalesce(chr(10) || '💬 ' || nullif(public.uno_tg_esc(trim(coalesce(p_note,''))),''), '') ||
      chr(10) || txt || chr(10) ||
      chr(10) || 'Taomlar: ' || to_char(sub, 'FM999G999G999') || ' so''m' ||
      case when fee > 0 then chr(10) || 'Yetkazish: ' || to_char(fee, 'FM999G999G999') || ' so''m' else '' end ||
      chr(10) || '<b>Jami: ' || to_char(tot, 'FM999G999G999') || ' so''m</b>' ||
      chr(10) || '💳 ' || case when p_pay='card' then 'Karta (kuryerga)' else 'Naqd' end);
  exception when others then null;
  end;
  return jsonb_build_object('id', oid, 'subtotal', sub, 'fee', fee, 'total', tot);
end $$;
revoke all on function public.uno_order_create(text,text,text,jsonb,double precision,double precision,text,text,text,text) from public;
grant execute on function public.uno_order_create(text,text,text,jsonb,double precision,double precision,text,text,text,text) to anon, authenticated;

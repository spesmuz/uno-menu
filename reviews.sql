-- UNO Airways: taomlarni yulduzcha bilan baholash va izoh qoldirish
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.
-- (setup.sql va telegram.sql oldin ishga tushirilgan bo'lishi kerak)

create table if not exists public.uno_reviews (
  id          bigint generated always as identity primary key,
  dish_id     text not null,
  device      text not null,                 -- mijoz telefonining tasodifiy belgisi (bitta telefon = bitta baho)
  stars       int  not null check (stars between 1 and 5),
  name        text,
  comment     text,
  lang        text,
  hidden      boolean not null default false, -- admin yashirgan izoh (baho ham hisobga olinmaydi)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (dish_id, device)
);
create index if not exists uno_reviews_dish on public.uno_reviews(dish_id, created_at desc);
alter table public.uno_reviews enable row level security;
revoke all on public.uno_reviews from anon, authenticated;

drop policy if exists uno_reviews_admin on public.uno_reviews;
create policy uno_reviews_admin on public.uno_reviews for all
  using (public.uno_is_admin()) with check (public.uno_is_admin());
grant select, update, delete on public.uno_reviews to authenticated;

-- barcha taomlarning o'rtacha bahosi (menyu ochilganda bir marta olinadi)
create or replace function public.uno_ratings()
returns table(dish_id text, avg numeric, cnt int)
language sql stable security definer set search_path = public as $$
  select r.dish_id, round(avg(r.stars)::numeric, 1), count(*)::int
  from public.uno_reviews r where not r.hidden group by r.dish_id;
$$;
grant execute on function public.uno_ratings() to anon, authenticated;

-- bitta taomning izohlari (yangilari birinchi); p_device — "sizning bahoingiz"ni ko'rsatish uchun
create or replace function public.uno_reviews_for(p_dish text, p_device text default null, p_limit int default 20, p_before bigint default null)
returns table(id bigint, stars int, name text, comment text, created_at timestamptz, mine boolean)
language sql stable security definer set search_path = public as $$
  (select r.id, r.stars, r.name, r.comment, r.created_at, true
     from public.uno_reviews r where r.dish_id = p_dish and r.device = p_device and p_device is not null and p_before is null)
  union all
  (select r.id, r.stars, r.name, r.comment, r.created_at, false
     from public.uno_reviews r
    where r.dish_id = p_dish and not r.hidden and coalesce(r.comment,'') <> ''
      and (p_device is null or r.device <> p_device)
      and (p_before is null or r.id < p_before)
    order by r.id desc limit least(greatest(coalesce(p_limit,20),1),50));
$$;
grant execute on function public.uno_reviews_for(text,text,int,bigint) to anon, authenticated;

-- mijoz baho qo'yadi yoki o'zgartiradi (bitta telefon — bitta taomga bitta baho)
create or replace function public.uno_review_add(p_dish text, p_device text, p_stars int, p_name text default null, p_comment text default null, p_lang text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  dv text := left(coalesce(p_device,''), 64);
  nm text := nullif(left(trim(regexp_replace(coalesce(p_name,''), '\s+', ' ', 'g')), 40), '');
  cm text := nullif(left(trim(coalesce(p_comment,'')), 500), '');
  dish_name text; old_c text; isnew boolean; a numeric; c int; txt text;
begin
  if length(dv) < 8 then raise exception 'bad_device'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'bad_stars'; end if;
  select d.data->>'name' into dish_name from public.uno_docs d where d.path = 'dishes/' || p_dish;
  if dish_name is null then raise exception 'bad_dish'; end if;
  -- spamdan himoya: bitta telefon 1 daqiqada 10 tadan ko'p, hammasi 1 daqiqada 60 tadan ko'p yozolmaydi
  if (select count(*) from public.uno_reviews where device = dv and updated_at > now() - interval '1 minute') >= 10
     or (select count(*) from public.uno_reviews where updated_at > now() - interval '1 minute') >= 60 then
    raise exception 'too_many';
  end if;

  select comment into old_c from public.uno_reviews where dish_id = p_dish and device = dv;
  isnew := not found;
  insert into public.uno_reviews(dish_id, device, stars, name, comment, lang)
  values (p_dish, dv, p_stars, nm, cm, left(p_lang,5))
  on conflict (dish_id, device) do update
    set stars = excluded.stars, name = excluded.name, comment = excluded.comment, lang = excluded.lang, updated_at = now();

  select round(avg(stars)::numeric,1), count(*)::int into a, c from public.uno_reviews where dish_id = p_dish and not hidden;

  -- yangi izoh yoki past baho bo'lsa — Telegram guruhga
  if (cm is not null and cm is distinct from old_c) or (isnew and p_stars <= 3) then
    begin
      txt := '⭐ <b>Taomga baho</b>: ' || public.uno_tg_esc(dish_name) || chr(10) ||
             repeat('★', p_stars) || repeat('☆', 5 - p_stars) || '  (' || p_stars || '/5)' ||
             coalesce(chr(10) || '👤 ' || public.uno_tg_esc(nm), '') ||
             coalesce(chr(10) || '💬 ' || public.uno_tg_esc(cm), '') ||
             chr(10) || '📊 O''rtacha: ' || a || ' (' || c || ' ta baho)';
      perform public.uno_tg_send(txt);
    exception when others then null;   -- Telegram sozlanmagan bo'lsa ham baho saqlanadi
    end;
  end if;
  return jsonb_build_object('avg', a, 'cnt', c);
end $$;
revoke all on function public.uno_review_add(text,text,int,text,text,text) from public;
grant execute on function public.uno_review_add(text,text,int,text,text,text) to anon, authenticated;

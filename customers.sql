-- UNO Airways: guests' profiles (name, phone, photo) from the iPhone app's "Profil" tab.
-- Run once in Supabase → SQL Editor. Safe to run again.

create table if not exists public.uno_customers (
  device     text primary key,
  name       text not null default '',
  phone      text not null default '',
  photo      text,                        -- small JPEG as data:image/jpeg;base64,…
  platform   text not null default 'ios',
  lang       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.uno_customers enable row level security;
drop policy if exists uno_customers_admin on public.uno_customers;
create policy uno_customers_admin on public.uno_customers for all
  using (public.uno_is_admin()) with check (public.uno_is_admin());
grant select, update, delete on public.uno_customers to authenticated;

-- the app saves its own profile; p_photo: null = keep the current photo, '' = remove it
create or replace function public.uno_customer_save(p_device text, p_name text, p_phone text, p_photo text default null,
                                                    p_platform text default 'ios', p_lang text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare dev text := btrim(coalesce(p_device,'')); nm text := left(btrim(coalesce(p_name,'')),80); ph text := left(btrim(coalesce(p_phone,'')),30);
begin
  if length(dev) < 8 or length(dev) > 80 then raise exception 'bad device'; end if;
  if p_photo is not null and p_photo <> '' and (left(p_photo,11) <> 'data:image/' or length(p_photo) > 400000) then raise exception 'bad photo'; end if;
  insert into public.uno_customers as c (device, name, phone, photo, platform, lang)
    values (dev, nm, ph, nullif(p_photo,''), left(coalesce(p_platform,'ios'),20), left(p_lang,5))
  on conflict (device) do update set
    name = excluded.name, phone = excluded.phone,
    photo = case when p_photo is null then c.photo else nullif(p_photo,'') end,
    platform = excluded.platform, lang = coalesce(excluded.lang, c.lang), updated_at = now();
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.uno_customer_save(text,text,text,text,text,text) to anon, authenticated;

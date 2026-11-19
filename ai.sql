-- UNO Airways: sun'iy intellekt (Gemini) kaliti
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.

create table if not exists public.uno_private (key text primary key, value text);
alter table public.uno_private enable row level security;
revoke all on public.uno_private from anon, authenticated;

-- admin kalitni saqlaydi
create or replace function public.uno_set_ai_key(p_key text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_private(key, value) values ('ai_key', trim(p_key))
  on conflict (key) do update set value = excluded.value;
end $$;

-- faqat admin kalitni ola oladi (admin brauzeri AI'ga shu kalit bilan murojaat qiladi)
create or replace function public.uno_get_ai_key() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return (select value from public.uno_private where key = 'ai_key');
end $$;

-- kalit kiritilganmi (kalitning o'zi qaytarilmaydi)
create or replace function public.uno_ai_status() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return coalesce((select value from public.uno_private where key = 'ai_key'), '') <> '';
end $$;

revoke all on function public.uno_set_ai_key(text) from public, anon;
revoke all on function public.uno_get_ai_key() from public, anon;
revoke all on function public.uno_ai_status() from public, anon;
grant execute on function public.uno_set_ai_key(text) to authenticated;
grant execute on function public.uno_get_ai_key() to authenticated;
grant execute on function public.uno_ai_status() to authenticated;

notify pgrst, 'reload schema';

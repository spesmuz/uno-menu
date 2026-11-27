-- UNO Airways: taom saqlanganda videolarni darhol avtomatik tuzatish
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.
-- GitHub kaliti (token) faqat admin paneldan kiritiladi va hech qachon qaytarib berilmaydi.

create extension if not exists pg_net;
create table if not exists public.uno_private (key text primary key, value text);
alter table public.uno_private enable row level security;
revoke all on public.uno_private from anon, authenticated;

-- admin GitHub kalitini saqlaydi (bo'sh qiymat = o'chirish)
create or replace function public.uno_set_gh_token(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  if coalesce(trim(p_token), '') = '' then
    delete from public.uno_private where key in ('gh_token', 'gh_kick_at');
    return;
  end if;
  insert into public.uno_private(key, value) values ('gh_token', trim(p_token))
  on conflict (key) do update set value = excluded.value;
end $$;

-- kalit kiritilganmi va oxirgi signal qachon yuborilgan (kalitning o'zi qaytarilmaydi)
create or replace function public.uno_gh_status() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return jsonb_build_object(
    'has', coalesce((select value from public.uno_private where key = 'gh_token'), '') <> '',
    'last', (select value from public.uno_private where key = 'gh_kick_at'));
end $$;

-- GitHub'ga "yangi media bor, tuzat" signali (3 daqiqada ko'pi bilan bir marta)
create or replace function public.uno_media_kick(p_force boolean default false) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tok text; last_at timestamptz;
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  tok := (select value from public.uno_private where key = 'gh_token');
  if coalesce(tok, '') = '' then return 'no_token'; end if;
  begin
    last_at := (select value from public.uno_private where key = 'gh_kick_at')::timestamptz;
  exception when others then last_at := null;
  end;
  if not p_force and last_at is not null and last_at > now() - interval '3 minutes' then return 'recent'; end if;
  insert into public.uno_private(key, value) values ('gh_kick_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
  on conflict (key) do update set value = excluded.value;
  perform net.http_post(
    url := 'https://api.github.com/repos/spesmuz/uno-menu/actions/workflows/opt-videos.yml/dispatches',
    body := '{"ref":"main"}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || tok,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'uno-menu',
      'Content-Type', 'application/json'));
  return 'sent';
end $$;

revoke all on function public.uno_set_gh_token(text) from public, anon;
revoke all on function public.uno_gh_status() from public, anon;
revoke all on function public.uno_media_kick(boolean) from public, anon;
grant execute on function public.uno_set_gh_token(text) to authenticated;
grant execute on function public.uno_gh_status() to authenticated;
grant execute on function public.uno_media_kick(boolean) to authenticated;

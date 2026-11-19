-- UNO Airways: chaqiruvlarni Telegram guruhga yuborish
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.
-- (calls.sql oldin ishga tushirilgan bo'lishi kerak)

create extension if not exists pg_net;

-- yashirin sozlamalar: faqat admin o'qiy oladi, mijozlar ko'rmaydi
create table if not exists public.uno_private (key text primary key, value text);
alter table public.uno_private enable row level security;
revoke all on public.uno_private from anon, authenticated;

create or replace function public.uno_priv(k text) returns text
language sql stable security definer set search_path = public as $$
  select value from public.uno_private where key = k;
$$;
revoke all on function public.uno_priv(text) from public, anon, authenticated;

-- admin: bot kaliti va guruhni saqlash
create or replace function public.uno_set_telegram(p_token text, p_chat text, p_title text, p_site text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  insert into public.uno_private(key, value) values
    ('tg_token', trim(p_token)), ('tg_chat', trim(p_chat)), ('tg_title', coalesce(p_title,'')), ('site_url', coalesce(nullif(trim(p_site),''), 'https://spesmuz.github.io/uno-menu/'))
  on conflict (key) do update set value = excluded.value;
end $$;

-- admin: holat (kalitning o'zi qaytarilmaydi)
create or replace function public.uno_telegram_status() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  return jsonb_build_object('configured', coalesce(public.uno_priv('tg_token'),'') <> '' and coalesce(public.uno_priv('tg_chat'),'') <> '',
                            'chat', public.uno_priv('tg_chat'), 'title', public.uno_priv('tg_title'));
end $$;

-- Telegram'ga xabar yuborish (ichki)
create or replace function public.uno_tg_send(p_text text, p_markup jsonb default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare tok text := public.uno_priv('tg_token'); chat text := public.uno_priv('tg_chat'); body jsonb;
begin
  if coalesce(tok,'') = '' or coalesce(chat,'') = '' then return; end if;
  body := jsonb_build_object('chat_id', chat, 'text', p_text, 'parse_mode', 'HTML', 'disable_web_page_preview', true);
  if p_markup is not null then body := body || jsonb_build_object('reply_markup', p_markup); end if;
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/sendMessage', body := body,
                        headers := '{"Content-Type":"application/json"}'::jsonb);
exception when others then
  raise warning 'telegram: %', sqlerrm;   -- chaqiruvning o'zi baribir saqlanadi
end $$;
revoke all on function public.uno_tg_send(text, jsonb) from public, anon, authenticated;

create or replace function public.uno_tg_esc(s text) returns text language sql immutable as $$
  select replace(replace(replace(coalesce(s,''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
$$;
create or replace function public.uno_money(n numeric) returns text language sql immutable as $$
  select regexp_replace(round(coalesce(n,0))::bigint::text, '(\d)(?=(\d{3})+$)', '\1 ', 'g') || ' so''m';
$$;

-- yangi chaqiruv → Telegram
create or replace function public.uno_calls_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare txt text; it jsonb; site text := coalesce(public.uno_priv('site_url'), 'https://spesmuz.github.io/uno-menu/');
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
  perform public.uno_tg_send(txt, jsonb_build_object('inline_keyboard',
    jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '✅ Qabul qildim', 'url', site || 'ofitsiant.html?accept=' || new.id)))));
  return null;
end $$;
drop trigger if exists uno_calls_notify on public.uno_calls;
create trigger uno_calls_notify after insert on public.uno_calls
  for each row execute function public.uno_calls_notify();

-- qabul qilindi → Telegram
create or replace function public.uno_calls_accepted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'new' and new.status = 'accepted' then
    perform public.uno_tg_send('✅ <b>' || uno_tg_esc(new.table_no) || '-stol</b>: ' || uno_tg_esc(coalesce(new.accepted_by,'Ofitsiant')) || ' qabul qildi'
      || case when new.kind = 'bill' then ' (hisob)' else '' end);
  end if;
  return null;
end $$;
drop trigger if exists uno_calls_accepted on public.uno_calls;
create trigger uno_calls_accepted after update on public.uno_calls
  for each row execute function public.uno_calls_accepted();

-- admin: sinov xabari
create or replace function public.uno_telegram_test() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.uno_is_admin() then raise exception 'not_admin' using errcode = '42501'; end if;
  perform public.uno_tg_send('✅ <b>UNO Airways</b>: Telegram bot ulandi. Mijoz chaqiruvlari shu guruhga keladi.');
end $$;

grant execute on function public.uno_set_telegram(text, text, text, text) to authenticated;
grant execute on function public.uno_telegram_status() to authenticated;
grant execute on function public.uno_telegram_test() to authenticated;

notify pgrst, 'reload schema';

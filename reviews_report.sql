-- UNO Airways: taom sharhlari uchun "shikoyat qilish" va "muallifni bloklash" (App Store 1.2 talabi).
-- Supabase → SQL Editor → Run. Qayta ishga tushirish xavfsiz. Avval reviews.sql va telegram.sql ishlagan bo'lishi kerak.

create table if not exists public.uno_review_reports (
  review_id bigint not null references public.uno_reviews(id) on delete cascade,
  device    text   not null,
  reason    text,
  at        timestamptz not null default now(),
  primary key (review_id, device)
);
alter table public.uno_review_reports enable row level security;
revoke all on public.uno_review_reports from anon, authenticated;
grant select, delete on public.uno_review_reports to authenticated;
drop policy if exists uno_review_reports_admin on public.uno_review_reports;
create policy uno_review_reports_admin on public.uno_review_reports for all using (public.uno_is_admin()) with check (public.uno_is_admin());

-- sharhlar ro'yxati + muallifning anonim belgisi (bloklash uchun; telefon belgisining o'zi berilmaydi)
drop function if exists public.uno_reviews_for(text,text,int,bigint);
create function public.uno_reviews_for(p_dish text, p_device text default null, p_limit int default 20, p_before bigint default null)
returns table(id bigint, stars int, name text, comment text, created_at timestamptz, mine boolean, author text)
language sql stable security definer set search_path = public as $$
  (select r.id, r.stars, r.name, r.comment, r.created_at, true, left(md5(r.device), 12)
     from public.uno_reviews r where r.dish_id = p_dish and r.device = p_device and p_device is not null and p_before is null)
  union all
  (select r.id, r.stars, r.name, r.comment, r.created_at, false, left(md5(r.device), 12)
     from public.uno_reviews r
    where r.dish_id = p_dish and not r.hidden and coalesce(r.comment,'') <> ''
      and (p_device is null or r.device <> p_device)
      and (p_before is null or r.id < p_before)
    order by r.id desc limit least(greatest(coalesce(p_limit,20),1),50));
$$;
grant execute on function public.uno_reviews_for(text,text,int,bigint) to anon, authenticated;

-- mijoz sharhga shikoyat qiladi: restoran Telegram'ga xabar oladi; 3 ta shikoyatdan keyin sharh avtomatik yashiriladi
create or replace function public.uno_review_report(p_id bigint, p_device text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.uno_reviews; n int; dname text;
begin
  if length(coalesce(p_device,'')) < 8 then raise exception 'bad_device'; end if;
  select * into r from public.uno_reviews where id = p_id;
  if not found then return jsonb_build_object('ok', true); end if;
  insert into public.uno_review_reports(review_id, device, reason) values (p_id, p_device, left(p_reason, 200))
    on conflict do nothing;
  select count(*) into n from public.uno_review_reports where review_id = p_id;
  if n >= 3 and not r.hidden then update public.uno_reviews set hidden = true where id = p_id; end if;
  select data->>'name' into dname from public.uno_docs where path = 'dishes/' || r.dish_id;
  begin
    perform public.uno_tg_send('⚠️ <b>Sharhga shikoyat</b> (' || n || ' ta)' || chr(10)
      || '🍽 ' || public.uno_tg_esc(coalesce(dname, r.dish_id)) || chr(10)
      || '👤 ' || public.uno_tg_esc(coalesce(r.name, 'Mehmon')) || ' · ' || r.stars || '★' || chr(10)
      || '💬 ' || public.uno_tg_esc(left(coalesce(r.comment, ''), 300))
      || case when n >= 3 then chr(10) || '🙈 Avtomatik yashirildi' else chr(10) || 'Admin panel → Sharhlar bo''limida yashirish yoki o''chirish mumkin.' end);
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'reports', n);
end $$;
revoke all on function public.uno_review_report(bigint, text, text) from public;
grant execute on function public.uno_review_report(bigint, text, text) to anon, authenticated;

notify pgrst, 'reload schema';

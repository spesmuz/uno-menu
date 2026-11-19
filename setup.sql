-- UNO Airways Restaurante — Supabase sozlamasi
-- Supabase → SQL Editor → New query → shu faylni to'liq joylang → Run.
-- Qayta ishga tushirish xavfsiz.

-- 1) Menyu ma'lumotlari jadvali
create table if not exists public.uno_docs (
  path       text primary key,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2) Admin ro'yxati (faqat shu email'lar menyuni o'zgartira oladi)
create table if not exists public.uno_admins (email text primary key);
insert into public.uno_admins(email) values ('admin@uno.local') on conflict do nothing;

create or replace function public.uno_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.uno_admins where email = lower(coalesce(auth.jwt()->>'email','')));
$$;

alter table public.uno_docs   enable row level security;
alter table public.uno_admins enable row level security;

drop policy if exists uno_docs_read   on public.uno_docs;
drop policy if exists uno_docs_insert on public.uno_docs;
drop policy if exists uno_docs_update on public.uno_docs;
drop policy if exists uno_docs_delete on public.uno_docs;
create policy uno_docs_read   on public.uno_docs for select using (true);
create policy uno_docs_insert on public.uno_docs for insert with check (public.uno_is_admin());
create policy uno_docs_update on public.uno_docs for update using (public.uno_is_admin()) with check (public.uno_is_admin());
create policy uno_docs_delete on public.uno_docs for delete using (public.uno_is_admin());

-- 3) O'zgarishlar barcha planshetlarga darhol yetib borishi uchun (Realtime)
do $$ begin
  alter publication supabase_realtime add table public.uno_docs;
exception when duplicate_object then null; end $$;

-- 4) Rasm va videolar ombori (ochiq o'qish, faqat admin yuklaydi), 50 MB gacha
insert into storage.buckets (id, name, public, file_size_limit)
values ('uno-media', 'uno-media', true, 52428800)
on conflict (id) do update set public = true;

drop policy if exists uno_media_insert on storage.objects;
drop policy if exists uno_media_update on storage.objects;
drop policy if exists uno_media_delete on storage.objects;
create policy uno_media_insert on storage.objects for insert to authenticated with check (bucket_id = 'uno-media' and public.uno_is_admin());
create policy uno_media_update on storage.objects for update to authenticated using (bucket_id = 'uno-media' and public.uno_is_admin());
create policy uno_media_delete on storage.objects for delete to authenticated using (bucket_id = 'uno-media' and public.uno_is_admin());

-- Boshlang'ich menyu admin panelga birinchi kirishda o'zi yuklanadi.

-- 5) Data API orqali kirish huquqlari (yangi Supabase loyihalarida avtomatik berilmaydi)
grant usage on schema public to anon, authenticated;
grant select on public.uno_docs to anon, authenticated;
grant insert, update, delete on public.uno_docs to authenticated;
grant execute on function public.uno_is_admin() to anon, authenticated;
notify pgrst, 'reload schema';

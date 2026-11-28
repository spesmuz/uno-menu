-- UNO Airways: ofitsiant chaqiruvi va hisob so'rash
-- Supabase → SQL Editor → shu faylni joylab → Run. Qayta ishga tushirish xavfsiz.

create table if not exists public.uno_calls (
  id          bigint generated always as identity primary key,
  table_no    text not null check (char_length(table_no) between 1 and 30),
  kind        text not null check (kind in ('waiter','bill')),
  total       numeric check (total is null or (total >= 0 and total < 1000000000)),
  items       jsonb,
  status      text not null default 'new' check (status in ('new','accepted')),
  accepted_by text,
  created_at  timestamptz not null default now(),
  accepted_at timestamptz
);
create index if not exists uno_calls_status_idx on public.uno_calls (status, created_at desc);

alter table public.uno_calls enable row level security;
drop policy if exists uno_calls_insert on public.uno_calls;
drop policy if exists uno_calls_read   on public.uno_calls;
-- mijoz yangi chaqiruv yarata oladi
create policy uno_calls_insert on public.uno_calls for insert to anon, authenticated
  with check (status = 'new' and accepted_by is null and accepted_at is null);
-- oxirgi 12 soatdagi chaqiruvlarni o'qish (stol raqami va turi, shaxsiy ma'lumot yo'q)
create policy uno_calls_read on public.uno_calls for select to anon, authenticated
  using (created_at > now() - interval '12 hours');

-- bir stoldan bir xil chaqiruvni 20 soniyada bir martadan ko'p yubormaslik
create or replace function public.uno_calls_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.uno_calls
             where table_no = new.table_no and kind = new.kind and status = 'new'
               and created_at > now() - interval '20 seconds') then
    raise exception 'too_soon' using errcode = 'P0001';
  end if;
  if (select count(*) from public.uno_calls where created_at > now() - interval '1 minute') > 60 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists uno_calls_guard on public.uno_calls;
create trigger uno_calls_guard before insert on public.uno_calls
  for each row execute function public.uno_calls_guard();

-- ofitsiant chaqiruvni qabul qiladi (faqat holat va ism o'zgaradi)
create or replace function public.uno_accept_call(p_id bigint, p_by text) returns void
language sql security definer set search_path = public as $$
  update public.uno_calls
     set status = 'accepted', accepted_by = left(coalesce(nullif(trim(p_by),''),'Ofitsiant'), 40), accepted_at = now()
   where id = p_id and status = 'new';
$$;

grant usage on schema public to anon, authenticated;
grant select, insert on public.uno_calls to anon, authenticated;
grant execute on function public.uno_accept_call(bigint, text) to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.uno_calls;
exception when duplicate_object then null; end $$;

notify pgrst, 'reload schema';

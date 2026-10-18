-- MIGRAÇÃO MULTIUSUÁRIO (rode uma vez no SQL Editor; não apaga dados)

-- 1) Perfis (nome, foto, cor). A senha fica só no Supabase Auth.
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url   text,
  theme_color  text default '#e8638b',
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "profiles_select_own" on public.profiles for select to authenticated using (user_id = auth.uid());
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check (user_id = auth.uid());
create policy "profiles_update_own" on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name',
                           new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- 2) Treino: cada linha pertence a um usuário (preenchido pelo banco com auth.uid())
alter table public.workout_completions add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete cascade;
alter table public.workout_days        add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete cascade;
alter table public.workout_completions drop constraint if exists workout_completions_workout_date_exercise_id_key;
alter table public.workout_days        drop constraint if exists workout_days_week_start_workout_day_key;
create unique index if not exists wc_user_unique on public.workout_completions (user_id, workout_date, exercise_id);
create unique index if not exists wd_user_unique on public.workout_days (user_id, week_start, workout_day);

-- 3) Troca as políticas abertas (anon) por políticas "só o dono" (RLS)
drop policy if exists "wc_select" on public.workout_completions;
drop policy if exists "wc_insert" on public.workout_completions;
drop policy if exists "wc_update" on public.workout_completions;
drop policy if exists "wc_delete" on public.workout_completions;
drop policy if exists "wd_select" on public.workout_days;
drop policy if exists "wd_insert" on public.workout_days;
drop policy if exists "wd_update" on public.workout_days;
drop policy if exists "wd_delete" on public.workout_days;
create policy "wc_own_select" on public.workout_completions for select to authenticated using (user_id = auth.uid());
create policy "wc_own_insert" on public.workout_completions for insert to authenticated with check (user_id = auth.uid());
create policy "wc_own_update" on public.workout_completions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "wc_own_delete" on public.workout_completions for delete to authenticated using (user_id = auth.uid());
create policy "wd_own_select" on public.workout_days for select to authenticated using (user_id = auth.uid());
create policy "wd_own_insert" on public.workout_days for insert to authenticated with check (user_id = auth.uid());
create policy "wd_own_update" on public.workout_days for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "wd_own_delete" on public.workout_days for delete to authenticated using (user_id = auth.uid());

-- 4) Fotos de perfil: bucket "avatars", cada usuário só mexe na própria pasta (<user_id>/...)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy "avatars_select_own" on storage.objects for select to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_insert_own" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_update_own" on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_delete_own" on storage.objects for delete to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- OPCIONAL: registros antigos (sem dono) ficam invisíveis. Para passá-los para a SUA conta,
-- crie sua conta, copie seu id em Authentication > Users e rode (troque SEU-ID):
-- update public.workout_completions set user_id = 'SEU-ID' where user_id is null;
-- update public.workout_days        set user_id = 'SEU-ID' where user_id is null;

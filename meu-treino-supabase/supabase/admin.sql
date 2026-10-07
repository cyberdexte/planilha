-- ÁREA DO ADMINISTRADOR (rode uma vez no SQL Editor; não altera nem apaga tabelas existentes)
-- Pré-requisito: multiusuario.sql já executado (usa public.profiles).
--
-- Modelo (reaproveita o que existe: usuário = auth.users, nome = profiles, exercícios = ids do app, ex.: cf, mf):
--   auth.users -> student_plans -> student_plan_days -> student_plan_exercises -> exercise_id
-- Aluno SEM linha em student_plans continua usando o treino padrão do app. Nada do que já existe muda.

-- =====================================================================
-- 1) Administradores (controlado só pelo banco; ninguém altera pelo site)
-- =====================================================================
create table if not exists public.admin_users (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null unique references auth.users(id) on delete cascade,
  email      text        not null,
  active     boolean     not null default true,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
drop policy if exists "admin_users_select_self" on public.admin_users;
create policy "admin_users_select_self" on public.admin_users for select to authenticated using (user_id = auth.uid());
revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to authenticated;   -- só a própria linha (política acima); sem insert/update/delete

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid() and active)
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Para autorizar alguém: a pessoa cria a conta primeiro; depois rode  select public.add_admin('email@exemplo.com');
-- Para desativar:  update public.admin_users set active = false where email = 'email@exemplo.com';
create or replace function public.add_admin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare u record;
begin
  select id, email into u from auth.users where lower(email) = lower(trim(p_email));
  if not found then raise exception 'Usuário % não encontrado. A pessoa precisa criar a conta primeiro.', p_email; end if;
  insert into public.admin_users (user_id, email, active) values (u.id, u.email, true)
  on conflict (user_id) do update set active = true, email = excluded.email;
end $$;
revoke all on function public.add_admin(text) from public, anon, authenticated;   -- só o SQL Editor (postgres) executa

-- =====================================================================
-- 2) Treino individual do aluno
-- =====================================================================
create table if not exists public.student_plans (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create table if not exists public.student_plan_days (
  id      uuid     primary key default gen_random_uuid(),
  user_id uuid     not null references public.student_plans(user_id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),            -- 0 = segunda ... 5 = sábado, 6 = domingo
  title   text     not null check (char_length(title) between 1 and 80),
  notes   text     check (notes is null or char_length(notes) <= 500),
  unique (user_id, weekday)
);
create table if not exists public.student_plan_exercises (
  id          uuid    primary key default gen_random_uuid(),
  day_id      uuid    not null references public.student_plan_days(id) on delete cascade,
  user_id     uuid    not null references public.student_plans(user_id) on delete cascade,
  exercise_id text    not null check (exercise_id ~ '^[a-z]{2}$'),       -- mesmo id do app (não existe tabela global de exercícios)
  position    integer not null check (position >= 0),
  unique (day_id, exercise_id)
);
create index if not exists spe_day_idx on public.student_plan_exercises (day_id, position);
create index if not exists spe_user_idx on public.student_plan_exercises (user_id);

alter table public.student_plans          enable row level security;
alter table public.student_plan_days      enable row level security;
alter table public.student_plan_exercises enable row level security;
drop policy if exists "sp_select"  on public.student_plans;
drop policy if exists "spd_select" on public.student_plan_days;
drop policy if exists "spe_select" on public.student_plan_exercises;
create policy "sp_select"  on public.student_plans          for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "spd_select" on public.student_plan_days      for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "spe_select" on public.student_plan_exercises for select to authenticated using (user_id = auth.uid() or public.is_admin());
-- Escrita: nenhuma política de insert/update/delete. Só a função admin_save_student_plan (que exige is_admin()) grava.
revoke all on public.student_plans, public.student_plan_days, public.student_plan_exercises from anon, authenticated;
grant select on public.student_plans, public.student_plan_days, public.student_plan_exercises to authenticated;

-- =====================================================================
-- 3) Auditoria (quem alterou o treino de quem, quando e o quê)
-- =====================================================================
create table if not exists public.admin_audit_log (
  id            uuid        primary key default gen_random_uuid(),
  admin_id      uuid        not null,
  admin_email   text,
  student_id    uuid        not null,
  student_email text,
  action        text        not null,
  details       jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists admin_audit_student_idx on public.admin_audit_log (student_id, created_at desc);
alter table public.admin_audit_log enable row level security;
drop policy if exists "audit_select_admin" on public.admin_audit_log;
create policy "audit_select_admin" on public.admin_audit_log for select to authenticated using (public.is_admin());
revoke all on public.admin_audit_log from anon, authenticated;
grant select on public.admin_audit_log to authenticated;

-- =====================================================================
-- 4) Funções do administrador (todas exigem is_admin() dentro do banco)
-- =====================================================================
-- Busca UM aluno pelo e-mail exato (não lista usuários).
create or replace function public.admin_find_student(p_email text)
returns table (user_id uuid, email text, display_name text, status text, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select u.id, u.email::text, coalesce(p.display_name, split_part(u.email::text, '@', 1)),
           case when u.banned_until is not null and u.banned_until > now() then 'Bloqueada'
                when u.email_confirmed_at is null then 'E-mail não confirmado'
                else 'Ativa' end,
           u.created_at, u.last_sign_in_at
    from auth.users u left join public.profiles p on p.user_id = u.id
    where lower(u.email::text) = lower(trim(p_email))
    limit 1;
end $$;
revoke all on function public.admin_find_student(text) from public, anon;
grant execute on function public.admin_find_student(text) to authenticated;

-- Substitui, de forma atômica, o treino do aluno. p_plan = [{weekday,title,notes,exercises:["cf","mf",...]}, ...] (só dias com exercícios)
create or replace function public.admin_save_student_plan(p_user uuid, p_plan jsonb, p_summary jsonb default '[]'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; e jsonb; v_day uuid; v_pos int; v_wd int; v_seen int[] := '{}'; v_admin text; v_student text;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select email::text into v_student from auth.users where id = p_user;
  if not found then raise exception 'student not found'; end if;
  if jsonb_typeof(p_plan) <> 'array' or jsonb_array_length(p_plan) > 7 then raise exception 'invalid plan'; end if;

  insert into public.student_plans (user_id, updated_by, updated_at) values (p_user, auth.uid(), now())
  on conflict (user_id) do update set updated_by = auth.uid(), updated_at = now();
  delete from public.student_plan_days where user_id = p_user;       -- apaga só a relação do aluno (exercícios do app não são tocados)

  for d in select * from jsonb_array_elements(p_plan) loop
    v_wd := (d->>'weekday')::int;
    if v_wd is null or v_wd < 0 or v_wd > 6 or v_wd = any (v_seen) then raise exception 'invalid weekday'; end if;
    v_seen := v_seen || v_wd;
    if jsonb_typeof(d->'exercises') <> 'array' or jsonb_array_length(d->'exercises') not between 1 and 20 then raise exception 'invalid exercises'; end if;
    insert into public.student_plan_days (user_id, weekday, title, notes)
    values (p_user, v_wd, left(coalesce(nullif(trim(d->>'title'), ''), 'Treino'), 80), nullif(left(trim(coalesce(d->>'notes', '')), 500), ''))
    returning id into v_day;
    v_pos := 0;
    for e in select * from jsonb_array_elements(d->'exercises') loop
      insert into public.student_plan_exercises (day_id, user_id, exercise_id, position) values (v_day, p_user, e #>> '{}', v_pos);
      v_pos := v_pos + 1;
    end loop;
  end loop;

  select email::text into v_admin from auth.users where id = auth.uid();
  insert into public.admin_audit_log (admin_id, admin_email, student_id, student_email, action, details)
  values (auth.uid(), v_admin, p_user, v_student, 'plan_update',
          jsonb_build_object('changes', case when jsonb_typeof(p_summary) = 'array' then p_summary else '[]'::jsonb end));
end $$;
revoke all on function public.admin_save_student_plan(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.admin_save_student_plan(uuid, jsonb, jsonb) to authenticated;

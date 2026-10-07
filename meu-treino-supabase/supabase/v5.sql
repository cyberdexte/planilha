-- MEU TREINO V5 (rode uma vez no SQL Editor, depois de schema.sql, multiusuario.sql, exercise_videos.sql e admin.sql)
-- Não apaga nem altera dados existentes. Todo usuário existente continua ATIVO (sem linha em account_status = ativo).

-- =====================================================================
-- 1) Status da conta: ativo / pausado (só o administrador altera, via função)
-- =====================================================================
create table if not exists public.account_status (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  status     text        not null default 'active' check (status in ('active','paused')),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.account_status enable row level security;
drop policy if exists "account_status_select" on public.account_status;
create policy "account_status_select" on public.account_status for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
revoke all on public.account_status from anon, authenticated;
grant select on public.account_status to authenticated;       -- sem insert/update/delete: o usuário não consegue se reativar

create or replace function public.is_paused() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.account_status where user_id = auth.uid() and status = 'paused')
$$;
revoke all on function public.is_paused() from public, anon;
grant execute on function public.is_paused() to authenticated;

-- =====================================================================
-- 2) Registro de séries (carga e repetições)
-- =====================================================================
create table if not exists public.set_logs (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  workout_date date        not null check (workout_date >= date '2020-01-01' and workout_date <= current_date + 1),
  exercise_id  text        not null check (exercise_id ~ '^[a-z]{2}$'),
  set_number   smallint    not null check (set_number between 1 and 12),
  weight_kg    numeric(6,1) not null check (weight_kg >= 0 and weight_kg <= 1000),
  reps         smallint    not null check (reps between 1 and 500),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, workout_date, exercise_id, set_number)
);
create index if not exists set_logs_user_ex_idx   on public.set_logs (user_id, exercise_id, workout_date desc);
create index if not exists set_logs_user_date_idx on public.set_logs (user_id, workout_date desc);
create or replace function public.set_logs_touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists set_logs_touch on public.set_logs;
create trigger set_logs_touch before update on public.set_logs for each row execute function public.set_logs_touch();

alter table public.set_logs enable row level security;
drop policy if exists "set_logs_own" on public.set_logs;
create policy "set_logs_own" on public.set_logs for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.set_logs from anon;
grant select, insert, update, delete on public.set_logs to authenticated;

-- Meta semanal (opcional) no perfil existente
alter table public.profiles add column if not exists weekly_goal smallint check (weekly_goal between 1 and 7);

-- =====================================================================
-- 3) Imposição da pausa no banco: política RESTRITIVA (soma-se às políticas atuais, não as enfraquece)
--    Usuário pausado não lê nem grava dados de treino, mesmo chamando a API direto.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['workout_completions','workout_days','exercise_videos','student_plans','student_plan_days','student_plan_exercises','set_logs']
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "not_paused" on public.%I', t);
      execute format('create policy "not_paused" on public.%I as restrictive for all to authenticated using (not (select public.is_paused())) with check (not (select public.is_paused()))', t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- 4) Funções do administrador
-- =====================================================================
-- Lista alunos (nome, e-mail, status, plano, última atividade). Busca opcional por nome ou e-mail. Máx. 50.
create or replace function public.admin_list_students(p_query text default '', p_limit int default 30)
returns table (user_id uuid, email text, display_name text, status text, has_plan boolean, last_activity timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := lower(trim(coalesce(p_query, '')));
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select u.id, u.email::text,
           coalesce(nullif(p.display_name, ''), split_part(u.email::text, '@', 1)),
           coalesce(a.status, 'active'),
           exists (select 1 from public.student_plans sp where sp.user_id = u.id),
           greatest(u.last_sign_in_at,
                    (select max(c.completed_at) from public.workout_completions c where c.user_id = u.id),
                    (select max(l.updated_at) from public.set_logs l where l.user_id = u.id))
    from auth.users u
    left join public.profiles p on p.user_id = u.id
    left join public.account_status a on a.user_id = u.id
    where q = '' or position(q in lower(u.email::text)) > 0 or position(q in lower(coalesce(p.display_name, ''))) > 0
    order by lower(coalesce(nullif(p.display_name, ''), u.email::text))
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
end $$;
revoke all on function public.admin_list_students(text, int) from public, anon;
grant execute on function public.admin_list_students(text, int) to authenticated;

-- Pausa / reativa o acesso de um aluno. Não permite pausar administradores nem a si mesmo.
create or replace function public.admin_set_account_status(p_user uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_student text; v_admin text;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('active','paused') then raise exception 'invalid status'; end if;
  select email::text into v_student from auth.users where id = p_user;
  if not found then raise exception 'student not found'; end if;
  if p_status = 'paused' and (p_user = auth.uid() or exists (select 1 from public.admin_users where user_id = p_user and active)) then
    raise exception 'cannot pause an administrator';
  end if;
  insert into public.account_status (user_id, status, updated_by, updated_at) values (p_user, p_status, auth.uid(), now())
  on conflict (user_id) do update set status = excluded.status, updated_by = auth.uid(), updated_at = now();
  select email::text into v_admin from auth.users where id = auth.uid();
  insert into public.admin_audit_log (admin_id, admin_email, student_id, student_email, action, details)
  values (auth.uid(), v_admin, p_user, v_student, case when p_status = 'paused' then 'account_paused' else 'account_reactivated' end, '{}'::jsonb);
end $$;
revoke all on function public.admin_set_account_status(uuid, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, text) to authenticated;

-- Contato do administrador para a tela de acesso pausado (e-mail de um administrador ativo).
-- Prefira definir ADMIN_CONTACT no config.js (mailto: ou link do WhatsApp); esta função é só o plano B.
create or replace function public.get_admin_contact() returns text
language sql stable security definer set search_path = public as $$
  select email from public.admin_users where active order by created_at limit 1
$$;
revoke all on function public.get_admin_contact() from public, anon;
grant execute on function public.get_admin_contact() to authenticated;

-- ACESSO POR APROVAÇÃO + ÁREA "PERSONAL" (CTI Fabrício Borges)
-- Rode UMA vez no SQL Editor do Supabase, depois de todos os arquivos anteriores (schema, multiusuario, admin, v5, tutorials...).
-- Não apaga dados. Pode ser rodado de novo: a parte de "contas existentes" só executa na primeira vez.

-- =====================================================================
-- 1) Status de acesso no perfil (novas contas = 'pending'). Contas que JÁ existem ficam liberadas.
--    Também grava, uma única vez, o treino padrão antigo para quem ainda não tinha ficha própria,
--    para que nenhum aluno atual perca o treino que já usa.
-- =====================================================================
do $$
declare r record;
begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='access_status') then
    alter table public.profiles add column access_status text not null default 'approved'
      check (access_status in ('pending','approved','revoked'));
    -- perfis que faltavam (contas antigas sem linha em profiles)
    insert into public.profiles (user_id, display_name)
      select u.id, split_part(u.email::text,'@',1) from auth.users u
      where not exists (select 1 from public.profiles p where p.user_id = u.id)
      on conflict do nothing;
    -- a partir de agora, contas novas começam pendentes
    alter table public.profiles alter column access_status set default 'pending';

    -- ficha própria para quem usava o treino padrão (cópia fiel do padrão que o app mostrava)
    for r in select u.id as user_id from auth.users u
             where not exists (select 1 from public.student_plans sp where sp.user_id = u.id)
    loop
      insert into public.student_plans (user_id, updated_at) values (r.user_id, now());
      insert into public.student_plan_days (user_id, weekday, title)
        select r.user_id, d.wd, d.title from (values
    (0, 'Glúteos + Posterior'),
    (1, 'Costas + Braços Leves'),
    (2, 'Quadríceps + Glúteos'),
    (3, 'Costas + Ombros + Abdômen'),
    (4, 'Glúteos + Posterior'),
    (5, 'Pernas Completo + Abdômen')
        ) as d(wd, title);
      insert into public.student_plan_exercises (day_id, user_id, exercise_id, position)
        select pd.id, r.user_id, x.ex, x.pos from public.student_plan_days pd
        join (values
    (0, 'cf', 0),
    (0, 'mf', 1),
    (0, 'ep', 2),
    (0, 'gm', 3),
    (0, 'ab', 4),
    (0, 'lp', 5),
    (0, 'pa', 6),
    (1, 'pf', 0),
    (1, 'rb', 1),
    (1, 'ra', 2),
    (1, 'pu', 3),
    (1, 'fp', 4),
    (1, 'ro', 5),
    (1, 'tr', 6),
    (2, 'ex', 0),
    (2, 'lp', 1),
    (2, 'hk', 2),
    (2, 'sm', 3),
    (2, 'ab', 4),
    (2, 'ep', 5),
    (2, 'pa', 6),
    (3, 'pf', 0),
    (3, 'ra', 1),
    (3, 'rb', 2),
    (3, 'el', 3),
    (3, 'fp', 4),
    (3, 'am', 5),
    (3, 'pr', 6),
    (4, 'ep', 0),
    (4, 'cf', 1),
    (4, 'mf', 2),
    (4, 'gm', 3),
    (4, 'ab', 4),
    (4, 'lp', 5),
    (4, 'st', 6),
    (5, 'lp', 0),
    (5, 'ex', 1),
    (5, 'cf', 2),
    (5, 'hk', 3),
    (5, 'ab', 4),
    (5, 'gm', 5),
    (5, 'pa', 6),
    (5, 'am', 7)
        ) as x(wd, ex, pos) on x.wd = pd.weekday
        where pd.user_id = r.user_id;
    end loop;
  end if;
end $$;

-- Ninguém altera o próprio status de acesso (nem por chamada direta à API): só funções de administrador.
create or replace function public.profiles_guard_access() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated','anon') then
    if tg_op = 'INSERT' then new.access_status := 'pending';
    else new.access_status := old.access_status; end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard_access on public.profiles;
create trigger profiles_guard_access before insert or update on public.profiles
  for each row execute function public.profiles_guard_access();

-- =====================================================================
-- 2) Personal trainers (mesmo modelo dos administradores: só o SQL Editor concede)
-- =====================================================================
create table if not exists public.trainer_users (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  email      text        not null,
  active     boolean     not null default true,
  created_at timestamptz not null default now()
);
alter table public.trainer_users enable row level security;
drop policy if exists "trainer_users_select_self" on public.trainer_users;
create policy "trainer_users_select_self" on public.trainer_users for select to authenticated using (user_id = auth.uid());
revoke all on public.trainer_users from anon, authenticated;
grant select on public.trainer_users to authenticated;

create or replace function public.is_trainer() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trainer_users where user_id = auth.uid() and active)
$$;
create or replace function public.can_manage_plans() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or public.is_trainer()
$$;
create or replace function public.has_access() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or public.is_trainer()
      or exists (select 1 from public.profiles where user_id = auth.uid() and access_status = 'approved')
$$;
-- Resposta única para o app: status de acesso e papéis do usuário logado
create or replace function public.my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'status', case when public.has_access() then 'approved'
                   else coalesce((select access_status from public.profiles where user_id = auth.uid()), 'pending') end,
    'admin', public.is_admin(), 'trainer', public.is_trainer())
$$;
revoke all on function public.is_trainer(), public.can_manage_plans(), public.has_access(), public.my_access() from public, anon;
grant execute on function public.is_trainer(), public.can_manage_plans(), public.has_access(), public.my_access() to authenticated;

-- Para criar um personal: a pessoa cria a conta; depois rode  select public.add_trainer('email@exemplo.com');
-- Para desativar:  update public.trainer_users set active = false where email = 'email@exemplo.com';
create or replace function public.add_trainer(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare u record;
begin
  select id, email into u from auth.users where lower(email) = lower(trim(p_email));
  if not found then raise exception 'Usuário % não encontrado. A pessoa precisa criar a conta primeiro.', p_email; end if;
  insert into public.trainer_users (user_id, email, active) values (u.id, u.email, true)
  on conflict (user_id) do update set active = true, email = excluded.email;
  update public.profiles set access_status = 'approved' where user_id = u.id;
end $$;
revoke all on function public.add_trainer(text) from public, anon, authenticated;

-- =====================================================================
-- 3) Imposição no banco: sem acesso liberado, nenhuma tabela de treino é lida ou gravada (política RESTRITIVA)
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['workout_completions','workout_days','exercise_videos','student_plans','student_plan_days','student_plan_exercises','set_logs','tutorials']
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "access_required" on public.%I', t);
      execute format('create policy "access_required" on public.%I as restrictive for all to authenticated using ((select public.has_access())) with check ((select public.has_access()))', t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- 4) Personal: lê fichas dos alunos e salva pela função abaixo (nada além disso)
-- =====================================================================
drop policy if exists "sp_select_trainer"  on public.student_plans;
drop policy if exists "spd_select_trainer" on public.student_plan_days;
drop policy if exists "spe_select_trainer" on public.student_plan_exercises;
create policy "sp_select_trainer"  on public.student_plans          for select to authenticated using ((select public.is_trainer()));
create policy "spd_select_trainer" on public.student_plan_days      for select to authenticated using ((select public.is_trainer()));
create policy "spe_select_trainer" on public.student_plan_exercises for select to authenticated using ((select public.is_trainer()));

-- Salvar ficha: agora também aceita personal (continua exigindo administrador OU personal, validado no banco)
create or replace function public.admin_save_student_plan(p_user uuid, p_plan jsonb, p_summary jsonb default '[]'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; e jsonb; v_day uuid; v_pos int; v_wd int; v_seen int[] := '{}'; v_admin text; v_student text;
begin
  if not public.can_manage_plans() then raise exception 'forbidden' using errcode = '42501'; end if;
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

-- Busca de alunos para o Personal: só com 2+ letras, só nome/e-mail/plano (sem status de acesso nem dados sensíveis)
create or replace function public.personal_list_students(p_query text default '', p_limit int default 30)
returns table (user_id uuid, email text, display_name text, status text, has_plan boolean, last_activity timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := lower(trim(coalesce(p_query, '')));
begin
  if not public.can_manage_plans() then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(q) < 2 then return; end if;
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
    where position(q in lower(u.email::text)) > 0 or position(q in lower(coalesce(p.display_name, ''))) > 0
    order by lower(coalesce(nullif(p.display_name, ''), u.email::text))
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
end $$;
revoke all on function public.personal_list_students(text, int) from public, anon;
grant execute on function public.personal_list_students(text, int) to authenticated;

-- =====================================================================
-- 5) Administrador: "Liberar acesso" (somente is_admin())
-- =====================================================================
create or replace function public.admin_list_access(p_query text default '', p_limit int default 30)
returns table (user_id uuid, email text, display_name text, access_status text, is_admin boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := lower(trim(coalesce(p_query, '')));
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select u.id, u.email::text,
           coalesce(nullif(p.display_name, ''), split_part(u.email::text, '@', 1)),
           case when ad.user_id is not null then 'approved' else coalesce(p.access_status, 'pending') end,
           (ad.user_id is not null),
           u.created_at
    from auth.users u
    left join public.profiles p on p.user_id = u.id
    left join public.admin_users ad on ad.user_id = u.id and ad.active
    where q = '' or position(q in lower(u.email::text)) > 0 or position(q in lower(coalesce(p.display_name, ''))) > 0
    order by case when ad.user_id is null and coalesce(p.access_status, 'pending') = 'pending' then 0
                  when ad.user_id is null and p.access_status = 'revoked' then 1 else 2 end,
             u.created_at desc
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
end $$;
revoke all on function public.admin_list_access(text, int) from public, anon;
grant execute on function public.admin_list_access(text, int) to authenticated;

create or replace function public.admin_set_access(p_user uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_student text; v_admin text;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('approved','revoked') then raise exception 'invalid status'; end if;
  select email::text into v_student from auth.users where id = p_user;
  if not found then raise exception 'student not found'; end if;
  if p_status = 'revoked' and (p_user = auth.uid() or exists (select 1 from public.admin_users where user_id = p_user and active)) then
    raise exception 'cannot revoke an administrator';
  end if;
  insert into public.profiles (user_id, display_name, access_status) values (p_user, split_part(v_student,'@',1), p_status)
  on conflict (user_id) do update set access_status = excluded.access_status;
  select email::text into v_admin from auth.users where id = auth.uid();
  insert into public.admin_audit_log (admin_id, admin_email, student_id, student_email, action, details)
  values (auth.uid(), v_admin, p_user, v_student, case when p_status = 'approved' then 'access_approved' else 'access_revoked' end, '{}'::jsonb);
end $$;
revoke all on function public.admin_set_access(uuid, text) from public, anon;
grant execute on function public.admin_set_access(uuid, text) to authenticated;

-- Garantia: administradores nunca ficam bloqueados
update public.profiles p set access_status = 'approved'
 where p.access_status <> 'approved' and exists (select 1 from public.admin_users a where a.user_id = p.user_id and a.active);

-- Conclusão de treinos por dia (uma linha por semana + dia)
create table if not exists public.workout_days (
  id           uuid        primary key default gen_random_uuid(),
  week_start   date        not null,   -- segunda-feira da semana
  workout_day  text        not null,   -- ex.: segunda-feira
  completed    boolean     not null default true,
  completed_at timestamptz default now(),
  unique (week_start, workout_day)
);
alter table public.workout_days enable row level security;
create policy "wd_select" on public.workout_days for select to anon using (true);
create policy "wd_insert" on public.workout_days for insert to anon with check (true);
create policy "wd_update" on public.workout_days for update to anon using (true) with check (true);
create policy "wd_delete" on public.workout_days for delete to anon using (true);

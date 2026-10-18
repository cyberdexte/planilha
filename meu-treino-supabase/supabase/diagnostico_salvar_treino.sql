-- DIAGNÓSTICO (somente leitura: não altera nada). Rode no SQL Editor e me envie o resultado das 3 consultas.
-- 1) A função de salvar existe e para quem está liberada?
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('admin_save_student_plan','can_manage_plans','is_trainer','has_access');
-- 2) Existe alguma regra (check) limitando o exercise_id dos treinos dos alunos?
select conrelid::regclass as tabela, conname, pg_get_constraintdef(oid) as regra
from pg_constraint
where conrelid in ('public.student_plan_exercises'::regclass,'public.student_plan_days'::regclass) and contype in ('c','f');
-- 3) Colunas das tabelas de ficha
select table_name, column_name, data_type, character_maximum_length
from information_schema.columns
where table_schema='public' and table_name in ('student_plan_exercises','student_plan_days');

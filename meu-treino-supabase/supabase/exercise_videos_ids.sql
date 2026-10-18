-- LIBRARY EXPANSION: permite cadastrar vídeos para os exercícios novos (ids como add_supino_reto)
-- Rode UMA vez no SQL Editor do Supabase. Pode rodar de novo sem problema (idempotente).
-- Não apaga nem altera nenhuma linha: só troca a regra de formato do exercise_id
-- (antes aceitava apenas 2 letras, ex.: cf, mf; agora aceita letras minúsculas, números e "_").
do $$
declare c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.exercise_videos'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%exercise_id%' and pg_get_constraintdef(oid) like '%{2}%'
  loop
    execute format('alter table public.exercise_videos drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'exercise_videos_exercise_id_fmt'
                 and conrelid = 'public.exercise_videos'::regclass) then
    alter table public.exercise_videos
      add constraint exercise_videos_exercise_id_fmt check (exercise_id ~ '^[a-z0-9_]{2,60}$');
  end if;
end $$;

-- Para cadastrar um vídeo (use apenas links do YouTube que você conferiu e que permitam incorporação):
-- insert into public.exercise_videos (exercise_id, youtube_id, youtube_url, title)
-- values ('add_supino_inclinado_barra', 'XXXXXXXXXXX', 'https://www.youtube.com/watch?v=XXXXXXXXXXX', 'Supino inclinado com barra')
-- on conflict (exercise_id) do update set youtube_id=excluded.youtube_id, youtube_url=excluded.youtube_url, title=excluded.title, active=true;

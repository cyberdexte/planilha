-- VÍDEOS DE EXERCÍCIOS (rode uma vez no SQL Editor; não mexe nas outras tabelas)
-- Leitura: usuários logados veem só vídeos ativos. Escrita: só pelo painel do Supabase (SQL Editor / Table Editor).
create table if not exists public.exercise_videos (
  id          uuid        primary key default gen_random_uuid(),
  exercise_id text        not null unique,                       -- mesmo id usado no app: cf, mf, ep...
  youtube_id  text        not null check (youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  youtube_url text        not null check (youtube_url ~ '^https://(www\.|m\.)?(youtube\.com|youtu\.be)/'),
  title       text,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (exercise_id ~ '^[a-z]{2}$')
);
create index if not exists exercise_videos_active_idx on public.exercise_videos (exercise_id) where active;

create or replace function public.exercise_videos_touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists exercise_videos_touch on public.exercise_videos;
create trigger exercise_videos_touch before update on public.exercise_videos for each row execute function public.exercise_videos_touch();

alter table public.exercise_videos enable row level security;
drop policy if exists "ev_read_active" on public.exercise_videos;
create policy "ev_read_active" on public.exercise_videos for select to authenticated using (active = true);
-- Sem políticas de insert/update/delete: o app (anon/authenticated) não consegue alterar a tabela.
revoke all on public.exercise_videos from anon, authenticated;
grant select on public.exercise_videos to authenticated;

-- Exemplo (cadeira flexora). Para cadastrar outros: troque exercise_id e os dados do vídeo.
insert into public.exercise_videos (exercise_id, youtube_id, youtube_url, title)
values ('cf','RYCqCZhHh74','https://www.youtube.com/watch?v=RYCqCZhHh74','Cadeira Flexora - Execução correta')
on conflict (exercise_id) do update set youtube_id=excluded.youtube_id, youtube_url=excluded.youtube_url, title=excluded.title, active=true;

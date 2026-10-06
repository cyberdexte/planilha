# Meu Treino — versão Supabase + Netlify

Pastas: `public/` (o site), `supabase/schema.sql` (tabela), `build.js` + `netlify.toml` (a Netlify gera o `config.js` com suas variáveis).

## 1. Criar o projeto no Supabase
supabase.com > crie conta > **New project** > dê um nome, defina uma senha do banco e escolha a região (ex.: São Paulo). Aguarde terminar.

## 2. Criar a tabela
No menu esquerdo: **SQL Editor** > **New query**. A tabela `workout_completions` é criada pelo SQL abaixo.

## 3. SQL
Cole todo o conteúdo de `supabase/schema.sql` e clique em **Run**. Deve aparecer "Success". Confira em **Table Editor**.

## 4. URL e 5. chave anon
**Project Settings** (engrenagem) > **API**: copie a **Project URL** e a chave **anon public**. Nunca use a `service_role`.

## 6. Onde colocar
- Na Netlify: como variáveis de ambiente (passo 8). 
- No seu computador: edite `public/config.js`.

## 7. Publicar na Netlify
Crie uma conta no GitHub, um repositório e envie esta pasta inteira. Na Netlify: **Add new site > Import an existing project** > escolha o repositório. O `netlify.toml` já define o comando (`node build.js`) e a pasta (`public`). Ainda não clique em deploy sem fazer o passo 8.

## 8. Variáveis na Netlify
Em **Site configuration > Environment variables** (o nome do menu pode variar um pouco) crie:
- `SUPABASE_URL` = a Project URL
- `SUPABASE_ANON_KEY` = a chave anon public
Depois faça **Deploy** (ou **Trigger deploy** se já tinha feito).

## 9. Testar o salvamento
Abra o site, toque em "Concluir exercício". No Supabase, **Table Editor > workout_completions** deve mostrar a linha. Desmarcar apaga a linha.

## 10. Fechar e reabrir
Atualize a página, feche o navegador e abra de novo: o exercício continua concluído.

## 11. Domingo / nova semana
Abra `SEU-SITE.netlify.app/?hoje=2026-10-11` (um domingo): mostra "Descanso" e a semana zerada. As linhas antigas continuam na tabela. Datas simuladas gravam de verdade; desmarque depois. Para sair do teste, abra o site sem `?hoje=`.

## Segurança (leia)
Sem login, quem tiver o link do site consegue ler e alterar seus registros. Mantenha o endereço só com você. O limite é a chave anon ser pública por natureza. Para proteção real, o caminho é um login do Supabase com um único usuário (cadastro desativado); posso fazer isso depois.

## Rodar no computador
Edite `public/config.js` e, dentro de `public`, rode `python3 -m http.server 8000`.

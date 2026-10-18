# Acesso por aprovação + Personal — como aplicar

## 1. Antes de tudo
Faça um backup (Supabase > Database > Backups) ou ao menos exporte `profiles`, `student_plans` e `workout_completions`.

## 2. Rodar a migração (primeiro o SQL, depois o site)
1. Supabase > **SQL Editor** > New query.
2. Cole todo o conteúdo de `supabase/acesso_personal.sql` e clique em **Run**. Deve aparecer "Success".
3. Só depois publique o novo `index2.html`. (O site novo precisa das funções do banco; sem o SQL, todos ficam em "Não foi possível verificar seu acesso".)

O que a migração faz com quem já existe: todas as contas atuais continuam **liberadas**; quem usava o treino padrão ganha uma ficha própria igual ao padrão (nenhum aluno perde treino); os históricos não são tocados. Contas criadas depois nascem **pendentes**.

## 3. Criar personal trainers
A pessoa cria a conta no site. Depois, no SQL Editor:
`select public.add_trainer('email@exemplo.com');`
Para remover: `update public.trainer_users set active = false where email = 'email@exemplo.com';`
O trainer vê o menu **Personal** (só busca de alunos e edição de ficha). Liberar acesso, pausar contas e Aulas continuam só do administrador.

## 4. Fluxo do dia a dia
Aluno cria conta > vê "Aguardando liberação de acesso" > administrador abre **Administrador > Liberar acesso** e aprova > aluno toca em "Verificar liberação" (ou reabre o site) > vê "Seu treino está sendo preparado!" > personal busca o aluno em **Personal**, monta a ficha e salva > aluno vê os treinos.

## 5. Importante
- Se você revogar um acesso, o banco bloqueia os dados na hora; a tela do aluno atualiza quando ele reabre/volta ao site (ou em até 5 minutos).
- **Ranking:** as funções `ranking_leaders`, `ranking_period` e `ranking_periods` não estavam nos arquivos que tenho, então esta migração NÃO as protege. Uma conta pendente que chame essas funções direto pela API poderia ver nomes e pontos. Me envie o `ranking.sql` que eu adiciono a verificação `has_access()`.
- O que **não foi testado**: nada rodou em um Supabase de verdade (veja o relatório de testes na resposta).

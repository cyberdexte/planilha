# CTI Fabrício Borges — PWA

## O que foi acrescentado
- `public/manifest.webmanifest` — nome, cores (#09090b), `display: standalone`, ícones.
- `public/service-worker.js` — cache só de arquivos estáticos públicos (HTML, config.js, ícones, biblioteca supabase-js e fontes). **Nunca** intercepta o Supabase (login, tokens, dados), YouTube, requisições POST/com Authorization.
- `public/icons/` — PNGs 192/512 (normal e maskable), apple-touch-icon e favicon, gerados a partir do logo FB que já estava no site (o logo original tem só 188 px, então os ícones grandes ficam um pouco suaves; se tiver o arquivo original em alta resolução, substitua os PNGs mantendo os nomes).
- `public/index.html` — apenas acréscimos: metatags/manifest no `<head>`, um bloco de CSS no fim do `<style>` e um bloco de HTML+JS no fim (registro do service worker, botão "Instalar", aviso de falta de conexão, esconder a barra inferior enquanto o teclado está aberto). Nenhuma função existente foi alterada.
- `build.js` — carimba uma versão nova no service worker a cada deploy. `netlify.toml` — cabeçalhos `no-cache` para service worker, manifest e index.html.

## Testar localmente
`cd public && python3 -m http.server 8000` e abra `http://localhost:8000` no Chrome (localhost conta como seguro). DevTools > Application > Manifest / Service Workers; marque "Offline" e recarregue.

## Publicar
Mesmo fluxo da Netlify (HTTPS automático). Depois do deploy, abra o site no Android (Chrome): aparece o aviso "Instalar" (ou menu ⋮ > Instalar app). No iPhone: Safari > Compartilhar > Adicionar à Tela de Início.
Em Supabase > Authentication > URL Configuration, confirme que a URL do site está em Site URL/Redirect URLs (o app instalado usa a mesma URL).

## Offline
Abre a interface se o site já foi visitado. Login, verificação de acesso, salvar treinos e administração exigem internet (o app já mostra mensagens em português, e agora também um aviso "Sem conexão"). Não há sincronização offline de edições.

// Gera o config do Supabase no deploy.
// Se as variáveis de ambiente existirem, elas têm prioridade.
// Caso contrário, mantém o config.js já incluído no projeto.
const fs = require("fs");
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_ANON_KEY;

if (url && key) {
  fs.writeFileSync(
    "public/config.js",
    "window.TREINO_CONFIG = " + JSON.stringify({
      SUPABASE_URL: url,
      SUPABASE_ANON_KEY: key
    }) + ";\n"
  );
  console.log("config.js gerado a partir das variáveis de ambiente.");
} else if (fs.existsSync("public/config.js")) {
  console.log("Variáveis do Supabase não definidas; usando o public/config.js existente.");
} else {
  console.error("Faltam SUPABASE_URL e SUPABASE_ANON_KEY e não existe public/config.js.");
  process.exit(1);
}

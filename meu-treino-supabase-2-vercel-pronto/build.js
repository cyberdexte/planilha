// Build script for Vercel/Netlify.
// It generates public/config.js from environment variables when available.
// If variables are not configured, it preserves the existing public/config.js.
const fs = require("fs");
const path = require("path");

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_ANON_KEY;
const configPath = path.join(process.cwd(), "public", "config.js");

if (url && key) {
  const content =
    "window.TREINO_CONFIG = " +
    JSON.stringify({
      SUPABASE_URL: url,
      SUPABASE_ANON_KEY: key
    }) +
    ";\n";

  fs.writeFileSync(configPath, content, "utf8");
  console.log("config.js gerado a partir das variáveis do ambiente.");
} else if (fs.existsSync(configPath)) {
  console.warn(
    "SUPABASE_URL/SUPABASE_ANON_KEY não foram configuradas. " +
    "O config.js existente será preservado."
  );
} else {
  console.error("config.js não encontrado e as variáveis SUPABASE_URL e SUPABASE_ANON_KEY não foram configuradas.");
  process.exit(1);
}

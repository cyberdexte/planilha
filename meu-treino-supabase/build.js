// Runs on Netlify: writes public/config.js from environment variables
const fs = require("fs");
const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;
if (!url || !key) { console.error("Faltam as variáveis SUPABASE_URL e SUPABASE_ANON_KEY na Netlify."); process.exit(1); }
fs.writeFileSync("public/config.js", "window.TREINO_CONFIG = " + JSON.stringify({ SUPABASE_URL: url, SUPABASE_ANON_KEY: key }) + ";\n");
console.log("config.js gerado.");

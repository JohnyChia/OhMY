const { createClient } = require("@supabase/supabase-js");


// A valid local-shaped URL keeps the chatbot runnable when a developer has
// not configured Supabase yet. Services already catch failed Supabase calls
// and use their in-memory fallback; real credentials take precedence.
const supabase = createClient(
  process.env.SUPABASE_URL || "http://127.0.0.1:54321",
  process.env.SUPABASE_SERVICE_ROLE_KEY || "local-development-key",
);


module.exports = supabase;

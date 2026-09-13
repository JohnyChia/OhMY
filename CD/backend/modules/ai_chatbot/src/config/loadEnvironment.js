const path = require('node:path');
const fs = require('node:fs');
const dotenv = require('dotenv');

const SHARED_KEYS = new Set([
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'PREFERENCE_RECOMMENDER_URL',
  'WHISPER_PROMPT',
]);

function environmentPaths(moduleRoot) {
  return [
    path.join(moduleRoot, '.env'),
    path.resolve(moduleRoot, '..', '..', '.env'),
  ];
}

function loadEnvironment(moduleRoot) {
  const [moduleEnv, backendEnv] = environmentPaths(moduleRoot);
  dotenv.config({ path: moduleEnv });

  if (!fs.existsSync(backendEnv)) return;
  const shared = dotenv.parse(fs.readFileSync(backendEnv));
  for (const [key, value] of Object.entries(shared)) {
    const isChatbotSetting = SHARED_KEYS.has(key)
      || key.startsWith('GEMINI_')
      || key.startsWith('GROQ_')
      || key.startsWith('NOVA_');
    if (isChatbotSetting && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

module.exports = { environmentPaths, loadEnvironment };

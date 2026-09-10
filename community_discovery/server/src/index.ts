import { config as loadEnvironment } from 'dotenv';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';
import { readServerConfig } from './config.js';
import { createDatabaseClient } from './database.js';

const serverDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectDirectory = resolve(serverDirectory, '..');
// Existing process variables win. The whole-project file is primary; a local
// server/.env can fill any missing values during isolated module development.
loadEnvironment({ path: resolve(projectDirectory, '.env'), quiet: true });
loadEnvironment({ path: resolve(serverDirectory, '.env'), quiet: true });

const config = readServerConfig();
const database = createDatabaseClient(
  config.supabaseUrl,
  config.supabaseServiceRoleKey,
);

createApp({
  database,
  googlePlacesApiKey: config.googlePlacesApiKey,
  allowedOrigins: config.allowedOrigins,
}).listen(config.port, () => {
  process.stdout.write(
    `Community validation service listening on port ${config.port}.\n`,
  );
});

export interface ServerConfig {
  port: number;
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  googlePlacesApiKey?: string;
  allowedOrigins: string[];
}

function required(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name]?.trim();
  if (!value || value.startsWith('YOUR_')) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

export function readServerConfig(
  environment: NodeJS.ProcessEnv = process.env,
): ServerConfig {
  const port = Number(environment.PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }

  const supabaseUrl = required(environment, 'SUPABASE_URL');
  const supabaseServiceRoleKey = required(
    environment,
    'SUPABASE_SERVICE_ROLE_KEY',
  );
  if (supabaseServiceRoleKey.startsWith('sb_publishable_')) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY must be a private server key, not a publishable key.',
    );
  }

  const googlePlacesApiKey = environment.GOOGLE_PLACES_API_KEY?.trim();
  return {
    port,
    supabaseUrl,
    supabaseServiceRoleKey,
    googlePlacesApiKey: googlePlacesApiKey || undefined,
    allowedOrigins: (environment.ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  };
}

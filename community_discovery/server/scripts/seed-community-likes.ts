import { resolve } from 'node:path';
import { createClient, type User } from '@supabase/supabase-js';
import { config } from 'dotenv';

config({ path: resolve(process.cwd(), '../../CD/backend/.env') });

const supabaseUrl = process.env.SUPABASE_URL?.trim();
const anonKey = process.env.SUPABASE_ANON_KEY?.trim();
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

if (!supabaseUrl || !anonKey || !serviceRoleKey) {
  throw new Error(
    'SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are required in CD/backend/.env.',
  );
}

function requiredPassword(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required in CD/backend/.env.`);
  return value;
}

const seedUsers = [
  {
    email: 'Aina@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_AINA_PASSWORD'),
    name: 'Aina',
  },
  {
    email: 'Hafiz@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_HAFIZ_PASSWORD'),
    name: 'Hafiz',
  },
  {
    email: 'MeiLin@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_MEILIN_PASSWORD'),
    name: 'Mei Lin',
  },
] as const;

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function allUsers(): Promise<User[]> {
  const users: User[] = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) return users;
  }
}

async function main() {
  const users = await allUsers();
  const { data: posts, error: postsError } = await admin
    .from('community_posts')
    .select('id, title, author_id')
    .eq('moderation_status', 'approved')
    .order('created_at', { ascending: false })
    .limit(12);
  if (postsError) throw postsError;
  if (!posts?.length) {
    console.log('No approved Community posts were found.');
    return;
  }

  let created = 0;
  let skipped = 0;
  for (let userIndex = 0; userIndex < seedUsers.length; userIndex += 1) {
    const seed = seedUsers[userIndex]!;
    const user = users.find(
      (candidate) =>
        candidate.email?.toLowerCase() === seed.email.toLowerCase(),
    );
    if (!user) throw new Error(`Existing seed user not found: ${seed.email}`);

    const client = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: signInError } = await client.auth.signInWithPassword({
      email: seed.email,
      password: seed.password,
    });
    if (signInError) throw new Error(`Could not sign in ${seed.email}.`);

    const rotated = [
      ...posts.slice(userIndex),
      ...posts.slice(0, userIndex),
    ];
    const targets = rotated
      .filter((post) => post.author_id !== user.id)
      .slice(0, 4);

    for (const post of targets) {
      const { data: existing, error: existingError } = await admin
        .from('community_post_likes')
        .select('post_id')
        .eq('post_id', post.id)
        .eq('user_id', user.id)
        .maybeSingle();
      if (existingError) throw existingError;
      if (existing) {
        skipped += 1;
        continue;
      }

      const { error: insertError } = await client
        .from('community_post_likes')
        .insert({ post_id: post.id, user_id: user.id });
      if (insertError) throw insertError;
      created += 1;
      console.log(`[liked] ${seed.name}: ${post.title}`);
    }
    await client.auth.signOut();
  }

  console.log(
    `Like seed complete: ${created} likes created, ${skipped} existing likes skipped.`,
  );
}

await main();

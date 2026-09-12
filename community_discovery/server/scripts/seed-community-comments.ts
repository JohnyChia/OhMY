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

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function requiredPassword(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required in CD/backend/.env.`);
  return value;
}

const seedUsers = [
  {
    email: 'Aina@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_AINA_PASSWORD'),
    username: 'Aina',
    comment: 'Thanks for sharing this place. I would love to visit it!',
  },
  {
    email: 'Hafiz@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_HAFIZ_PASSWORD'),
    username: 'Hafiz',
    comment: 'The photos and travel details are really helpful.',
  },
  {
    email: 'MeiLin@gmail.com',
    password: requiredPassword('COMMUNITY_SEED_MEILIN_PASSWORD'),
    username: 'Mei Lin',
    comment: 'Adding this recommendation to my next trip plan.',
  },
] as const;

async function existingUsers(): Promise<User[]> {
  const users: User[] = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) return users;
  }
}

async function ensureUser(
  seed: (typeof seedUsers)[number],
  users: User[],
): Promise<User> {
  const existing = users.find(
    (user) => user.email?.toLowerCase() === seed.email.toLowerCase(),
  );
  if (existing) {
    console.log(`[existing user] ${seed.email}`);
    return existing;
  }

  const { data, error } = await supabase.auth.admin.createUser({
    email: seed.email,
    password: seed.password,
    email_confirm: true,
    user_metadata: {
      username: seed.username,
      full_name: seed.username,
      display_name: seed.username,
    },
  });
  if (error) throw error;
  console.log(`[created user] ${seed.email}`);
  users.push(data.user);
  return data.user;
}

async function main() {
  const users = await existingUsers();
  const { data: posts, error: postsError } = await supabase
    .from('community_posts')
    .select('id, title, author_id')
    .eq('moderation_status', 'approved')
    .order('created_at', { ascending: false })
    .limit(12);
  if (postsError) throw postsError;
  if (!posts || posts.length === 0) {
    console.log('No approved Community posts were found.');
    return;
  }

  let createdComments = 0;
  let existingComments = 0;
  let normalizedComments = 0;
  for (const seed of seedUsers) {
    const user = await ensureUser(seed, users);
    const userClient = createClient(supabaseUrl!, anonKey!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: signInError } = await userClient.auth.signInWithPassword({
      email: seed.email,
      password: seed.password,
    });
    if (signInError) {
      throw new Error(
        `Could not sign in ${seed.email}. The existing account password was not changed.`,
      );
    }
    for (const post of posts) {
      if (post.author_id === user.id) continue;
      const content = seed.comment;
      const legacyContent = `${seed.comment} (${post.title})`;
      const { data: matches, error: duplicateError } = await supabase
        .from('community_post_comments')
        .select('id, content')
        .eq('post_id', post.id)
        .eq('user_id', user.id)
        .in('content', [content, legacyContent]);
      if (duplicateError) throw duplicateError;
      const current = matches?.find((comment) => comment.content === content);
      const legacy = matches?.filter(
        (comment) => comment.content === legacyContent,
      );
      if (current) {
        if (legacy && legacy.length > 0) {
          const { error: cleanupError } = await supabase
            .from('community_post_comments')
            .delete()
            .in(
              'id',
              legacy.map((comment) => comment.id),
            );
          if (cleanupError) throw cleanupError;
        }
        existingComments += 1;
        continue;
      }
      if (legacy && legacy.length > 0) {
        const first = legacy[0]!;
        const extras = legacy.slice(1);
        const { error: normalizeError } = await supabase
          .from('community_post_comments')
          .update({ content, author_name: seed.username })
          .eq('id', first.id);
        if (normalizeError) throw normalizeError;
        if (extras.length > 0) {
          const { error: cleanupError } = await supabase
            .from('community_post_comments')
            .delete()
            .in(
              'id',
              extras.map((comment) => comment.id),
            );
          if (cleanupError) throw cleanupError;
        }
        normalizedComments += 1;
        continue;
      }

      const { data: insertedRows, error: insertError } = await userClient.rpc(
        'community_add_comment_v7',
        {
          p_post_id: post.id,
          p_content: content,
        },
      );
      if (insertError) throw insertError;
      const inserted = Array.isArray(insertedRows) ? insertedRows[0] : null;
      if (inserted?.id) {
        const { error: nameError } = await supabase
          .from('community_post_comments')
          .update({ author_name: seed.username })
          .eq('id', inserted.id);
        if (nameError) throw nameError;
      }
      createdComments += 1;
    }
    await userClient.auth.signOut();
  }

  console.log(
    `Seed complete: ${createdComments} comments created, ` +
      `${normalizedComments} bracketed comments normalized, ` +
      `${existingComments} duplicates skipped across ${posts.length} posts.`,
  );
}

await main();

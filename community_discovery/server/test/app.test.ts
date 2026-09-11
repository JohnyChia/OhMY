import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createApp } from '../src/app.js';

async function withServer(
  run: (baseUrl: string) => Promise<void>,
  database: SupabaseClient = {} as SupabaseClient,
) {
  const app = createApp({ database });
  const server = app.listen(0);
  await new Promise<void>((resolve) => server.once('listening', resolve));
  try {
    const address = server.address() as AddressInfo;
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

function fakeDatabase(options: { eligible?: boolean } = {}) {
  const rpcCalls: Array<{ name: string; params: Record<string, unknown> }> = [];
  const rows: Record<string, unknown[]> = {
    community_blocked_words: [{ term: 'fucking', active: true, language: 'en' }],
    community_moderation_allowlist: [],
    community_location_aliases: [
      { canonical_location: 'Kuala Lumpur', alias: 'KL', active: true },
    ],
    tags: [{ id: 13, name: 'Heritage', tag_type: 'cultural' }],
    community_location_tag_rules: [
      {
        tag_id: 13,
        location_pattern: 'Kwai Chai Hong',
        place_type: null,
        weight: 6,
        active: true,
      },
    ],
    community_nlp_settings: [
      { key: 'fallback_tag_name', value: 'Heritage' },
    ],
  };
  const resultFor = (table: string) => ({ data: rows[table] ?? [], error: null });
  const database = {
    auth: {
      getUser: async (token: string) => ({
        data: token === 'valid-jwt' ? { user: { id: 'user-1' } } : { user: null },
        error: token === 'valid-jwt' ? null : new Error('invalid token'),
      }),
    },
    from: (table: string) => {
      const query = {
        select: () => query,
        eq: async () => resultFor(table),
        then: (resolve: (value: unknown) => unknown) =>
          Promise.resolve(resolve(resultFor(table))),
      };
      return query;
    },
    rpc: async (name: string, params: Record<string, unknown>) => {
      rpcCalls.push({ name, params });
      if (name === 'community_validation_context_v5') {
        return {
          data: options.eligible === false
            ? { eligible: false, reason: 'Finish the trip before creating a post.' }
            : {
                eligible: true,
                reason: 'Trip is eligible.',
                destination: 'Kuala Lumpur',
                attraction: 'Kwai Chai Hong',
                history_entry_id: 'history-1',
              },
          error: null,
        };
      }
      if (name === 'community_create_post_v5') {
        return { data: 'post-1', error: null };
      }
      if (name === 'community_update_post_v5') {
        return { data: 'post-1', error: null };
      }
      return { data: null, error: new Error(`Unexpected RPC: ${name}`) };
    },
  } as unknown as SupabaseClient;
  return { database, rpcCalls };
}

function createPayload(overrides: Record<string, unknown> = {}) {
  return {
    historyEntryId: 'history-1',
    title: 'Morning at Kwai Chai Hong',
    description:
      'Kwai Chai Hong in Kuala Lumpur has colourful heritage lanes before breakfast.',
    imagePaths: ['user-1/post.jpg'],
    ...overrides,
  };
}

test('health endpoint is available without credentials', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
  });
});

test('community endpoints require a Supabase bearer token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(createPayload()),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json() as { code: string }).code, 'UNAUTHENTICATED');
  });
});

test('create post succeeds after text and trip validation', async () => {
  const fake = fakeDatabase();
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts`, {
      method: 'POST',
      headers: {
        authorization: 'Bearer valid-jwt',
        'content-type': 'application/json',
      },
      body: JSON.stringify(createPayload()),
    });
    assert.equal(response.status, 201);
    const body = await response.json() as {
      postId: string;
      detectedTags: Array<{ id: number }>;
    };
    assert.equal(body.postId, 'post-1');
    assert.deepEqual(body.detectedTags.map((tag) => tag.id), [13]);
    const createCall = fake.rpcCalls.find(
      (call) => call.name === 'community_create_post_v5',
    );
    assert.deepEqual(createCall?.params.p_tag_ids, [13]);
    assert.equal(createCall?.params.p_history_entry_id, 'history-1');
  }, fake.database);
});

test('owner edit uses the private v5 update RPC', async () => {
  const fake = fakeDatabase();
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts/post-1`, {
      method: 'PATCH',
      headers: {
        authorization: 'Bearer valid-jwt',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        title: 'Updated Kuala Lumpur walk',
        description: 'Kuala Lumpur was enjoyable and easy to explore on foot.',
        imagePaths: [],
      }),
    });
    assert.equal(response.status, 200);
    const updateCall = fake.rpcCalls.find(
      (call) => call.name === 'community_update_post_v5',
    );
    assert.equal(updateCall?.params.p_post_id, 'post-1');
  }, fake.database);
});

test('create post rejects missing pictures before database write', async () => {
  const fake = fakeDatabase();
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts`, {
      method: 'POST',
      headers: {
        authorization: 'Bearer valid-jwt',
        'content-type': 'application/json',
      },
      body: JSON.stringify(createPayload({ imagePaths: [] })),
    });
    assert.equal(response.status, 422);
    assert.equal((await response.json() as { code: string }).code, 'INVALID_IMAGES');
    assert.equal(
      fake.rpcCalls.some((call) => call.name === 'community_create_post_v5'),
      false,
    );
  }, fake.database);
});

test('create post rejects dirty language without calling the write RPC', async () => {
  const fake = fakeDatabase();
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts`, {
      method: 'POST',
      headers: {
        authorization: 'Bearer valid-jwt',
        'content-type': 'application/json',
      },
      body: JSON.stringify(createPayload({
        description: 'Kuala Lumpur was f u c k i n g awful during this visit.',
      })),
    });
    assert.equal(response.status, 422);
    assert.equal(
      (await response.json() as { code: string }).code,
      'INAPPROPRIATE_LANGUAGE',
    );
    assert.equal(
      fake.rpcCalls.some((call) => call.name === 'community_create_post_v5'),
      false,
    );
  }, fake.database);
});

test('create post rejects an unavailable or unowned history entry', async () => {
  const fake = fakeDatabase({ eligible: false });
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/community/posts`, {
      method: 'POST',
      headers: {
        authorization: 'Bearer valid-jwt',
        'content-type': 'application/json',
      },
      body: JSON.stringify(createPayload()),
    });
    assert.equal(response.status, 403);
    assert.equal(
      (await response.json() as { code: string }).code,
      'HISTORY_NOT_ELIGIBLE',
    );
  }, fake.database);
});

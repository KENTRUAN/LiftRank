import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { ref, set, get, remove } from 'firebase/database';

let env: RulesTestEnvironment;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-liftrank', database: { host: '127.0.0.1', port: 9000, rules: await readFile('database.rules.json', 'utf8') } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearDatabase(); });
const db = (uid: string) => env.authenticatedContext(uid).database();
async function seed(value: any) { await env.withSecurityRulesDisabled(async ctx => { await set(ref(ctx.database()), value); }); }
const lease = (roomId = 'demo-gym') => ({ roomId, sessionId: 'session-a', expiresAt: Date.now() + 90_000 });
const presence = () => ({ uid: 'a', sessionId: 'session-a', x: 2, y: 7, station: 'lounge', status: 'Resting', updatedAt: Date.now() });

test('room presence is private to active room members; clients cannot forge membership', async () => {
  await seed({ world: { memberships: { a: lease() }, rooms: { 'demo-gym': { presence: { a: presence() } } } } });
  await assertSucceeds(get(ref(db('a'), 'world/rooms/demo-gym/presence')));
  await assertFails(get(ref(db('b'), 'world/rooms/demo-gym/presence')));
  await assertFails(set(ref(db('b'), 'world/memberships/b'), lease()));
  await assertFails(get(ref(env.unauthenticatedContext().database(), 'profiles/a')));
});
test('movement only updates the authenticated member, validates session and bounds', async () => {
  await seed({ world: { memberships: { a: lease() } } });
  const path = 'world/rooms/demo-gym/presence/a';
  await assertSucceeds(set(ref(db('a'), path), presence()));
  for (const bad of [{ ...presence(), x: 100 }, { ...presence(), sessionId: 'old' }, { ...presence(), location: { lat: 10 } }, { ...presence(), uid: 'b' }]) {
    await assertFails(set(ref(db('a'), path), bad));
  }
  await assertFails(set(ref(db('b'), path), presence()));
  await assertSucceeds(remove(ref(db('a'), path)));
});
test('expired leases deny room reads and presence writes', async () => {
  await seed({ world: { memberships: { a: { ...lease(), expiresAt: Date.now() - 1 } } } });
  await assertFails(get(ref(db('a'), 'world/rooms/demo-gym/presence')));
  await assertFails(set(ref(db('a'), 'world/rooms/demo-gym/presence/a'), presence()));
  await assertFails(get(ref(db('a'), 'roomMessages/demo-gym')));
});
test('only chat members can read private messages; all social writes are server-only', async () => {
  await seed({ social: { chats: { pair: { members: { a: true, b: true }, messages: { one: { text: 'private' } } } } } });
  await assertSucceeds(get(ref(db('a'), 'social/chats/pair/messages')));
  await assertSucceeds(get(ref(db('b'), 'social/chats/pair/messages')));
  await assertFails(get(ref(db('c'), 'social/chats/pair/messages')));
  await assertFails(set(ref(db('c'), 'social/chats/pair/members/c'), true));
  await assertFails(set(ref(db('a'), 'social/friends/a/b'), { status: 'accepted' }));
  await assertFails(set(ref(db('a'), 'social/chats/pair/messages/two'), { text: 'forged' }));
  await assertFails(get(ref(db('a'), 'social')));
});
test('reports, quotas, and other members block lists are never readable by clients', async () => {
  await seed({ reports: { one: { text: 'private' } }, usage: { total: 1 }, social: { blocks: { a: { b: true } } } });
  await assertFails(get(ref(db('b'), 'social/blocks/a')));
  await assertSucceeds(get(ref(db('a'), 'social/blocks/a')));
  await assertFails(get(ref(db('a'), 'reports')));
  await assertFails(get(ref(db('a'), 'usage')));
});

test('profiles are readable only by self, a gym peer or an existing connection; blocks override', async () => {
  await seed({ profiles: { a: { name: 'A' }, b: { name: 'B' } }, world: { memberships: { a: lease(), b: lease() } } });
  await assertSucceeds(get(ref(db('a'), 'profiles/a')));
  await assertSucceeds(get(ref(db('a'), 'profiles/b')));
  await assertFails(get(ref(db('c'), 'profiles/b')));
  await assertFails(get(ref(db('a'), 'profiles')));
  await env.withSecurityRulesDisabled(async ctx => {
    await remove(ref(ctx.database(), 'world'));
    await set(ref(ctx.database(), 'social/friends/a/b'), { status: 'accepted' });
  });
  await assertSucceeds(get(ref(db('a'), 'profiles/b')));
  await env.withSecurityRulesDisabled(async ctx => { await set(ref(ctx.database(), 'social/blocks/b/a'), true); });
  await assertFails(get(ref(db('a'), 'profiles/b')));
});

test('chat availability is separate from workout state and must be boolean', async () => {
  await seed({ world: { memberships: { a: lease() } } });
  const path = 'world/rooms/demo-gym/presence/a';
  await assertSucceeds(set(ref(db('a'), path), { ...presence(), status: 'Ready', openToChat: false }));
  await assertSucceeds(set(ref(db('a'), path), { ...presence(), status: 'Training', openToChat: true }));
  await assertFails(set(ref(db('a'), path), { ...presence(), openToChat: 'yes' }));
});


test('anonymous profiles cannot be read by gym peers or friends; aliases own their presence', async () => {
  await seed({ profiles: { a: { name: 'Secret', visibility: 'anonymous' } },
    social: { friends: { b: { a: { status: 'accepted' } } } },
    world: { memberships: { a: { ...lease(), publicID: 'anon-random', visibility: 'anonymous' }, b: lease() } } });
  await assertSucceeds(get(ref(db('a'), 'profiles/a')));
  await assertFails(get(ref(db('b'), 'profiles/a')));
  await assertSucceeds(set(ref(db('a'), 'world/rooms/demo-gym/presence/anon-random'), { ...presence(), uid: 'anon-random', visibility: 'anonymous' }));
  await assertFails(set(ref(db('a'), 'world/rooms/demo-gym/presence/anon-random'), { ...presence(), uid: 'anon-random' }));
  await assertFails(set(ref(db('a'), 'world/rooms/demo-gym/presence/a'), presence()));
  await assertFails(set(ref(db('a'), 'world/rooms/demo-gym/presence/anon-random'), { ...presence(), uid: 'anon-random', visibility: 'public' }));
});
test('clients cannot occupy or approve equipment directly and cannot publish an unreserved station', async () => {
  await seed({ world: { memberships: { a: lease(), b: lease() }, rooms: { 'demo-gym': { equipment: { bench: { ownerID: 'a', members: { a: 'session-a' } } } } } } });
  await assertSucceeds(set(ref(db('a'), 'world/rooms/demo-gym/presence/a'), { ...presence(), station: 'bench' }));
  await assertFails(set(ref(db('b'), 'world/rooms/demo-gym/presence/b'), { ...presence(), uid: 'b', station: 'bench' }));
  await assertFails(set(ref(db('b'), 'world/rooms/demo-gym/equipment/bench/members/b'), 'session-a'));
  await assertFails(remove(ref(db('b'), 'world/rooms/demo-gym/equipment/bench/members/a')));
  await assertSucceeds(remove(ref(db('a'), 'world/rooms/demo-gym/equipment/bench/members/a')));
});

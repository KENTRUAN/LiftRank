import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { Server } from 'node:http';
import { getDatabase } from 'firebase-admin/database';

process.env.NODE_ENV = 'test';
process.env.GOOGLE_CLOUD_PROJECT = 'demo-liftrank';
let server: Server;
let base: string;
type Guest = { uid: string; token: string };
let a: Guest, b: Guest, c: Guest;
async function guest(): Promise<Guest> {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const value = await response.json() as any;
  assert.equal(response.status, 200);
  return { uid: value.localId, token: value.idToken };
}
async function post(user: Guest, path: string, body: any = {}, expected = 200): Promise<any> {
  const response = await fetch(`${base}/${path}`, { method: 'POST', headers: { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const result = await response.json();
  assert.equal(response.status, expected, JSON.stringify(result));
  return result;
}
before(async () => {
  const { app } = await import('../src/server.js');
  await getDatabase().ref().remove();
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address() as { port: number };
  base = `http://127.0.0.1:${address.port}`;
  [a, b, c] = await Promise.all([guest(), guest(), guest()]);
  for (const [index, user] of [a, b, c].entries()) await post(user, 'profile', { name: `Lifter ${index}`, gsr: 500, interests: 'Strength' });
});
after(async () => { server?.closeAllConnections(); await new Promise<void>(resolve => server?.close(() => resolve())); getDatabase().goOffline(); });

const near = () => ({ latitude: 35.995, longitude: -78.94, accuracy: 20, timestamp: Date.now() });
async function spaceGuest(name: string) {
  const user = await guest(); await post(user, 'profile', { name }); return user;
}

test('two guests share Demo Gym, stale sessions cannot renew or leave the replacement session', async () => {
  const first = await post(a, 'rooms/join', { roomId: 'demo-gym' });
  const second = await post(b, 'rooms/join', { roomId: 'demo-gym' });
  assert.equal(first.roomId, second.roomId);
  const replacement = await post(a, 'rooms/join', { roomId: 'demo-gym' });
  await post(a, 'rooms/renew', { sessionId: first.sessionId }, 403);
  await post(a, 'rooms/leave', { sessionId: first.sessionId });
  const renewed = await post(a, 'rooms/renew', { sessionId: replacement.sessionId });
  assert.equal(renewed.sessionId, replacement.sessionId);
});
test('friend acceptance, private messages, duplicate retries and blocking run through authenticated API', async () => {
  await post(a, `messages/private/${b.uid}`, { id: 'before', text: 'not yet' }, 403);
  await post(a, `friends/${b.uid}/request`, {}, 403);
  for (const user of [a, b]) {
    const lease = (await getDatabase().ref(`world/access/memberships/${user.uid}`).get()).val();
    await getDatabase().ref(`world/rooms/demo-gym/presence/${user.uid}`).set({ uid: user.uid, sessionId: lease.sessionId, x: 2, y: 7, station: 'lounge', status: 'Ready', openToChat: true, updatedAt: Date.now() });
  }
  await post(c, `friends/${b.uid}/request`, {}, 403);
  await post(a, `friends/${b.uid}/request`);
  await post(a, `friends/${b.uid}/accept`, {}, 409);
  const accepted = await post(b, `friends/${a.uid}/accept`);
  const bLease = (await getDatabase().ref(`world/access/memberships/${b.uid}`).get()).val();
  await post(b, 'rooms/leave', { sessionId: bLease.sessionId });
  await post(a, `messages/private/${b.uid}`, { id: 'hello', text: 'Want to train?' });
  await post(a, `messages/private/${b.uid}`, { id: 'hello', text: 'Want to train?' });
  await post(c, `messages/private/${b.uid}`, { id: 'third', text: 'not authorized' }, 403);
  const messages = (await getDatabase().ref(`social/chats/${accepted.conversationId}/messages`).get()).val();
  assert.equal(Object.keys(messages).length, 1);
  await post(b, 'reports', { targetID: a.uid, messageID: 'hello', reason: 'Integration test' });
  await post(b, `friends/${a.uid}/block`);
  await post(a, `messages/private/${b.uid}`, { id: 'blocked', text: 'not authorized' }, 403);
  assert.equal((await getDatabase().ref(`social/chats/${accepted.conversationId}`).get()).exists(), false);
});
test('room chat requires membership and authenticated identity', async () => {
  await post(a, 'messages/room/demo-gym', { id: 'room-message', text: 'Hello room' });
  await post(c, 'messages/room/demo-gym', { id: 'outsider', text: 'no membership' }, 403);
  await post({ uid: 'invalid', token: 'invalid' }, 'rooms/join', { roomId: 'demo-gym' }, 401);
});

test('equipment is exclusive until a work-in is accepted; anonymous mode hides identity and prevents requests', async () => {
  for (const user of [a, b, c]) {
    const lease = await post(user, 'rooms/join', { roomId: 'demo-gym' });
    await getDatabase().ref(`world/rooms/demo-gym/presence/${lease.publicID}`).set({ uid: lease.publicID, sessionId: lease.sessionId, updatedAt: Date.now(), x: 2, y: 7, station: 'lounge', status: 'Ready' });
  }
  await post(a, 'equipment/bench/claim');
  await post(b, 'equipment/bench/claim', {}, 409);
  await post(b, 'equipment/bench/request', { mode: 'together' });
  await post(c, 'equipment/bench/accept', { targetID: b.uid }, 403);
  await post(a, 'equipment/bench/accept', { targetID: b.uid });
  const occupied = (await getDatabase().ref('world/rooms/demo-gym/equipment/bench/members').get()).val();
  assert.equal(Object.keys(occupied).length, 2);
  await post(b, 'equipment/bench/release');
  await post(b, 'equipment/cardio/claim');
  await post(c, 'equipment/cardio/request', {}, 409);
  await post(c, 'profile', { name: 'Anonymous QA', gsr: 600, visibility: 'anonymous' });
  const anon = await post(c, 'rooms/join', { roomId: 'demo-gym' });
  assert.notEqual(anon.publicID, c.uid);
  assert.ok(anon.publicID.startsWith('anon-'));
  await post(c, `friends/${a.uid}/request`, {}, 403);
  await post(a, `friends/${c.uid}/request`, {}, 403);
});

test('concurrent admission allows exactly ten guests with distinct spawn cells', async () => {
  await getDatabase().ref('world').remove();
  const guests = await Promise.all(Array.from({ length: 11 }, () => guest()));
  await Promise.all(guests.map((user, index) => post(user, 'profile', { name: `Capacity guest ${index}`, gsr: 0 })));
  const results = await Promise.all(guests.map(async user => {
    const response = await fetch(`${base}/rooms/join`, {
      method: 'POST', headers: { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ roomId: 'demo-gym' }),
    });
    return { status: response.status, body: await response.json() as any };
  }));
  assert.equal(results.filter(r => r.status === 200).length, 10, JSON.stringify(results));
  assert.equal(results.filter(r => r.status === 409).length, 1);
  assert.equal(new Set(results.filter(r => r.status === 200).map(r => `${r.body.spawnX},${r.body.spawnY}`)).size, 10);
});

test('authenticated AI routes separate provider quotas and block social drafts before external calls', async () => {
  const oldFetch=globalThis.fetch, oldEnv={...process.env};
  let genericCalls=0, trainerCalls=0;
  process.env.TINKER_API_KEY='integration-training-key';process.env.GEMINI_API_KEY='integration-general-key';
  delete process.env.TINKER_REQUIRE_FINE_TUNED;
  globalThis.fetch=async(input,init)=>{
    const host=new URL(String(input)).hostname;
    if(host==='generativelanguage.googleapis.com'){
      genericCalls++;assert.equal(new Headers(init?.headers).get('x-goog-api-key'),'integration-general-key');
      return Response.json({candidates:[{content:{parts:[{text:'Hi, let’s talk about lifting.'}]}}]});
    }
    if(host==='tinker.thinkingmachines.dev'){
      trainerCalls++;assert.equal(new Headers(init?.headers).get('x-api-key'),'integration-training-key');
      return Response.json({content:[{type:'tool_use',name:'reply_to_lifter',input:{reply:'Hello lifter.',todoAction:'keep',todos:null,schedule:[]}}]});
    }
    return oldFetch(input,init);
  };
  try{
    // The preceding capacity test fills the room; isolate this emulator scenario.
    await getDatabase().ref('world').remove();
    const d=await guest(),e=await guest();
    for(const user of [d,e]){await post(user,'profile',{name:'AI route test',interests:'Lifting'});await post(user,'rooms/join',{roomId:'demo-gym'});}
    const draft=await post(d,'companion',{targetID:e.uid,messages:[{role:'user',text:'introduce me'}]});
    assert.equal(draft.reply,'Hi, let’s talk about lifting.');
    const training={catalog:[{key:'deadlift',name:'Deadlift',cardio:false}],localDate:'2026-11-07',messages:[{role:'user',text:'Hi'}]};
    await post(d,'trainer',training);
    const usage=(await getDatabase().ref(`usage/${new Date().toISOString().slice(0,10)}`).get()).val();
    assert.equal(usage.generalAI.users[d.uid],1);assert.equal(usage.companion.users[d.uid],1);
    process.env.GENERAL_AI_GLOBAL_LIMIT='0';
    await post(d,'companion',{targetID:e.uid,messages:[{role:'user',text:'intro'}]},429);
    await post(d,'trainer',training);assert.equal(genericCalls,1);assert.equal(trainerCalls,2);
    await post(e,`friends/${d.uid}/block`);
    await post(d,'companion',{targetID:e.uid,messages:[{role:'user',text:'intro'}]},403);
    assert.equal(genericCalls,1);
  }finally{globalThis.fetch=oldFetch;process.env=oldEnv;}
});

test('nearby public spaces require approval, hide coordinates, and survive the creator leaving', async () => {
  const owner = await spaceGuest('Space owner'), member = await spaceGuest('Space member'), outsider = await spaceGuest('Space outsider');
  const created = await post(owner, 'spaces/create', { name: 'Open floor', visibility: 'public', location: near() });
  const id = created.gym.id;
  const found = await post(member, 'spaces/nearby', { location: near() });
  assert.ok(found.spaces.some((s: any) => s.id === id));
  assert.equal(JSON.stringify(found.spaces).includes('latitude'), false);
  assert.equal(JSON.stringify(found).includes(owner.uid), false);
  await post(member, 'rooms/join', { roomId: id, location: near() }, 403);
  await post(member, `spaces/${id}/request`, { location: near() });
  const request = (await post(owner, 'spaces/inbox')).requests.find((r: any) => r.roomId === id);
  await post(outsider, `spaces/${id}/respond`, { requestID: request.id, action: 'accept' }, 403);
  await post(owner, `spaces/${id}/respond`, { requestID: request.id, action: 'accept' });
  await post(member, 'rooms/join', { roomId: id, location: { ...near(), latitude: 40 } }, 403);
  const lease = await post(member, 'rooms/join', { roomId: id, location: near() });
  await post(outsider, `spaces/${id}/request`, { location: near() });
  const next = (await post(member, 'spaces/inbox')).requests.find((r: any) => r.roomId === id);
  // A member can approve even while the creator is still there.
  await post(member, `spaces/${id}/respond`, { requestID: next.id, action: 'accept' });
  await post(owner, 'rooms/leave', { sessionId: created.membership.sessionId });
  assert.equal((await post(member, 'spaces/inbox')).room.isHost, true);
  const second = await post(outsider, 'rooms/join', { roomId: id, location: near() });
  await post(member, 'rooms/leave', { sessionId: lease.sessionId });
  assert.equal((await post(outsider, 'spaces/inbox')).room.id, id);
  await post(outsider, 'rooms/leave', { sessionId: second.sessionId });
  await post(member, 'rooms/join', { roomId: id, location: near() }, 404);
  assert.equal((await getDatabase().ref(`world/access/spaces/${id}`).get()).exists(), false);
});

test('private spaces only admit invited nearby friends and never appear in discovery', async () => {
  const owner = await spaceGuest('Private owner'), friend = await spaceGuest('Invited friend'), stranger = await spaceGuest('Stranger');
  const { gym } = await post(owner, 'spaces/create', { name: 'Private floor', visibility: 'private', location: near() });
  const id = gym.id;
  assert.ok(!(await post(friend, 'spaces/nearby', { location: near() })).spaces.some((s: any) => s.id === id));
  await post(friend, `spaces/${id}/request`, { location: near() }, 403);
  await post(friend, 'rooms/join', { roomId: id, location: near() }, 403);
  await post(owner, `spaces/${id}/invite`, { targetID: stranger.uid }, 403);
  for (const [a, b] of [[owner, friend], [friend, owner]]) await getDatabase().ref(`social/friends/${a!.uid}/${b!.uid}`).set({ uid: b!.uid, status: 'accepted', updatedAt: Date.now() });
  await post(owner, `spaces/${id}/invite`, { targetID: friend.uid });
  assert.equal((await post(friend, 'spaces/inbox')).invitations[0].gym.id, id);
  assert.equal((await post(stranger, 'spaces/inbox')).invitations.length, 0);
  await post(stranger, `spaces/${id}/visibility`, { visibility: 'public' }, 403);
  await post(friend, 'rooms/join', { roomId: id, location: { ...near(), accuracy: 101 } }, 400);
  await post(friend, 'rooms/join', { roomId: id, location: { ...near(), timestamp: Date.now() - 61_000 } }, 400);
  await post(friend, 'rooms/join', { roomId: id }, 400);
  await post(friend, 'rooms/join', { roomId: id, location: near() });
  await post(friend, 'equipment/bench/claim', {}, 400);
});

test('privacy changes revoke public approvals; blocks prevent requests, invitations and admission', async () => {
  const owner = await spaceGuest('Privacy owner'), joiner = await spaceGuest('Privacy joiner');
  const { gym } = await post(owner, 'spaces/create', { name: 'Changing space', visibility: 'public', location: near() });
  await post(joiner, `spaces/${gym.id}/request`, { location: near() });
  const request = (await post(owner, 'spaces/inbox')).requests.find((r: any) => r.roomId === gym.id);
  await post(owner, `spaces/${gym.id}/respond`, { requestID: request.id, action: 'accept' });
  await post(owner, `spaces/${gym.id}/visibility`, { visibility: 'private' });
  await post(joiner, 'rooms/join', { roomId: gym.id, location: near() }, 403);
  await post(owner, `spaces/${gym.id}/visibility`, { visibility: 'public' });
  await post(owner, `friends/${joiner.uid}/block`);
  assert.ok(!(await post(joiner, 'spaces/nearby', { location: near() })).spaces.some((s: any) => s.id === gym.id));
  await post(joiner, `spaces/${gym.id}/request`, { location: near() }, 403);
  await post(owner, `spaces/${gym.id}/invite`, { targetID: joiner.uid }, 403);
  await post(joiner, 'rooms/join', { roomId: gym.id, location: near() }, 403);
  await post(owner, 'spaces/registered-not-a-space/visibility', { visibility: 'private' }, 404);
});

test('creation requires a precise fresh location; expired members do not keep a space alive', async () => {
  const owner = await spaceGuest('Expiry owner');
  const input = { name: 'Temporary space', visibility: 'public' };
  for (const location of [null, { ...near(), accuracy: 500 }, { ...near(), timestamp: Date.now() - 61_000 }]) {
    await post(owner, 'spaces/create', { ...input, location }, 400);
  }
  const { gym } = await post(owner, 'spaces/create', { ...input, location: near() });
  await getDatabase().ref(`world/access/memberships/${owner.uid}/expiresAt`).set(Date.now() - 1);
  assert.ok(!(await post(owner, 'spaces/nearby', { location: near() })).spaces.some((s: any) => s.id === gym.id));
  assert.equal((await getDatabase().ref(`world/access/spaces/${gym.id}`).get()).exists(), false);
});

test('Wilson preset is public and requires a fresh nearby check-in without Places', async () => {
  const user = await spaceGuest('Wilson visitor');
  const point = { ...near(), latitude: 35.997085, longitude: -78.940951 };
  const result = await post(user, 'spaces/nearby', { location: point });
  const gym = result.gyms.find((g: any) => g.id === 'registered-duke-wilson');
  assert.equal(gym.name, 'Duke Wilson Recreation Center'); assert.equal(gym.visibility, 'public');
  await post(user, 'rooms/join', { roomId: gym.id, location: { ...point, latitude: 36.1 } }, 403);
  await post(user, 'rooms/join', { roomId: gym.id, location: { ...point, accuracy: 101 } }, 400);
  await post(user, 'rooms/join', { roomId: gym.id, location: { ...point, timestamp: Date.now() - 61000 } }, 400);
  const joined = await post(user, 'rooms/join', { roomId: gym.id, location: point });
  assert.equal(joined.roomId, gym.id);
  await post(user, `spaces/${gym.id}/visibility`, { visibility: 'private' }, 404);
});

test('home greeting uses the workout model without changing workouts or generating a plan', async () => {
  const oldFetch = globalThis.fetch, oldEnv = { ...process.env };
  process.env.TINKER_API_KEY = 'test-only-key'; delete process.env.TINKER_REQUIRE_FINE_TUNED;
  let calls = 0;
  globalThis.fetch = async (input, init) => {
    if (new URL(String(input)).hostname === 'tinker.thinkingmachines.dev') {
      calls++; const body = JSON.parse(String(init?.body)); assert.ok(body.system.includes('3 sets completed'));
      return Response.json({ content: [{ type: 'tool_use', name: 'reply_to_lifter', input: {
        reply: 'Three sets down. Take a steady rest before the next one.', todoAction: 'keep', todos: null, schedule: []
      } }] });
    }
    return oldFetch(input, init);
  };
  try {
    const user = await spaceGuest('Welcome reader');
    const welcome = await post(user, 'trainer/greeting', { localDate: '2026-11-07', language: 'en', status: 'Strength, 3 sets completed', plan: 'No requested plan today' });
    assert.deepEqual(Object.keys(welcome), ['reply']); assert.ok(welcome.reply.includes('Three sets')); assert.equal(calls, 1);
    assert.equal((await getDatabase().ref(`world/access/memberships/${user.uid}`).get()).exists(), false);
    process.env.GREETING_GLOBAL_LIMIT = '0';
    await post(user, 'trainer/greeting', { localDate: '2026-11-07', status: 'No active workout', plan: 'No plan' }, 429);
    assert.equal(calls, 1);
  } finally { globalThis.fetch = oldFetch; process.env = oldEnv; }
});

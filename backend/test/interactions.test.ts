import test from 'node:test';
import assert from 'node:assert/strict';
import { equipmentAction, cleanEquipment } from '../src/equipment.js';
import { cleanProfile, joinWorld, validateGymEncounter } from '../src/core.js';
import { cleanTrainerReply, validatedTrainerReply, trainerResponseSchema } from '../src/trainer.js';
const now = Date.now();
const lease = { roomId: 'demo-gym', sessionId: 'a-session', expiresAt: now + 90000 };
const present = Object.fromEntries(['a', 'b', 'c'].map(uid => [uid, { uid, sessionId: `${uid}-session`, updatedAt: now }]));
const act = (state: any, uid: string, station: string, action: string, target?: string) => equipmentAction(state, present, uid, { ...lease, sessionId: `${uid}-session` }, station, action, target, 'workIn', now);

test('occupied lifting equipment requires explicit owner acceptance; cardio never permits sharing', () => {
  let state = act(null, 'a', 'bench', 'claim');
  assert.throws(() => act(state, 'b', 'bench', 'claim'));
  state = act(state, 'b', 'bench', 'request');
  assert.equal(state.bench?.members.b, undefined);
  assert.throws(() => act(state, 'c', 'bench', 'accept', 'b'));
  state = act(state, 'a', 'bench', 'accept', 'b');
  assert.equal(state.bench?.members.b, 'b-session');
  assert.throws(() => act(state, 'c', 'bench', 'request'));
  assert.throws(() => act(state, 'a', 'rack', 'claim'));
  state = act(state, 'b', 'bench', 'release');
  state = act(state, 'b', 'cardio', 'claim');
  assert.throws(() => act(state, 'c', 'cardio', 'request'));
});
test('disconnect cleanup releases equipment, promotes remaining partner, expires work-in requests', () => {
  let state = act(null, 'a', 'bench', 'claim');
  state = act(state, 'b', 'bench', 'request');
  state = act(state, 'a', 'bench', 'accept', 'b');
  let clean = cleanEquipment(state, { b: present.b }, now);
  assert.equal(clean.bench?.ownerID, 'b');
  assert.deepEqual(Object.keys(clean.bench!.members), ['b']);
  assert.deepEqual(cleanEquipment(state, {}, now), {});
  state = act(null, 'a', 'rack', 'claim'); state = act(state, 'b', 'rack', 'request');
  clean = cleanEquipment(state, present, now + 60001);
  assert.deepEqual(clean, {});
});
test('anonymous room identities cannot exchange friend requests and background refresh preserves anonymity', () => {
  let world = joinWorld(null, 'a', 'demo-gym', 'a-session', now);
  world = joinWorld(world, 'b', 'demo-gym', 'b-session', now);
  world.memberships.a!.publicID = 'anon-secret'; world.memberships.a!.visibility = 'anonymous';
  world.rooms['demo-gym']!.presence = { 'anon-secret': present.a, b: present.b } as any;
  assert.throws(() => validateGymEncounter(world, 'a', 'b', now));
  const profile = cleanProfile('a', { name: 'Private identity', gsr: 500, visibility: 'anonymous' });
  assert.equal(cleanProfile('a', { snapshotOnly: true, visibility: 'public', gsr: 600 }, profile).visibility, 'anonymous');
});
test('trainer accepts empty todo deletion and full-week schedules, rejects unknown exercises and malformed output', () => {
  const item = { exerciseKey: 'bench_press', sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90 };
  const result = cleanTrainerReply(JSON.stringify({ reply: 'Your week', todos: [], schedule: Array.from({ length: 7 }, (_, dayOffset) => ({ dayOffset, title: 'Workout', items: [item] })) }), new Set(['bench_press']));
  assert.deepEqual(result.todos, []); assert.equal(result.schedule.length, 7);
  assert.throws(() => cleanTrainerReply(JSON.stringify({ reply: 'Bad', todos: [{ ...item, exerciseKey: 'made-up' }] }), new Set(['bench_press'])));
  assert.throws(() => cleanTrainerReply('not json', new Set()));
  assert.throws(() => cleanTrainerReply(JSON.stringify({ reply: 'Bad', todos: [{ ...item, sets: 0 }] }), new Set(['bench_press'])), /No changes were applied/);
  assert.throws(() => cleanTrainerReply(JSON.stringify({ reply: 'Bad', todos: [{ ...item, sets: -1 }] }), new Set(['bench_press'])));
});

test('trainer chats need no plan; numeric transport strings normalize without accepting unsafe values', () => {
  assert.deepEqual(cleanTrainerReply({ reply: 'Hello!', todos: null, schedule: [] }, new Set()), { reply: 'Hello!', todos: null, schedule: [] });
  const item = { exerciseKey: 'bench_press', sets: '3', repsLow: '8', restSeconds: '90' };
  const result = cleanTrainerReply({ reply: 'Plan', todos: [item] }, new Set(['bench_press']));
  assert.equal(result.todos![0]!.repsHigh, 8);
  for (const sets of [false, null, '', 0, 1.5, 11]) assert.throws(() => cleanTrainerReply({ reply: 'Bad', todos: [{ ...item, sets }] }, new Set(['bench_press'])));
  assert.equal(trainerResponseSchema(['bench_press']).properties.todos.anyOf.length, 2);
  assert.deepEqual(cleanTrainerReply({ reply: 'Clear', todoAction: 'clear', todos: null, schedule: [] }, new Set()).todos, []);
  assert.throws(() => cleanTrainerReply({ reply: 'Bad', todoAction: 'replace', todos: null }, new Set()));
  assert.throws(() => cleanTrainerReply({ reply: 'Bad', todoAction: 'keep', todos: [item] }, new Set(['bench_press'])));
});
test('trainer repairs invalid output once, charges each attempt, and never applies partial results', async () => {
  let calls = 0, charges = 0;
  const result = await validatedTrainerReply(new Set(), async repair => {
    calls++;
    if (calls === 1) return 'bad json';
    assert.match(repair!, /invalid JSON/);
    return { reply: 'Hello', todos: null, schedule: [] };
  }, async () => { charges++; });
  assert.equal(result.reply, 'Hello'); assert.equal(calls, 2); assert.equal(charges, 2);
  calls = 0;
  await assert.rejects(validatedTrainerReply(new Set(), async () => { calls++; return null; }, async () => {}), /workout is unchanged/);
  assert.equal(calls, 2);
});
test('session policy prevents cardio and missing-session todo edits before any reply reaches the app', async () => {
  let calls=0;
  const item={exerciseKey:'deadlift',sets:3,repsLow:8,repsHigh:12,restSeconds:90};
  const result=await validatedTrainerReply(new Set(['deadlift']),async repair=>{
    calls++;
    if(!repair)return {reply:'Plan',todoAction:'replace',todos:[item],schedule:[]};
    assert.match(repair,/cannot edit current-workout todos/);
    return {reply:'Use a separate strength session.',todoAction:'keep',todos:null,schedule:[]};
  },async()=>{},{allowsTodoEditing:false});
  assert.equal(calls,2);assert.equal(result.todos,null);
  await assert.rejects(validatedTrainerReply(new Set(['deadlift']),async()=>({reply:'Clear',todoAction:'clear',todos:[],schedule:[]}),async()=>{},{allowsTodoEditing:false}),/workout is unchanged/);
});

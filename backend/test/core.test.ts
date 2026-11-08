import test from 'node:test';
import assert from 'node:assert/strict';
import { appendPrivateMessage, cleanProfile, friendshipAction, joinWorld, pairKey, validateCheckIn, validateGymEncounter } from '../src/core.js';

const now = 1_800_000_000_000;
const gym = { latitude: 40, longitude: -74 };
test('check-in accepts nearby fresh location and rejects inaccurate, stale, distant and absent locations', () => {
  const valid = { ...gym, accuracy: 20, timestamp: now };
  assert.doesNotThrow(() => validateCheckIn(valid, gym, now));
  for (const bad of [undefined, { ...valid, accuracy: 101 }, { ...valid, timestamp: now - 60_001 }, { ...valid, latitude: 41 }, { ...valid, timestamp: now + 10_000 }, { ...valid, latitude: NaN }]) {
    assert.throws(() => validateCheckIn(bad, gym, now));
  }
});
test('room switching removes the previous presence, capacity counts leases, expired slots recover', () => {
  let world = joinWorld(null, 'a', 'first', 's1', now);
  world = joinWorld(world, 'a', 'second', 's2', now);
  assert.equal(world.rooms.first?.presence.a, undefined);
  assert.equal(world.memberships.a?.roomId, 'second');
  for (let i = 0; i < 9; i++) world = joinWorld(world, `u${i}`, 'second', `s${i}`, now);
  assert.equal(new Set(Object.values(world.memberships).map(m => `${m.spawnX},${m.spawnY}`)).size, 10);
  assert.throws(() => joinWorld(world, 'extra', 'second', 'extra', now));
  world.memberships.returning = { roomId: 'second', sessionId: 'expired', expiresAt: now - 1 };
  assert.throws(() => joinWorld(world, 'returning', 'second', 'new-session', now));
  assert.doesNotThrow(() => joinWorld(world, 'a', 'second', 'replacement', now));
  assert.doesNotThrow(() => joinWorld(world, 'extra', 'second', 'extra', now + 100_000));
});
test('friend request lifecycle and duplicate requests enforce direction', () => {
  let social = friendshipAction(null, 'a', 'b', 'request', now);
  assert.equal(social.friends.b?.a?.status, 'incoming');
  assert.throws(() => friendshipAction(social, 'a', 'b', 'accept', now));
  assert.throws(() => friendshipAction(social, 'b', 'a', 'request', now));
  social = friendshipAction(social, 'b', 'a', 'accept', now);
  assert.equal(social.friends.a?.b?.status, 'accepted');
  social = friendshipAction(social, 'a', 'b', 'remove', now);
  assert.equal(social.chats[pairKey('a', 'b')], undefined);
});
test('only friends message, retries deduplicate, blocking deletes conversation and prevents messages', () => {
  const message = { id: 'one', senderID: 'a', text: 'Hello', createdAt: now };
  assert.throws(() => appendPrivateMessage(null, 'a', 'b', message));
  let social = friendshipAction(null, 'a', 'b', 'request', now);
  social = friendshipAction(social, 'b', 'a', 'accept', now);
  social = appendPrivateMessage(social, 'a', 'b', message);
  social = appendPrivateMessage(social, 'a', 'b', message);
  assert.equal(Object.keys(social.chats[pairKey('a', 'b')]!.messages).length, 1);
  social = friendshipAction(social, 'b', 'a', 'block', now);
  assert.equal(social.chats[pairKey('a', 'b')], undefined);
  assert.throws(() => appendPrivateMessage(social, 'a', 'b', message));
  assert.throws(() => friendshipAction(social, 'a', 'b', 'request', now));
});
test('profile publishing excludes private health fields and unapproved asset paths', () => {
  const p = cleanProfile('a', { name: 'Lifter', bodyweightKg: 80, birthYear: 1995, gsr: 600, avatar: { assetPath: 'someone-else' } });
  assert.equal('bodyweightKg' in p, false);
  assert.equal('birthYear' in p, false);
  assert.equal(p.avatar.assetPath, undefined);
});

test('friend discovery requires fresh simultaneous presence in the same gym', () => {
  let world = joinWorld(null, 'a', 'demo-gym', 'a-session', now);
  world = joinWorld(world, 'b', 'demo-gym', 'b-session', now);
  assert.throws(() => validateGymEncounter(world, 'a', 'b', now));
  for (const uid of ['a', 'b']) world.rooms['demo-gym']!.presence[uid] = { uid, sessionId: `${uid}-session`, x: 2, y: 7, station: 'bench', status: 'Ready', updatedAt: now };
  assert.doesNotThrow(() => validateGymEncounter(world, 'a', 'b', now));
  assert.throws(() => validateGymEncounter(world, 'a', 'stranger-account-id', now));
  assert.throws(() => validateGymEncounter(world, 'a', 'b', now + 45_001));
  world.memberships.b!.sessionId = 'replacement';
  assert.throws(() => validateGymEncounter(world, 'a', 'b', now));
  world.memberships.b!.sessionId = 'b-session';
  world.memberships.b!.roomId = 'other-gym';
  assert.throws(() => validateGymEncounter(world, 'a', 'b', now));
});

test('profile highlights and public routines strip nested health details and respect opt-out', () => {
  const value = { name: 'Local lifter', gsr: 600, muscleRanks: { chest: 600, weightKg: 90 }, shareActivity: true,
    highlights: { workoutCount: 2, streakDays: 1, weekMuscles: { chest: 500, bodyFat: 20 }, notes: 'private',
      memories: [{ id: 'workout-1', date: Date.now(), title: 'Strength', minutes: 30, sets: 3, score: 600, weightKg: 90, notes: 'private' }], months: [] },
    routines: [{ id: 'routine-0', name: 'Push', notes: 'private', exercises: [{ name: 'Bench', sets: 3, repsLow: 8, repsHigh: 12, weightKg: 90 }] }] };
  const shared = cleanProfile('a', value);
  const json = JSON.stringify(shared);
  for (const key of ['weightKg', 'bodyFat', 'notes', 'private']) assert.equal(json.includes(key), false);
  assert.equal(shared.highlights?.workoutCount, 2);
  const withdrawn = cleanProfile('a', { ...value, gsr: 0, shareActivity: false, routines: [] }, shared);
  assert.equal(withdrawn.highlights, undefined);
  assert.deepEqual(withdrawn.muscleRanks, {});
  assert.deepEqual(withdrawn.routines, []);
});

test('background snapshot refresh cannot revert sharing consent or publish unselected routines', () => {
  const profile = cleanProfile('a', { name: 'Current name', gsr: 500, shareRank: true, shareActivity: true });
  const refreshed = cleanProfile('a', { snapshotOnly: true, name: 'Stale name', shareRank: false, shareActivity: false, gsr: 600,
    routines: [{ id: 'unselected', name: 'Private', exercises: [{ name: 'Bench', sets: 3, repsLow: 8, repsHigh: 12 }] }] }, profile);
  assert.equal(refreshed.name, 'Current name');
  assert.equal(refreshed.shareActivity, true);
  assert.equal(refreshed.shareRank, true);
  assert.equal(refreshed.gsr, 600);
  assert.deepEqual(refreshed.routines, []);
});

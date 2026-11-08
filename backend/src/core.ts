import { createHash } from 'node:crypto';

export class APIError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const DEMO_ROOM = 'demo-gym';
export const LEASE_MS = 90_000;
export const STALE_MS = 45_000;
export const stations = ['lounge', 'bench', 'rack', 'cardio', 'platform'] as const;
export const statuses = ['Ready', 'Training', 'Resting'] as const;
export function text(value: unknown, max: number, field = 'Text'): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) {
    throw new APIError(400, `${field} must contain 1–${max} characters.`);
  }
  return value.trim();
}
export function finite(value: unknown, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new APIError(400, 'Invalid numeric value.');
  }
  return value;
}
export function key(value: unknown): string {
  const s = text(value, 160, 'Identifier');
  if (!/^[a-zA-Z0-9_-]+$/.test(s)) throw new APIError(400, 'Invalid identifier.');
  return s;
}
export const roomKey = (placeID: string) => createHash('sha256').update(placeID).digest('hex').slice(0, 32);
export const pairKey = (a: string, b: string) => createHash('sha256').update([a, b].sort().join('\0')).digest('hex');
export interface Location { latitude: number; longitude: number; accuracy: number; timestamp: number }
export function location(value: any, now = Date.now(), checkFresh = true): Location {
  if (!value) throw new APIError(400, 'A fresh, precise location is required to check in.');
  const result = {
    latitude: finite(value.latitude, -90, 90), longitude: finite(value.longitude, -180, 180),
    accuracy: finite(value.accuracy, 0, checkFresh ? 100 : 100_000),
    timestamp: finite(value.timestamp, 0, now + 5_000),
  };
  if (checkFresh && now - result.timestamp > 60_000) throw new APIError(400, 'Location is older than 60 seconds. Try again.');
  return result;
}
export function distanceMeters(a: Pick<Location, 'latitude' | 'longitude'>, b: Pick<Location, 'latitude' | 'longitude'>): number {
  const rad = Math.PI / 180;
  const dlat = (b.latitude - a.latitude) * rad;
  const dlon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dlat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dlon / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}
export function validateCheckIn(value: unknown, gym: Pick<Location, 'latitude' | 'longitude'>, now = Date.now()) {
  const current = location(value, now);
  if (distanceMeters(current, gym) > 500) throw new APIError(403, 'You need to be within 500 meters of this gym.');
}
export interface Avatar { preset: string; color: string; assetPath?: string }
export interface Profile { uid: string; name: string; gsr: number; cosmetics: string[]; interests: string; avatar: Avatar;
  trainingAvatar?: ReturnType<typeof cleanTrainingAvatar>;
  visibility?: string; muscleRanks?: Record<string, number>; shareRank?: boolean; shareActivity?: boolean; highlights?: ReturnType<typeof cleanHighlights>; routines?: ReturnType<typeof cleanRoutines> }
const muscleKeys = new Set(['chest', 'shoulders', 'biceps', 'triceps', 'forearms', 'abs', 'quads', 'calves', 'back', 'traps', 'glutes', 'hamstrings', 'lowerBack']);
export function cleanTrainingAvatar(value: any) {
  if (value == null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value) || !['nailong', 'doubao'].includes(value.style)) {
    throw new APIError(400, 'Choose a supported training avatar.');
  }
  return {
    style: value.style as string,
    offsetX: finite(value.offsetX ?? 0, -1, 1), offsetY: finite(value.offsetY ?? 0, -1, 1),
    rotation: finite(value.rotation ?? 0, -360, 360), scale: finite(value.scale ?? 1, 0.5, 2),
  };
}
export function cleanMuscleRanks(value: any): Record<string, number> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).filter(([name]) => muscleKeys.has(name)).map(([name, score]) => [name, Math.round(finite(score, 0, 1000))]));
}
export function cleanHighlights(value: any) {
  if (!value || typeof value !== 'object') return undefined;
  const integer = (v: unknown, maximum: number) => Math.round(finite(v, 0, maximum));
  return {
    workoutCount: integer(value.workoutCount, 1_000_000), streakDays: integer(value.streakDays, 36500),
    weekMuscles: cleanMuscleRanks(value.weekMuscles),
    memories: (Array.isArray(value.memories) ? value.memories : []).slice(0, 8).map((m: any) => ({
      id: key(m.id), date: finite(m.date, 0, Date.now() + 86400000), title: text(m.title, 100),
      minutes: integer(m.minutes, 1440), sets: integer(m.sets, 10000), score: integer(m.score, 1000),
    })),
    months: (Array.isArray(value.months) ? value.months : []).slice(0, 6).map((m: any) => ({
      month: finite(m.month, 0, Date.now() + 86400000), sessions: integer(m.sessions, 10000), minutes: integer(m.minutes, 1_000_000),
    })),
    updatedAt: Date.now(),
  };
}
export function cleanRoutines(value: any) {
  return (Array.isArray(value) ? value : []).slice(0, 5).map((r: any) => ({
    id: key(r.id), name: text(r.name, 100),
    exercises: (Array.isArray(r.exercises) ? r.exercises : []).slice(0, 20).map((e: any) => ({
      name: text(e.name, 100), sets: Math.round(finite(e.sets, 1, 20)),
      repsLow: Math.round(finite(e.repsLow, 0, 500)), repsHigh: Math.round(finite(e.repsHigh, e.repsLow, 500)),
    })),
  })).filter(r => r.exercises.length > 0);
}
export function cleanProfile(uid: string, value: any, existing?: Profile): Profile {
  if (value.snapshotOnly) {
    if (!existing) throw new APIError(409, 'Create your shared profile first.');
    // Background refreshes update the equipped look but cannot overwrite consent, name or routine selection.
    const allowed = new Set((existing.routines ?? []).map(r => r.id));
    return cleanProfile(uid, { ...existing, gsr: value.gsr, muscleRanks: value.muscleRanks,
      highlights: value.highlights, cosmetics: value.cosmetics ?? existing.cosmetics,
      trainingAvatar: value.trainingAvatar ?? existing.trainingAvatar,
      routines: (Array.isArray(value.routines) ? value.routines : []).filter((r: any) => allowed.has(r.id)) }, existing);
  }
  const shareRank = typeof value.shareRank === 'boolean' ? value.shareRank : existing?.shareRank ?? (value.gsr ?? 0) > 0;
  const preset = value.avatar?.preset ?? existing?.avatar.preset ?? 'bolt';
  const color = value.avatar?.color ?? existing?.avatar.color ?? 'orange';
  if (!['bolt', 'leaf', 'star'].includes(preset) || !['orange', 'blue', 'purple', 'green'].includes(color)) {
    throw new APIError(400, 'Choose a supported avatar style.');
  }
  const shareActivity = typeof value.shareActivity === 'boolean' ? value.shareActivity : existing?.shareActivity ?? false;
  const visibility = value.visibility === 'anonymous' ? 'anonymous' : value.visibility === 'public' ? 'public' : existing?.visibility ?? 'public';
  const trainingAvatar = shareRank && visibility !== 'anonymous' ? cleanTrainingAvatar(value.trainingAvatar ?? existing?.trainingAvatar) : undefined;
  const highlights = shareActivity ? cleanHighlights(value.highlights ?? existing?.highlights) : undefined;
  return {
    uid, visibility, name: text(value.name, 40, 'Nickname'), shareRank, gsr: shareRank ? Math.round(finite(value.gsr ?? 0, 0, 1000)) : 0,
    ...(trainingAvatar ? { trainingAvatar } : {}),
    cosmetics: shareRank && Array.isArray(value.cosmetics) ? value.cosmetics.slice(0, 16).map((v: unknown) => text(v, 60)) : [],
    interests: typeof value.interests === 'string' ? value.interests.trim().slice(0, 160) : '',
    avatar: { preset, color, ...(existing?.avatar.assetPath && !value.resetAvatar ? { assetPath: existing.avatar.assetPath } : {}) },
    muscleRanks: shareRank && (value.gsr ?? 0) > 0 ? cleanMuscleRanks(value.muscleRanks ?? existing?.muscleRanks) : {},
    shareActivity, ...(highlights ? { highlights } : {}), routines: cleanRoutines(value.routines ?? existing?.routines),
  };
}
export interface Membership { roomId: string; sessionId: string; expiresAt: number; spawnX?: number; spawnY?: number; publicID?: string; visibility?: string; joinedAt?: number }
export interface Presence { uid: string; sessionId: string; x: number; y: number; station: string; status: string; updatedAt: number }
export interface World { memberships: Record<string, Membership>; rooms: Record<string, { presence: Record<string, Presence> }> }
export function validateGymEncounter(raw: Partial<World> | null, a: string, b: string, now = Date.now()) {
  const world = normalizeWorld(raw), first = world.memberships[a], second = world.memberships[b];
  if (!first || !second || first.roomId !== second.roomId || first.expiresAt <= now || second.expiresAt <= now) {
    throw new APIError(403, 'Meet in the same checked-in gym to send a friend request.');
  }
  for (const [uid, member] of [[a, first], [b, second]] as const) {
    const presence = world.rooms[member.roomId]?.presence?.[member.publicID ?? uid];
    if (member.visibility === 'anonymous') throw new APIError(403, 'Anonymous members cannot exchange friend requests.');
    if (!presence || presence.sessionId !== member.sessionId || presence.updatedAt < now - STALE_MS) {
      throw new APIError(403, 'Both members must be present in the gym.');
    }
  }
}
export function normalizeWorld(value: Partial<World> | null): World {
  return { memberships: value?.memberships ?? {}, rooms: value?.rooms ?? {} };
}
export function joinWorld(raw: Partial<World> | null, uid: string, roomId: string, sessionId: string, now: number): World {
  const world = normalizeWorld(raw);
  const otherActive = Object.entries(world.memberships).filter(([id, m]) => id !== uid && m.roomId === roomId && m.expiresAt > now);
  if (otherActive.length >= 10) throw new APIError(409, 'This room is full (10 members).');
  const previous = world.memberships[uid];
  if (previous) delete world.rooms[previous.roomId]?.presence?.[uid];
  const occupied = Object.entries(world.memberships).filter(([id, m]) => id !== uid && m.roomId === roomId && m.expiresAt > now).map(([, m]) => `${m.spawnX},${m.spawnY}`);
  const spawn = [[2,7], [3,7], [4,7], [5,7], [6,7], [2,6], [3,6], [4,6], [5,6], [6,6]].find(([x,y]) => !occupied.includes(`${x},${y}`)) ?? [2,7];
  world.memberships[uid] = { roomId, sessionId, expiresAt: now + LEASE_MS, spawnX: spawn[0]!, spawnY: spawn[1]! };
  world.rooms[roomId] ??= { presence: {} };
  world.rooms[roomId]!.presence ??= {};
  // The client installs onDisconnect before publishing its first presence.
  return world;
}
export interface Friendship { uid: string; status: 'incoming' | 'outgoing' | 'accepted'; updatedAt: number }
export interface Message { id: string; senderID: string; text: string; createdAt: number }
export interface SocialState {
  friends: Record<string, Record<string, Friendship>>;
  blocks: Record<string, Record<string, boolean>>;
  chats: Record<string, { members: Record<string, boolean>; messages: Record<string, Message> }>;
}
export function normalizeSocial(raw: Partial<SocialState> | null): SocialState {
  return { friends: raw?.friends ?? {}, blocks: raw?.blocks ?? {}, chats: raw?.chats ?? {} };
}
export function isBlocked(s: SocialState, a: string, b: string) { return !!(s.blocks[a]?.[b] || s.blocks[b]?.[a]); }
export function friendshipAction(raw: Partial<SocialState> | null, a: string, b: string, action: string, now: number): SocialState {
  const s = normalizeSocial(raw);
  if (a === b) throw new APIError(400, 'Choose another member.');
  s.friends[a] ??= {}; s.friends[b] ??= {}; s.blocks[a] ??= {};
  const state = s.friends[a]![b]?.status;
  if (action === 'block') {
    s.blocks[a]![b] = true;
    delete s.friends[a]![b]; delete s.friends[b]![a];
    // Delete the chat so prior listeners receive removal and no longer retain remote access.
    delete s.chats[pairKey(a, b)];
    return s;
  }
  if (action === 'unblock') { delete s.blocks[a]![b]; return s; }
  if (isBlocked(s, a, b)) throw new APIError(403, 'This interaction is unavailable.');
  if (action === 'request') {
    if (state) throw new APIError(409, 'A friendship or request already exists.');
    s.friends[a]![b] = { uid: b, status: 'outgoing', updatedAt: now };
    s.friends[b]![a] = { uid: a, status: 'incoming', updatedAt: now };
  } else if (action === 'accept') {
    if (state !== 'incoming' || s.friends[b]![a]?.status !== 'outgoing') throw new APIError(409, 'No incoming request.');
    s.friends[a]![b] = { uid: b, status: 'accepted', updatedAt: now };
    s.friends[b]![a] = { uid: a, status: 'accepted', updatedAt: now };
    s.chats[pairKey(a, b)] ??= { members: { [a]: true, [b]: true }, messages: {} };
  } else if (['decline', 'cancel', 'remove'].includes(action)) {
    const required = { decline: 'incoming', cancel: 'outgoing', remove: 'accepted' }[action];
    if (state !== required) throw new APIError(409, 'The request has changed. Refresh and try again.');
    delete s.friends[a]![b]; delete s.friends[b]![a]; delete s.chats[pairKey(a, b)];
  } else throw new APIError(400, 'Unknown friendship action.');
  return s;
}
export function appendPrivateMessage(raw: Partial<SocialState> | null, a: string, b: string, message: Message): SocialState {
  const s = normalizeSocial(raw);
  if (isBlocked(s, a, b) || s.friends[a]?.[b]?.status !== 'accepted' || s.friends[b]?.[a]?.status !== 'accepted') {
    throw new APIError(403, 'Private chat is available to accepted friends only.');
  }
  const id = pairKey(a, b);
  s.chats[id] ??= { members: { [a]: true, [b]: true }, messages: {} };
  const chat = s.chats[id]!;
  chat.messages ??= {};
  const duplicate = chat.messages[message.id];
  if (duplicate && (duplicate.senderID !== a || duplicate.text !== message.text)) throw new APIError(409, 'Message identifier already used.');
  chat.messages[message.id] ??= message;
  const ordered = Object.values(chat.messages).sort((x, y) => x.createdAt - y.createdAt);
  for (const old of ordered.slice(0, Math.max(0, ordered.length - 200))) delete chat.messages[old.id];
  return s;
}

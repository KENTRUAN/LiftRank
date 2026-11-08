import { APIError, distanceMeters, joinWorld, LEASE_MS, location, text, type Location, type Membership } from './core.js';

export const SPACE_RADIUS = 500;
export const REQUEST_MS = 120_000;
export interface SpaceRequest { id: string; uid: string; name: string; status: 'pending' | 'approved' | 'declined' | 'invited'; expiresAt: number; inviterID?: string }
export interface WorkoutSpace {
  id: string; name: string; ownerID: string; visibility: 'public' | 'private';
  latitude: number; longitude: number; createdAt: number; expiresAt: number; closed: boolean;
  requests: Record<string, SpaceRequest>;
}
export interface AccessState { memberships: Record<string, Membership>; spaces: Record<string, WorkoutSpace> }
export function accessState(raw: Partial<AccessState> | null): AccessState {
  return { memberships: raw?.memberships ?? {}, spaces: Object.fromEntries(Object.entries(raw?.spaces ?? {})
    .map(([id, space]) => [id, { ...space, requests: space.requests ?? {} }])) };
}
export function activeMembers(state: AccessState, room: string, now: number) {
  return Object.entries(state.memberships).filter(([, m]) => m.roomId === room && m.expiresAt > now)
    .sort(([a, x], [b, y]) => (x.joinedAt ?? 0) - (y.joinedAt ?? 0) || a.localeCompare(b));
}
/** Admission, hosting and capacity share one transaction; movement is outside it. */
export function reconcileSpaces(state: AccessState, now: number) {
  for (const [uid, member] of Object.entries(state.memberships)) if (member.expiresAt <= now) delete state.memberships[uid];
  for (const space of Object.values(state.spaces)) {
    space.requests ??= {};
    for (const [id, request] of Object.entries(space.requests)) if (request.expiresAt <= now) delete space.requests[id];
    const members = activeMembers(state, space.id, now);
    if (!members.length) {
      space.closed = true; space.requests = {};
      // Expired locations are removed rather than retained as a location history.
      delete state.spaces[space.id];
      continue;
    }
    if (!members.some(([id]) => id === space.ownerID)) space.ownerID = members[0]![0];
    space.expiresAt = Math.max(...members.map(([, m]) => m.expiresAt));
  }
  return state;
}
export function requireSpace(state: AccessState, id: string): WorkoutSpace {
  const space = state.spaces[id];
  if (!space || space.closed) throw new APIError(404, 'This workout space has ended. Start a new space.');
  return space;
}
export function requireNearby(value: unknown, space: Pick<WorkoutSpace, 'latitude' | 'longitude'>, now: number) {
  const point = location(value, now);
  if (distanceMeters(point, space) > SPACE_RADIUS) throw new APIError(403, 'You need to be within 500 meters of this space.');
  return point;
}
export function requireHost(state: AccessState, space: WorkoutSpace, uid: string, now: number) {
  if (space.ownerID !== uid || !activeMembers(state, space.id, now).some(([id]) => id === uid)) {
    throw new APIError(403, 'Only the current host can manage this space.');
  }
}
export function spaceSummary(space: WorkoutSpace, uid: string, point?: Location) {
  return { id: space.id, name: space.name, address: 'Nearby workout space', isDemo: false, kind: 'custom',
    visibility: space.visibility, isHost: uid === space.ownerID,
    ...(point ? { distanceMeters: Math.round(distanceMeters(point, space) / 50) * 50 } : {}) };
}
export function admit(state: AccessState, uid: string, roomId: string, sessionId: string, now: number,
  identity: { publicID: string; visibility: string }) {
  const previous = state.memberships[uid];
  state.memberships = joinWorld({ memberships: state.memberships, rooms: {} }, uid, roomId, sessionId, now).memberships;
  state.memberships[uid] = { ...state.memberships[uid]!, ...identity,
    joinedAt: previous?.roomId === roomId ? previous.joinedAt ?? now : now };
  return state;
}
export function createSpace(state: AccessState, uid: string, id: string, sessionId: string, input: any, now: number,
  identity: { publicID: string; visibility: string }) {
  const point = location(input.location, now);
  if (!['public', 'private'].includes(input.visibility)) throw new APIError(400, 'Choose public or private.');
  state.spaces[id] = { id, name: text(input.name, 60, 'Space name'), ownerID: uid, visibility: input.visibility,
    latitude: point.latitude, longitude: point.longitude, createdAt: now, expiresAt: now + LEASE_MS, closed: false, requests: {} };
  return reconcileSpaces(admit(state, uid, id, sessionId, now, identity), now);
}
export function joinSpace(state: AccessState, uid: string, id: string, sessionId: string, value: unknown, now: number,
  identity: { publicID: string; visibility: string }) {
  reconcileSpaces(state, now);
  const space = requireSpace(state, id);
  requireNearby(value, space, now);
  const alreadyMember = activeMembers(state, id, now).some(([member]) => member === uid);
  const request = space.requests[uid];
  if (!alreadyMember && (!request || request.expiresAt <= now || !['approved', 'invited'].includes(request.status))) {
    throw new APIError(403, 'Ask the host to join, or accept an invitation first.');
  }
  admit(state, uid, id, sessionId, now, identity);
  delete space.requests[uid];
  return reconcileSpaces(state, now);
}

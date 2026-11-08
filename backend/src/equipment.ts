import { APIError, key, STALE_MS, type Membership } from './core.js';

export type EquipmentStation = { ownerID: string; members: Record<string, string>; requests: Record<string, WorkInRequest> };
export type WorkInRequest = { id: string; requesterID: string; ownerID: string; sessionId: string; mode: string; createdAt: number; expiresAt: number };
export type EquipmentState = Record<string, EquipmentStation>;
const lifting = new Set(['bench', 'rack', 'platform']);
const allowed = new Set([...lifting, 'cardio']);
export function cleanEquipment(raw: EquipmentState | null, present: Record<string, any>, now: number): EquipmentState {
  const state = structuredClone(raw ?? {});
  for (const [station, value] of Object.entries(state)) {
    value.members ??= {}; value.requests ??= {};
    for (const [id, session] of Object.entries(value.members)) {
      if (!present[id] || present[id].sessionId !== session || present[id].updatedAt < now - STALE_MS) delete value.members[id];
    }
    if (!value.members[value.ownerID]) value.ownerID = Object.keys(value.members).sort()[0] ?? '';
    for (const [id, request] of Object.entries(value.requests)) {
      if (request.expiresAt <= now || request.ownerID !== value.ownerID || !present[id] || present[id].sessionId !== request.sessionId || present[id].updatedAt < now - STALE_MS) delete value.requests[id];
    }
    if (!Object.keys(value.members).length) delete state[station];
  }
  return state;
}
export function equipmentAction(raw: EquipmentState | null, present: Record<string, any>, actor: string, lease: Membership, station: string, action: string, target: string | undefined, mode: string, now: number) {
  const state = cleanEquipment(raw, present, now);
  if (!allowed.has(station)) throw new APIError(400, 'Choose a gym station.');
  if (!present[actor] || present[actor].sessionId !== lease.sessionId || present[actor].updatedAt < now - STALE_MS) throw new APIError(403, 'Rejoin the room before using equipment.');
  if (action === 'release') {
    if (state[station]) { delete state[station]!.members[actor]; delete state[station]!.requests[actor]; }
    return cleanEquipment(state, present, now);
  }
  const inUse = Object.entries(state).find(([_, item]) => !!item.members[actor]);
  if (action === 'claim') {
    if (state[station]?.members[actor]) return state;
    if (inUse) throw new APIError(409, 'Release your current station first.');
    if (state[station]) throw new APIError(409, lifting.has(station) ? 'Equipment occupied. Ask to work in or train together.' : 'Cardio equipment is occupied. This station cannot be shared.');
    state[station] = { ownerID: actor, members: { [actor]: lease.sessionId }, requests: {} };
  } else if (action === 'request') {
    const equipment = state[station];
    if (!equipment) throw new APIError(409, 'The equipment is free now. Try again.');
    if (!lifting.has(station)) throw new APIError(409, 'Cardio equipment cannot be shared.');
    if (inUse || equipment.members[actor]) throw new APIError(409, 'Release your current station first.');
    if (Object.keys(equipment.members).length >= 2) throw new APIError(409, 'This station already has two lifters.');
    if (!['workIn', 'together'].includes(mode)) throw new APIError(400, 'Choose work in or train together.');
    equipment.requests[actor] = { id: actor, requesterID: actor, ownerID: equipment.ownerID, sessionId: lease.sessionId, mode, createdAt: now, expiresAt: now + 60_000 };
  } else if (action === 'accept' || action === 'decline') {
    const equipment = state[station], request = equipment?.requests[key(target)];
    if (!equipment || equipment.ownerID !== actor || !request) throw new APIError(403, 'This request is no longer available.');
    if (action === 'accept') {
      if (Object.keys(equipment.members).length >= 2 || Object.values(state).some(e => !!e.members[request.requesterID])) throw new APIError(409, 'The lifter or equipment is no longer available.');
      equipment.members[request.requesterID] = request.sessionId;
    }
    delete equipment.requests[request.requesterID];
  } else throw new APIError(400, 'Unknown equipment action.');
  return state;
}

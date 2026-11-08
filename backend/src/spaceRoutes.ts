import type { Express } from 'express';
import type { Database, Reference } from 'firebase-admin/database';
import { randomUUID } from 'node:crypto';
import { APIError, key, location, isBlocked, normalizeSocial, type Membership } from './core.js';
import { accessState, activeMembers, createSpace, reconcileSpaces, requireHost, requireNearby, requireSpace,
  spaceSummary, REQUEST_MS, type AccessState } from './spaces.js';
import { nearbyRegisteredGyms } from './registeredGyms.js';

type Dependencies = {
  db: Database; transaction: (ref: Reference, fn: (raw: any) => any) => Promise<any>;
  quota: (uid: string, kind: string, user: number, total: number) => Promise<void>;
  clearPresence: (uid: string, lease: Membership) => Promise<void>;
};
export function spaceRoutes(app: Express, { db, transaction, quota, clearPresence }: Dependencies) {
  const ref = db.ref('world/access');
  const socialState = async () => {
    const [blocks, friends] = await Promise.all([db.ref('social/blocks').get(), db.ref('social/friends').get()]);
    return normalizeSocial({ blocks: blocks.val(), friends: friends.val() });
  };
  const update = (fn: (state: AccessState, now: number) => void) => transaction(ref, raw => {
    const now = Date.now(), state = reconcileSpaces(accessState(raw), now);
    fn(state, now); return state;
  }).then(accessState);
  const checkedProfile = async (uid: string) => {
    const profile = (await db.ref(`profiles/${uid}`).get()).val();
    if (!profile) throw new APIError(400, 'Create your community profile first.');
    return profile;
  };
  app.post('/spaces/nearby', async (req, res) => {
    const uid = res.locals.uid, point = location(req.body.location);
    await quota(uid, 'spaceDiscovery', 300, 10000);
    const social = await socialState();
    const state = await update(() => {});
    const spaces = Object.values(state.spaces).filter(space => {
      if (space.visibility !== 'public' || activeMembers(state, space.id, Date.now()).some(([id]) => isBlocked(social, uid, id))) return false;
      try { requireNearby(point, space, Date.now()); return true; } catch { return false; }
    }).map(space => spaceSummary(space, uid, point));
    res.json({ gyms: nearbyRegisteredGyms(point), spaces: spaces.sort((a, b) => a.distanceMeters! - b.distanceMeters!) });
  });
  app.post('/spaces/create', async (req, res) => {
    const uid = res.locals.uid, profile = await checkedProfile(uid);
    await quota(uid, 'spaceCreate', 20, 1000);
    const id = `space-${randomUUID()}`, sessionId = randomUUID();
    const identity = { publicID: profile.visibility === 'anonymous' ? `anon-${randomUUID()}` : uid, visibility: profile.visibility ?? 'public' };
    let previous: Membership | undefined;
    const state = await update((state, now) => { previous = state.memberships[uid]; createSpace(state, uid, id, sessionId, req.body, now, identity); });
    if (previous) await clearPresence(uid, previous);
    res.json({ gym: spaceSummary(state.spaces[id]!, uid), membership: state.memberships[uid] });
  });
  app.post('/spaces/inbox', async (_req, res) => {
    const uid = res.locals.uid, social = await socialState();
    const state = await update(() => {});
    const invitations = [], requests = [], sent = [];
    for (const space of Object.values(state.spaces)) {
      if (isBlocked(social, uid, space.ownerID)) continue;
      const mine = space.requests[uid];
      if (mine) {
        const entry = { id: mine.id, gym: spaceSummary(space, uid), status: mine.status, expiresAt: mine.expiresAt };
        if (['invited', 'approved'].includes(mine.status)) invitations.push(entry);
        else sent.push(entry);
      }
      if (activeMembers(state, space.id, Date.now()).some(([member]) => member === uid)) {
        for (const request of Object.values(space.requests)) {
          if (request.status === 'pending' && !isBlocked(social, uid, request.uid)) {
            requests.push({ id: request.id, roomId: space.id, name: request.name, expiresAt: request.expiresAt });
          }
        }
      }
    }
    const current = state.memberships[uid];
    const room = current && state.spaces[current.roomId];
    res.json({ invitations, requests, sent, room: room ? spaceSummary(room, uid) : null });
  });
  app.post('/spaces/:id/request', async (req, res) => {
    const uid = res.locals.uid, id = key(req.params.id), profile = await checkedProfile(uid), social = await socialState();
    await quota(uid, 'spaceRequest', 100, 3000);
    const requestID = randomUUID();
    await update((state, now) => {
      const space = requireSpace(state, id);
      if (space.visibility !== 'public') throw new APIError(403, 'This space is private. A nearby friend must invite you.');
      if (activeMembers(state, id, now).some(([member]) => isBlocked(social, uid, member))) throw new APIError(403, 'This space is unavailable.');
      requireNearby(req.body.location, space, now);
      if (space.requests[uid]?.status === 'pending') return;
      space.requests[uid] = { id: requestID, uid, name: profile.visibility === 'anonymous' ? 'Anonymous lifter' : profile.name,
        status: 'pending', expiresAt: now + REQUEST_MS };
    });
    res.json({ ok: true });
  });
  app.post('/spaces/:id/respond', async (req, res) => {
    const uid = res.locals.uid, id = key(req.params.id), requestID = key(req.body.requestID), social = await socialState();
    if (!['accept', 'decline'].includes(req.body.action)) throw new APIError(400, 'Choose accept or decline.');
    await update((state, now) => {
      const space = requireSpace(state, id);
      if (!activeMembers(state, id, now).some(([member]) => member === uid)) throw new APIError(403, 'Join this space before responding.');
      const request = Object.values(space.requests).find(r => r.id === requestID && r.status === 'pending');
      if (!request) throw new APIError(409, 'This request expired or was already handled.');
      if (isBlocked(social, uid, request.uid)) throw new APIError(403, 'This member is unavailable.');
      request.status = req.body.action === 'accept' ? 'approved' : 'declined'; request.expiresAt = now + REQUEST_MS;
    });
    res.json({ ok: true });
  });
  app.post('/spaces/:id/invite', async (req, res) => {
    const uid = res.locals.uid, id = key(req.params.id), target = key(req.body.targetID), social = await socialState();
    if (isBlocked(social, uid, target) || social.friends[uid]?.[target]?.status !== 'accepted') throw new APIError(403, 'You can invite accepted friends only.');
    await quota(uid, 'spaceInvite', 100, 3000);
    const requestID = randomUUID();
    await update((state, now) => {
      const space = requireSpace(state, id); requireHost(state, space, uid, now);
      space.requests[target] = { id: requestID, uid: target, name: 'Friend', status: 'invited', inviterID: uid, expiresAt: now + 300_000 };
    });
    res.json({ ok: true });
  });
  app.post('/spaces/:id/cancel', async (req, res) => {
    await update(state => { const space = requireSpace(state, key(req.params.id)); delete space.requests[res.locals.uid]; });
    res.json({ ok: true });
  });
  app.post('/spaces/:id/visibility', async (req, res) => {
    if (!['public', 'private'].includes(req.body.visibility)) throw new APIError(400, 'Choose public or private.');
    const uid = res.locals.uid, id = key(req.params.id);
    const state = await update((state, now) => {
      const space = requireSpace(state, id); requireHost(state, space, uid, now);
      space.visibility = req.body.visibility;
      if (space.visibility === 'private') {
        for (const [uid, request] of Object.entries(space.requests)) if (request.status !== 'invited') delete space.requests[uid];
      }
    });
    res.json({ gym: spaceSummary(state.spaces[id]!, uid) });
  });
}

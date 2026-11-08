import { spaceRoutes } from './spaceRoutes.js';
import { accessState, admit, joinSpace, reconcileSpaces } from './spaces.js';
import { registeredGyms } from './registeredGyms.js';
import { validatedTrainerReply } from './trainer.js';
import { trainerPlanReply } from './providers.js';
import { equipmentAction, cleanEquipment } from './equipment.js';
import express from 'express';
import { randomUUID } from 'node:crypto';
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase, type Reference } from 'firebase-admin/database';
import { getStorage } from 'firebase-admin/storage';
import { APIError, DEMO_ROOM, LEASE_MS, appendPrivateMessage, cleanProfile, finite, friendshipAction, isBlocked,
  joinWorld, key, location, normalizeSocial, pairKey, roomKey, text, validateCheckIn, validateGymEncounter, type Membership } from './core.js';
import { companionReply, generateAvatar, gymDetails, imageInput, searchGyms } from './providers.js';

const projectId = process.env.GOOGLE_CLOUD_PROJECT ?? 'demo-liftrank';
if (!getApps().length) initializeApp({ projectId,
  ...(!process.env.FIREBASE_DATABASE_EMULATOR_HOST ? { credential: applicationDefault() } : {}),
  databaseURL: process.env.FIREBASE_DATABASE_URL ?? `https://${projectId}-default-rtdb.firebaseio.com`,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
const db = getDatabase();
export const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '6mb' }));
app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use(async (req, res, next) => {
  try {
    const token = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if (!token) throw new APIError(401, 'Sign in to continue.');
    try { res.locals.uid = (await getAuth().verifyIdToken(token)).uid; }
    catch { throw new APIError(401, 'Session expired. Reopen the social gym.'); }
    next();
  } catch (e) { next(e); }
});
async function transaction(ref: Reference, operation: (current: any) => any) {
  // A get() does not retain the SDK's transaction cache. Keep a value listener
  // until the transaction finishes so a cold-cache null cannot abort a valid
  // acceptance/renewal or replace an existing world with an empty one.
  const listener = () => {};
  ref.on('value', listener);
  try {
    await ref.once('value');
    let error: unknown;
    const result = await ref.transaction(current => {
      try { error = undefined; return operation(current); }
      catch (e) { error = e; return undefined; }
    });
    if (error) throw error;
    if (!result.committed) throw new APIError(409, 'The data changed. Please retry.');
    return result.snapshot.val();
  } finally { ref.off('value', listener); }
}
async function membership(uid: string, roomId?: string): Promise<Membership> {
  const m = (await db.ref(`world/access/memberships/${uid}`).get()).val();
  if (!m || m.expiresAt <= Date.now() || (roomId && m.roomId !== roomId)) throw new APIError(403, 'Check into this gym first.');
  return m;
}
async function quota(uid: string, kind: string, perUser: number, globalMax: number, bucket = new Date().toISOString().slice(0, 10)) {
  await transaction(db.ref(`usage/${bucket}/${kind}`), current => {
    const s = current ?? { total: 0, users: {} };
    s.users ??= {};
    if ((s.users[uid] ?? 0) >= perUser || s.total >= globalMax) throw new APIError(429, 'Usage limit reached. Please try again later.');
    s.users[uid] = (s.users[uid] ?? 0) + 1; s.total = (s.total ?? 0) + 1;
    return s;
  });
}
app.post('/profile', async (req, res) => {
  const uid = res.locals.uid;
  const ref = db.ref(`profiles/${uid}`);
  let oldVisibility: string | undefined;
  const profile = await transaction(ref, old => { oldVisibility = old?.visibility ?? 'public'; return cleanProfile(uid, req.body, old); });
  if (!req.body.snapshotOnly && oldVisibility !== profile.visibility) {
    const lease = (await db.ref(`world/access/memberships/${uid}`).get()).val();
    if (lease) {
      const publicID = profile.visibility === 'anonymous' ? `anon-${randomUUID()}` : uid;
      await transaction(db.ref(`world/access/memberships/${uid}`), current => current?.sessionId === lease.sessionId ? { ...current, publicID, visibility: profile.visibility } : current);
      await clearPresence(uid, lease);
    }
  }
  res.json(profile);
});
app.post('/gyms/search', async (req, res) => {
  await quota(res.locals.uid, 'search', 100, Number(process.env.SEARCH_GLOBAL_LIMIT ?? 2000));
  const center = req.body.location ? location(req.body.location, Date.now(), false) : undefined;
  const radius = req.body.radius === 25000 ? 25000 : 5000;
  res.json({ gyms: await searchGyms(req.body.query ? text(req.body.query, 160) : '', center, radius) });
});
app.post('/rooms/join', async (req, res) => {
  const uid = res.locals.uid;
  const profile = (await db.ref(`profiles/${uid}`).get()).val();
  if (!profile) throw new APIError(400, 'Create your social profile first.');
  const requested = key(req.body.roomId), custom = requested.startsWith('space-');
  let roomId = requested;
  if (requested !== DEMO_ROOM && !custom) {
    await quota(uid, 'checkin', 100, 2000);
    if (requested.startsWith('registered-')) {
      const gym = registeredGyms().find(g => g.id === requested);
      if (!gym) throw new APIError(404, 'This registered gym is unavailable.');
      validateCheckIn(req.body.location, gym);
    } else {
      const placeID = text(req.body.placeID, 200, 'Place ID');
      const gym = await gymDetails(placeID);
      validateCheckIn(req.body.location, gym);
      roomId = roomKey(placeID);
      await db.ref(`gymIdentifiers/${roomId}`).set({ placeID });
    }
  }
  const sessionId = randomUUID();
  const identity = { publicID: profile.visibility === 'anonymous' ? `anon-${randomUUID()}` : uid, visibility: profile.visibility ?? 'public' };
  const social = custom ? normalizeSocial((await db.ref('social').get()).val()) : null;
  let previous: Membership | undefined;
  const state = await transaction(db.ref('world/access'), raw => {
    const state = accessState(raw), now = Date.now(); previous = state.memberships[uid];
    if (custom) {
      if (Object.entries(state.memberships).some(([id, m]) => m.roomId === roomId && m.expiresAt > now && isBlocked(social!, uid, id))) throw new APIError(403, 'This space is unavailable.');
      const grant = state.spaces[roomId]?.requests?.[uid];
      const inviter = grant?.inviterID;
      if (grant?.status === 'invited' && (!inviter || isBlocked(social!, inviter, uid) || social!.friends[inviter]?.[uid]?.status !== 'accepted')) throw new APIError(403, 'This friend invitation is no longer available.');
      joinSpace(state, uid, roomId, sessionId, req.body.location, now, identity);
    } else { admit(state, uid, roomId, sessionId, now, identity); reconcileSpaces(state, now); }
    return state;
  });
  if (previous) await clearPresence(uid, previous);
  res.json(state.memberships[uid]);
});
app.post('/rooms/renew', async (req, res) => {
  const uid = res.locals.uid, session = key(req.body.sessionId);
  const state = await transaction(db.ref('world/access'), raw => {
    const state = accessState(raw), now = Date.now(), m = state.memberships[uid];
    if (!m || m.sessionId !== session || m.expiresAt <= now) throw new APIError(403, 'Check in again to rejoin.');
    m.expiresAt = now + LEASE_MS;
    return reconcileSpaces(state, now);
  });
  res.json(state.memberships[uid]);
});
app.post('/rooms/leave', async (req, res) => {
  const uid = res.locals.uid, sessionId = key(req.body.sessionId);
  let removed: Membership | undefined;
  await transaction(db.ref('world/access'), raw => {
    const state = accessState(raw), m = state.memberships[uid]; removed = undefined;
    if (m?.sessionId === sessionId) { removed = m; delete state.memberships[uid]; }
    return reconcileSpaces(state, Date.now());
  });
  if (removed) await clearPresence(uid, removed);
  res.json({ ok: true });
});
spaceRoutes(app, { db, transaction, quota, clearPresence });
async function clearPresence(uid: string, membership: Membership) {
  await transaction(db.ref(`world/rooms/${membership.roomId}/presence/${membership.publicID ?? uid}`), p =>
    p?.sessionId === membership.sessionId ? null : p);
  await transaction(db.ref(`world/rooms/${membership.roomId}/equipment`), raw => {
    const state = raw ?? {};
    for (const entry of Object.values(state) as any[]) {
      const id = membership.publicID ?? uid;
      if (entry.members?.[id] === membership.sessionId) delete entry.members[id];
      if (entry.requests?.[id]?.sessionId === membership.sessionId) delete entry.requests[id];
    }
    return state;
  });
}
app.post('/equipment/:station/:action', async (req, res) => {
  const uid = res.locals.uid, lease = await membership(uid), actor = lease.publicID ?? uid;
  if (lease.roomId.startsWith('space-')) throw new APIError(400, 'Open workout spaces do not reserve gym machines.');
  await quota(uid, 'equipment', 600, 10000);
  const room = db.ref(`world/rooms/${lease.roomId}`);
  const present = (await room.child('presence').get()).val() ?? {};
  const state = await transaction(room.child('equipment'), raw => equipmentAction(raw, present, actor, lease,
    String(req.params.station), String(req.params.action), req.body.targetID, req.body.mode ?? 'workIn', Date.now()));
  res.json({ equipment: state });
});
app.post('/friends/:target/:action', async (req, res) => {
  const uid = res.locals.uid, target = key(req.params.target), action = String(req.params.action);
  if (action === 'request' || action === 'accept') {
    const profiles = await Promise.all([uid, target].map(id => db.ref(`profiles/${id}/visibility`).get()));
    if (profiles.some(p => p.val() === 'anonymous')) throw new APIError(403, 'Anonymous mode does not allow new connections.');
  }
  await quota(uid, 'social', 300, 5000);
  if (!(await db.ref(`profiles/${target}`).get()).exists()) throw new APIError(404, 'Member not found.');
  if (action === 'request') {
    const world = (await db.ref('world').get()).val();
    validateGymEncounter({ memberships: world?.access?.memberships, rooms: world?.rooms }, uid, target);
  }
  const social = await transaction(db.ref('social'), raw => friendshipAction(raw, uid, target, action, Date.now()));
  res.json({ friendship: social.friends?.[uid]?.[target] ?? null, conversationId: pairKey(uid, target) });
});
app.post('/messages/private/:target', async (req, res) => {
  const uid = res.locals.uid, target = key(req.params.target);
  const message = { id: key(req.body.id), senderID: uid, text: text(req.body.text, 1000), createdAt: Date.now() };
  await quota(uid, 'messages', 600, 10_000);
  await transaction(db.ref('social'), raw => appendPrivateMessage(raw, uid, target, message));
  res.json({ ...message, conversationId: pairKey(uid, target) });
});
app.post('/messages/room/:roomId', async (req, res) => {
  const uid = res.locals.uid, roomId = key(req.params.roomId);
  const lease = await membership(uid, roomId);
  const message = { id: key(req.body.id), senderID: lease.publicID ?? uid, text: text(req.body.text, 1000), createdAt: Date.now() };
  await quota(uid, 'messages', 600, 10_000);
  await transaction(db.ref(`roomMessages/${roomId}`), raw => {
    const messages = raw ?? {};
    if (messages[message.id] && messages[message.id].senderID !== message.senderID) throw new APIError(409, 'Message identifier already used.');
    messages[message.id] ??= message;
    const sorted = Object.keys(messages).sort((a, b) => messages[a].createdAt - messages[b].createdAt);
    for (const id of sorted.slice(0, Math.max(0, sorted.length - 50))) delete messages[id];
    return messages;
  });
  res.json(message);
});
app.post('/reports', async (req, res) => {
  const uid = res.locals.uid;
  await quota(uid, 'reports', 20, 1000);
  const target = key(req.body.targetID), messageID = key(req.body.messageID);
  let message: any;
  if (req.body.roomID) {
    const roomID = key(req.body.roomID);
    await membership(uid, roomID);
    message = (await db.ref(`roomMessages/${roomID}/${messageID}`).get()).val();
  } else {
    const social = normalizeSocial((await db.ref('social').get()).val());
    if (social.friends[uid]?.[target]?.status !== 'accepted' || isBlocked(social, uid, target)) throw new APIError(403, 'Conversation unavailable.');
    message = social.chats[pairKey(uid, target)]?.messages?.[messageID];
  }
  if (!message || message.senderID !== target) throw new APIError(404, 'Message unavailable.');
  await db.ref('reports').push().set({ reporterID: uid, targetID: target, message, reason: text(req.body.reason ?? 'Inappropriate message', 500), createdAt: Date.now() });
  res.json({ ok: true });
});
app.post('/avatars/generate', async (req, res) => {
  const uid = res.locals.uid;
  const prompt = text(req.body.prompt ?? 'Friendly gym character', 500);
  const selfie = imageInput(req.body.selfie);
  await quota(uid, 'avatar', 3, Number(process.env.AVATAR_GLOBAL_LIMIT ?? 30));
  // Selfie bytes exist only in request memory; do not log request bodies.
  const image = await generateAvatar(prompt, selfie);
  // Preview stays on the device. Only the approved image is uploaded to Storage.
  res.json(image);
});
app.post('/avatars/approve', async (req, res) => {
  const uid = res.locals.uid, image = imageInput(req.body.image);
  if (!image) throw new APIError(400, 'Choose an avatar preview.');
  if (!(await db.ref(`profiles/${uid}`).get()).exists()) throw new APIError(400, 'Create a profile first.');
  await quota(uid, 'avatarApproval', 10, 300);
  const path = `avatars/${uid}/${randomUUID()}.${image.mimeType === 'image/png' ? 'png' : 'jpg'}`;
  const file = getStorage().bucket().file(path);
  await file.save(Buffer.from(image.data, 'base64'), { contentType: image.mimeType, resumable: false, metadata: { cacheControl: 'private, max-age=3600' } });
  let previous: string | undefined;
  try {
    await transaction(db.ref(`profiles/${uid}`), profile => {
      if (!profile) throw new APIError(400, 'Profile unavailable.');
      previous = profile.avatar?.assetPath;
      return { ...profile, avatar: { ...profile.avatar, assetPath: path } };
    });
  } catch (error) { await file.delete().catch(() => {}); throw error; }
  if (previous && previous !== path) await getStorage().bucket().file(previous).delete().catch(() => {});
  res.json({ assetPath: path });
});
app.post('/trainer', async (req, res) => {
  const messages = req.body.messages;
  if (!Array.isArray(messages) || !messages.length || messages.length > 16) throw new APIError(400, 'Send up to 16 messages.');
  const catalog = req.body.catalog;
  if (!Array.isArray(catalog) || catalog.length > 250) throw new APIError(400, 'Send a valid exercise catalogue.');
  const entries = catalog.map((item: any) => ({ key: key(item.key), name: text(item.name, 120), cardio: item.cardio === true }));
  const input = messages.map((m: any) => ({ role: m.role === 'assistant' ? 'assistant' : 'user', text: text(m.text, 3000) }));
  // Workout context is supplied only on an explicit message send and never saved on the server.
  const context = { catalog: entries, localDate: text(req.body.localDate, 10), activeWorkout: req.body.activeWorkout ?? null,
    schedule: req.body.schedule ?? [], goals: typeof req.body.goals === 'string' ? req.body.goals.slice(0, 500) : '' };
  if (JSON.stringify(context).length > 60000) throw new APIError(400, 'Training context is too large.');
  res.json(await validatedTrainerReply(new Set(entries.map((e: any) => e.key)), repair => trainerPlanReply(input, context, repair),
    () => quota(res.locals.uid, 'companion', 30, Number(process.env.COMPANION_GLOBAL_LIMIT ?? 300)),
    { allowsTodoEditing: context.activeWorkout != null && context.activeWorkout.allowsTodoEditing !== false }));
});
app.post('/trainer/greeting', async (req, res) => {
  const context = {
    localDate: text(req.body.localDate, 10), language: text(req.body.language ?? 'en', 40),
    workout: text(req.body.status, 300), requestedPlan: text(req.body.plan, 300),
  };
  await quota(res.locals.uid, 'greeting', 20, Number(process.env.GREETING_GLOBAL_LIMIT ?? 200));
  const message = [{ role: 'user', text: 'Welcome me back in one or two short sentences in my supplied language. Use the supplied workout status and requested plan, if any. Offer a useful training encouragement. Do not invent a schedule or claim to change anything. Return keep, todos:null and schedule:[].' }];
  const result = await validatedTrainerReply(new Set(), repair => trainerPlanReply(message,
    { ...context, catalog: [], activeWorkout: { allowsTodoEditing: false, status: context.workout }, schedule: [] }, repair),
    () => quota(res.locals.uid, 'companion', 30, Number(process.env.COMPANION_GLOBAL_LIMIT ?? 300)), { allowsTodoEditing: false });
  res.json({ reply: result.reply.slice(0, 600) });
});
app.post('/companion', async (req, res) => {
  const uid = res.locals.uid;
  const input = req.body.messages;
  if (!Array.isArray(input) || !input.length || input.length > 16) throw new APIError(400, 'Send between 1 and 16 messages.');
  const messages = input.map(m => ({ role: m.role === 'assistant' ? 'assistant' : 'user', text: text(m.text, 2000) }));
  const profile = (await db.ref(`profiles/${uid}`).get()).val();
  const context: any = { name: profile?.name, interests: profile?.interests };
  // Explicit allowlist: no body measurements or detailed workout history.
  if (req.body.workout) context.workout = text(req.body.workout, 3000, 'Workout summary');
  if (req.body.station) context.station = text(req.body.station, 30);
  if (req.body.targetID) {
    const target = key(req.body.targetID);
    const social = normalizeSocial((await db.ref('social').get()).val());
    if (isBlocked(social, uid, target)) throw new APIError(403, 'Member unavailable.');
    if (social.friends[uid]?.[target]?.status !== 'accepted') {
      const [a, b] = await Promise.all([membership(uid), membership(target)]);
      if (a.roomId !== b.roomId) throw new APIError(403, 'Join the same room first.');
    }
    const other = (await db.ref(`profiles/${target}`).get()).val();
    if (other?.visibility === 'anonymous') throw new APIError(403, 'This member is anonymous.');
    context.otherMember = { name: other?.name, interests: other?.interests };
  }
  await quota(uid, req.body.targetID ? 'generalAI' : 'companion', 30,
    Number(req.body.targetID ? (process.env.GENERAL_AI_GLOBAL_LIMIT ?? 300) : (process.env.COMPANION_GLOBAL_LIMIT ?? 300)));
  res.json({ reply: await companionReply(messages, context, !!req.body.targetID) });
});
app.use((error: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const status = error instanceof APIError ? error.status : error.type === 'entity.too.large' ? 413 : 500;
  // Never log provider payloads, tokens, selfies, coordinates, or conversations.
  if (status === 500) console.error('Request failed', error?.code ?? error?.name ?? 'UnknownError');
  res.status(status).json({ error: status === 500 ? 'Something went wrong. Please try again.' : error.message });
});
if (process.env.NODE_ENV !== 'test') app.listen(Number(process.env.PORT ?? 8080), '0.0.0.0', () => console.log('LiftRank social API ready'));

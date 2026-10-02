#!/usr/bin/env node
// Grove: a local community chat server. Zero dependencies, Node 18+.
// Serves the frontend from ./public, a JSON REST API under /api and
// realtime updates over Server-Sent Events at /api/events.

'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '127.0.0.1';
const DATA_DIR = process.env.GROVE_DATA || path.join(__dirname, 'data');
const DB_FILE = path.join(DATA_DIR, 'db.json');
const PUBLIC_DIR = path.join(__dirname, 'public');
const MAX_BODY = 1024 * 1024;

const LIMITS = {
  username: [3, 24],
  password: [6, 200],
  displayName: [1, 32],
  status: [0, 80],
  communityName: [2, 40],
  channelName: [1, 32],
  topic: [0, 160],
  message: [1, 4000],
};
const COLORS = ['#7c5cff', '#ff6b9d', '#20c997', '#f59f00', '#339af0', '#e64980', '#12b886', '#fd7e14'];

// ---------------------------------------------------------------- storage

function emptyDb() {
  return { users: {}, sessions: {}, communities: {}, members: [], channels: {}, messages: {} };
}

function loadDb() {
  try {
    return Object.assign(emptyDb(), JSON.parse(fs.readFileSync(DB_FILE, 'utf8')));
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Could not read database, starting fresh:', err.message);
    return emptyDb();
  }
}

let db = loadDb();
let saveTimer = null;

function save() {
  if (saveTimer) return;
  saveTimer = setTimeout(flush, 100);
}

function flush() {
  clearTimeout(saveTimer);
  saveTimer = null;
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmp = DB_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db));
  fs.renameSync(tmp, DB_FILE);
}

// ---------------------------------------------------------------- helpers

const id = () => crypto.randomBytes(9).toString('base64url');
const now = () => new Date().toISOString();

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return { salt, hash: crypto.scryptSync(password, salt, 64).toString('hex') };
}

function checkPassword(password, user) {
  const { hash } = hashPassword(password, user.salt);
  return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(user.passHash, 'hex'));
}

function str(value, field, [min, max]) {
  if (typeof value !== 'string') throw new ApiError(400, `${field} is required`);
  const v = value.trim();
  if (v.length < min) throw new ApiError(400, `${field} must be at least ${min} characters`);
  if (v.length > max) throw new ApiError(400, `${field} must be at most ${max} characters`);
  return v;
}

function channelSlug(name) {
  const slug = name.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
  if (!slug) throw new ApiError(400, 'Channel name needs letters or numbers');
  return slug.slice(0, LIMITS.channelName[1]);
}

function inviteCode() {
  return crypto.randomBytes(5).toString('base64url');
}

function publicUser(u) {
  if (!u) return null;
  return {
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    color: u.color,
    status: u.status,
    online: online.has(u.id),
    createdAt: u.createdAt,
  };
}

function membership(communityId, userId) {
  return db.members.find((m) => m.communityId === communityId && m.userId === userId);
}

function requireCommunity(communityId, userId) {
  const c = db.communities[communityId];
  if (!c || !membership(communityId, userId)) throw new ApiError(404, 'Community not found');
  return c;
}

function requireOwner(community, userId) {
  if (community.ownerId !== userId) throw new ApiError(403, 'Only the owner can do that');
}

function requireChannel(channelId, userId) {
  const ch = db.channels[channelId];
  if (!ch) throw new ApiError(404, 'Channel not found');
  const community = requireCommunity(ch.communityId, userId);
  return { ch, community };
}

function communityView(c, userId) {
  const channels = Object.values(db.channels)
    .filter((ch) => ch.communityId === c.id)
    .sort((a, b) => a.position - b.position);
  const members = db.members
    .filter((m) => m.communityId === c.id)
    .map((m) => ({ ...publicUser(db.users[m.userId]), role: m.role, joinedAt: m.joinedAt }));
  return {
    id: c.id,
    name: c.name,
    icon: c.icon,
    color: c.color,
    ownerId: c.ownerId,
    createdAt: c.createdAt,
    inviteCode: c.ownerId === userId ? c.inviteCode : undefined,
    channels,
    members,
  };
}

function communitySummary(c) {
  return { id: c.id, name: c.name, icon: c.icon, color: c.color, ownerId: c.ownerId };
}

function messageView(m) {
  return { ...m, author: publicUser(db.users[m.authorId]) };
}

function messagesIn(channelId) {
  return (db.messages[channelId] ||= []);
}

function findMessage(messageId) {
  for (const [channelId, list] of Object.entries(db.messages)) {
    const index = list.findIndex((m) => m.id === messageId);
    if (index !== -1) return { channelId, list, index, msg: list[index] };
  }
  throw new ApiError(404, 'Message not found');
}

// ---------------------------------------------------------------- realtime

const clients = new Map(); // userId -> Set<res>
const online = new Set();

function send(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function toUsers(userIds, event, data) {
  for (const uid of new Set(userIds)) {
    for (const res of clients.get(uid) || []) send(res, event, data);
  }
}

function membersOf(communityId) {
  return db.members.filter((m) => m.communityId === communityId).map((m) => m.userId);
}

function toCommunity(communityId, event, data) {
  toUsers(membersOf(communityId), event, data);
}

function peersOf(userId) {
  const mine = db.members.filter((m) => m.userId === userId).map((m) => m.communityId);
  return db.members.filter((m) => mine.includes(m.communityId)).map((m) => m.userId);
}

function openStream(req, res, user) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.write('retry: 2000\n\n');
  if (!clients.has(user.id)) clients.set(user.id, new Set());
  clients.get(user.id).add(res);
  const wasOnline = online.has(user.id);
  online.add(user.id);
  send(res, 'ready', { user: publicUser(user) });
  if (!wasOnline) toUsers(peersOf(user.id), 'presence', { userId: user.id, online: true });

  const ping = setInterval(() => res.write(': ping\n\n'), 25000);
  req.on('close', () => {
    clearInterval(ping);
    const set = clients.get(user.id);
    set.delete(res);
    if (set.size === 0) {
      clients.delete(user.id);
      online.delete(user.id);
      toUsers(peersOf(user.id), 'presence', { userId: user.id, online: false });
    }
  });
}

// ---------------------------------------------------------------- routes

const routes = [];
function route(method, pattern, handler, { auth = true } = {}) {
  const keys = [];
  const re = new RegExp(
    '^' + pattern.replace(/:(\w+)/g, (_, k) => (keys.push(k), '([^/]+)')) + '$'
  );
  routes.push({ method, re, keys, handler, auth });
}

function startSession(user) {
  const token = crypto.randomBytes(32).toString('base64url');
  db.sessions[token] = { userId: user.id, createdAt: now() };
  save();
  return { token, user: publicUser(user) };
}

route('POST', '/api/auth/register', ({ body }) => {
  const username = str(body.username, 'Username', LIMITS.username).toLowerCase();
  if (!/^[a-z0-9_.]+$/.test(username)) {
    throw new ApiError(400, 'Username can only use letters, numbers, _ and .');
  }
  const password = typeof body.password === 'string' ? body.password : '';
  if (password.length < LIMITS.password[0]) throw new ApiError(400, 'Password must be at least 6 characters');
  if (password.length > LIMITS.password[1]) throw new ApiError(400, 'Password is too long');
  if (Object.values(db.users).some((u) => u.username === username)) {
    throw new ApiError(409, 'That username is taken');
  }
  const { salt, hash } = hashPassword(password);
  const user = {
    id: id(),
    username,
    displayName: body.displayName ? str(body.displayName, 'Display name', LIMITS.displayName) : username,
    passHash: hash,
    salt,
    color: COLORS[Object.keys(db.users).length % COLORS.length],
    status: '',
    createdAt: now(),
  };
  db.users[user.id] = user;
  return { status: 201, body: startSession(user) };
}, { auth: false });

route('POST', '/api/auth/login', ({ body }) => {
  const username = String(body.username || '').trim().toLowerCase();
  const user = Object.values(db.users).find((u) => u.username === username);
  if (!user || !checkPassword(String(body.password || ''), user)) {
    throw new ApiError(401, 'Wrong username or password');
  }
  return startSession(user);
}, { auth: false });

route('POST', '/api/auth/logout', ({ token }) => {
  delete db.sessions[token];
  save();
  return { ok: true };
});

route('GET', '/api/me', ({ user }) => publicUser(user));

route('PATCH', '/api/me', ({ user, body }) => {
  if (body.displayName !== undefined) user.displayName = str(body.displayName, 'Display name', LIMITS.displayName);
  if (body.status !== undefined) user.status = str(body.status, 'Status', LIMITS.status);
  if (body.color !== undefined) {
    if (!/^#[0-9a-f]{6}$/i.test(body.color)) throw new ApiError(400, 'Color must look like #a1b2c3');
    user.color = body.color;
  }
  if (body.password !== undefined) {
    if (!checkPassword(String(body.currentPassword || ''), user)) throw new ApiError(403, 'Current password is wrong');
    const p = String(body.password);
    if (p.length < LIMITS.password[0]) throw new ApiError(400, 'Password must be at least 6 characters');
    Object.assign(user, (({ salt, hash }) => ({ salt, passHash: hash }))(hashPassword(p)));
  }
  save();
  const view = publicUser(user);
  toUsers([user.id, ...peersOf(user.id)], 'user:update', view);
  return view;
});

route('GET', '/api/communities', ({ user }) =>
  db.members
    .filter((m) => m.userId === user.id)
    .sort((a, b) => a.joinedAt.localeCompare(b.joinedAt))
    .map((m) => communitySummary(db.communities[m.communityId]))
);

route('POST', '/api/communities', ({ user, body }) => {
  const name = str(body.name, 'Name', LIMITS.communityName);
  const icon = typeof body.icon === 'string' && body.icon.trim() ? [...body.icon.trim()].slice(0, 2).join('') : '';
  const c = {
    id: id(),
    name,
    icon,
    color: COLORS[crypto.randomInt(COLORS.length)],
    ownerId: user.id,
    inviteCode: inviteCode(),
    createdAt: now(),
  };
  db.communities[c.id] = c;
  db.members.push({ communityId: c.id, userId: user.id, role: 'owner', joinedAt: now() });
  for (const [i, [chName, topic]] of [['welcome', 'Say hi and introduce yourself'], ['general', 'Anything goes']].entries()) {
    const ch = { id: id(), communityId: c.id, name: chName, topic, position: i, createdAt: now() };
    db.channels[ch.id] = ch;
  }
  save();
  return { status: 201, body: communityView(c, user.id) };
});

route('GET', '/api/communities/:cid', ({ user, params }) =>
  communityView(requireCommunity(params.cid, user.id), user.id)
);

route('PATCH', '/api/communities/:cid', ({ user, params, body }) => {
  const c = requireCommunity(params.cid, user.id);
  requireOwner(c, user.id);
  if (body.name !== undefined) c.name = str(body.name, 'Name', LIMITS.communityName);
  if (body.icon !== undefined) c.icon = [...String(body.icon).trim()].slice(0, 2).join('');
  save();
  toCommunity(c.id, 'community:update', communitySummary(c));
  return communityView(c, user.id);
});

route('DELETE', '/api/communities/:cid', ({ user, params }) => {
  const c = requireCommunity(params.cid, user.id);
  requireOwner(c, user.id);
  const audience = membersOf(c.id);
  for (const ch of Object.values(db.channels)) {
    if (ch.communityId === c.id) {
      delete db.channels[ch.id];
      delete db.messages[ch.id];
    }
  }
  db.members = db.members.filter((m) => m.communityId !== c.id);
  delete db.communities[c.id];
  save();
  toUsers(audience, 'community:delete', { id: c.id });
  return { ok: true };
});

route('POST', '/api/communities/:cid/leave', ({ user, params }) => {
  const c = requireCommunity(params.cid, user.id);
  if (c.ownerId === user.id) throw new ApiError(400, 'Owners cannot leave. Delete the community instead.');
  db.members = db.members.filter((m) => !(m.communityId === c.id && m.userId === user.id));
  save();
  toCommunity(c.id, 'member:leave', { communityId: c.id, userId: user.id });
  toUsers([user.id], 'community:delete', { id: c.id });
  return { ok: true };
});

route('POST', '/api/communities/:cid/invite', ({ user, params }) => {
  const c = requireCommunity(params.cid, user.id);
  requireOwner(c, user.id);
  c.inviteCode = inviteCode();
  save();
  return { inviteCode: c.inviteCode };
});

route('GET', '/api/invites/:code', ({ params }) => {
  const c = Object.values(db.communities).find((x) => x.inviteCode === params.code);
  if (!c) throw new ApiError(404, 'That invite is invalid or expired');
  return { ...communitySummary(c), memberCount: membersOf(c.id).length };
}, { auth: false });

route('POST', '/api/invites/:code', ({ user, params }) => {
  const c = Object.values(db.communities).find((x) => x.inviteCode === params.code);
  if (!c) throw new ApiError(404, 'That invite is invalid or expired');
  if (!membership(c.id, user.id)) {
    const m = { communityId: c.id, userId: user.id, role: 'member', joinedAt: now() };
    db.members.push(m);
    save();
    toCommunity(c.id, 'member:join', {
      communityId: c.id,
      member: { ...publicUser(user), role: m.role, joinedAt: m.joinedAt },
    });
  }
  return communityView(c, user.id);
});

route('POST', '/api/communities/:cid/channels', ({ user, params, body }) => {
  const c = requireCommunity(params.cid, user.id);
  requireOwner(c, user.id);
  const name = channelSlug(str(body.name, 'Channel name', LIMITS.channelName));
  const siblings = Object.values(db.channels).filter((ch) => ch.communityId === c.id);
  if (siblings.some((ch) => ch.name === name)) throw new ApiError(409, 'A channel with that name exists');
  const ch = {
    id: id(),
    communityId: c.id,
    name,
    topic: body.topic ? str(body.topic, 'Topic', LIMITS.topic) : '',
    position: siblings.length ? Math.max(...siblings.map((s) => s.position)) + 1 : 0,
    createdAt: now(),
  };
  db.channels[ch.id] = ch;
  save();
  toCommunity(c.id, 'channel:create', ch);
  return { status: 201, body: ch };
});

route('PATCH', '/api/channels/:chid', ({ user, params, body }) => {
  const { ch, community } = requireChannel(params.chid, user.id);
  requireOwner(community, user.id);
  if (body.name !== undefined) {
    const name = channelSlug(str(body.name, 'Channel name', LIMITS.channelName));
    const clash = Object.values(db.channels).some(
      (o) => o.communityId === ch.communityId && o.id !== ch.id && o.name === name
    );
    if (clash) throw new ApiError(409, 'A channel with that name exists');
    ch.name = name;
  }
  if (body.topic !== undefined) ch.topic = str(body.topic, 'Topic', LIMITS.topic);
  save();
  toCommunity(ch.communityId, 'channel:update', ch);
  return ch;
});

route('DELETE', '/api/channels/:chid', ({ user, params }) => {
  const { ch, community } = requireChannel(params.chid, user.id);
  requireOwner(community, user.id);
  const remaining = Object.values(db.channels).filter((o) => o.communityId === ch.communityId);
  if (remaining.length <= 1) throw new ApiError(400, 'A community needs at least one channel');
  delete db.channels[ch.id];
  delete db.messages[ch.id];
  save();
  toCommunity(ch.communityId, 'channel:delete', { id: ch.id, communityId: ch.communityId });
  return { ok: true };
});

route('GET', '/api/channels/:chid/messages', ({ user, params, query }) => {
  const { ch } = requireChannel(params.chid, user.id);
  const limit = Math.min(Math.max(Number(query.get('limit')) || 50, 1), 100);
  let list = messagesIn(ch.id);
  const before = query.get('before');
  if (before) {
    const index = list.findIndex((m) => m.id === before);
    list = index === -1 ? [] : list.slice(0, index);
  }
  return list.slice(-limit).map(messageView);
});

route('POST', '/api/channels/:chid/messages', ({ user, params, body }) => {
  const { ch } = requireChannel(params.chid, user.id);
  const msg = {
    id: id(),
    channelId: ch.id,
    authorId: user.id,
    content: str(body.content, 'Message', LIMITS.message),
    createdAt: now(),
    editedAt: null,
    reactions: {},
  };
  messagesIn(ch.id).push(msg);
  save();
  const view = messageView(msg);
  toCommunity(ch.communityId, 'message:create', view);
  return { status: 201, body: view };
});

route('PATCH', '/api/messages/:mid', ({ user, params, body }) => {
  const { msg } = findMessage(params.mid);
  const { ch } = requireChannel(msg.channelId, user.id);
  if (msg.authorId !== user.id) throw new ApiError(403, 'You can only edit your own messages');
  msg.content = str(body.content, 'Message', LIMITS.message);
  msg.editedAt = now();
  save();
  const view = messageView(msg);
  toCommunity(ch.communityId, 'message:update', view);
  return view;
});

route('DELETE', '/api/messages/:mid', ({ user, params }) => {
  const { msg, list, index } = findMessage(params.mid);
  const { ch, community } = requireChannel(msg.channelId, user.id);
  if (msg.authorId !== user.id && community.ownerId !== user.id) {
    throw new ApiError(403, 'You cannot delete that message');
  }
  list.splice(index, 1);
  save();
  toCommunity(ch.communityId, 'message:delete', { id: msg.id, channelId: ch.id });
  return { ok: true };
});

route('POST', '/api/messages/:mid/reactions', ({ user, params, body }) => {
  const { msg } = findMessage(params.mid);
  const { ch } = requireChannel(msg.channelId, user.id);
  const emoji = typeof body.emoji === 'string' ? body.emoji.trim() : '';
  if (!emoji || [...emoji].length > 8) throw new ApiError(400, 'Pick an emoji');
  const users = (msg.reactions[emoji] ||= []);
  const at = users.indexOf(user.id);
  if (at === -1) users.push(user.id);
  else users.splice(at, 1);
  if (!users.length) delete msg.reactions[emoji];
  save();
  const view = messageView(msg);
  toCommunity(ch.communityId, 'message:update', view);
  return view;
});

route('POST', '/api/channels/:chid/typing', ({ user, params }) => {
  const { ch } = requireChannel(params.chid, user.id);
  const others = membersOf(ch.communityId).filter((u) => u !== user.id);
  toUsers(others, 'typing', { channelId: ch.id, user: publicUser(user) });
  return { ok: true };
});

// ---------------------------------------------------------------- http

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new ApiError(413, 'Request body too large'));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        resolve(parsed && typeof parsed === 'object' ? parsed : {});
      } catch {
        reject(new ApiError(400, 'Body must be JSON'));
      }
    });
    req.on('error', reject);
  });
}

function json(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(data);
}

function authUser(req, url) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : url.searchParams.get('token');
  const session = token && db.sessions[token];
  const user = session && db.users[session.userId];
  return user ? { token, user } : null;
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
};

function serveStatic(res, pathname) {
  const rel = pathname === '/' ? 'index.html' : decodeURIComponent(pathname).replace(/^\/+/, '');
  const file = path.resolve(PUBLIC_DIR, rel);
  if (!file.startsWith(PUBLIC_DIR + path.sep)) return json(res, 403, { error: 'Forbidden' });
  fs.readFile(file, (err, data) => {
    if (err) {
      // Unknown paths fall back to the app shell so client-side routes work.
      return fs.readFile(path.join(PUBLIC_DIR, 'index.html'), (e2, html) => {
        if (e2) return json(res, 404, { error: 'Not found' });
        res.writeHead(200, { 'Content-Type': MIME['.html'] });
        res.end(html);
      });
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const { pathname } = url;

  if (!pathname.startsWith('/api/')) {
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'Method not allowed' });
    return serveStatic(res, pathname);
  }

  try {
    if (pathname === '/api/health') return json(res, 200, { ok: true, users: Object.keys(db.users).length });

    if (pathname === '/api/events' && req.method === 'GET') {
      const auth = authUser(req, url);
      if (!auth) throw new ApiError(401, 'Log in first');
      return openStream(req, res, auth.user);
    }

    let pathMatched = false;
    for (const r of routes) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      pathMatched = true;
      if (r.method !== req.method) continue;
      const auth = authUser(req, url);
      if (r.auth && !auth) throw new ApiError(401, 'Log in first');
      const params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
      const body = req.method === 'GET' ? {} : await readBody(req);
      const result = await r.handler({ ...auth, params, body, query: url.searchParams, req });
      if (result && result.status && 'body' in result) return json(res, result.status, result.body);
      return json(res, 200, result);
    }
    throw new ApiError(pathMatched ? 405 : 404, pathMatched ? 'Method not allowed' : 'No such endpoint');
  } catch (err) {
    if (err instanceof ApiError) return json(res, err.status, { error: err.message });
    console.error(err);
    return json(res, 500, { error: 'Something went wrong on the server' });
  }
}

function createServer() {
  return http.createServer((req, res) => {
    handle(req, res);
  });
}

if (require.main === module) {
  const server = createServer();
  server.listen(PORT, HOST, () => {
    console.log(`Grove is running at http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`);
    console.log(`Data is stored in ${DB_FILE}`);
  });
  const stop = () => {
    if (saveTimer) flush();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

module.exports = { createServer, flush };

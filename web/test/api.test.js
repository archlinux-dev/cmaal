'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'grove-test-'));
process.env.GROVE_DATA = dataDir;
const { createServer, flush } = require('../server.js');

let server;
let base;

before(async () => {
  server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.closeAllConnections();
  server.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

async function call(method, url, body, token) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + url, { method, headers, body: body && JSON.stringify(body) });
  return { status: res.status, body: await res.json() };
}

// Reads Server-Sent Events until `predicate` matches one, or times out.
async function nextEvent(token, predicate, trigger) {
  const ctrl = new AbortController();
  const res = await fetch(`${base}/api/events?token=${token}`, { signal: ctrl.signal });
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  let triggered = false;
  const timeout = setTimeout(() => ctrl.abort(), 3000);
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) throw new Error('stream ended');
      buf += decoder.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n\n')) !== -1) {
        const chunk = buf.slice(0, i);
        buf = buf.slice(i + 2);
        const event = /^event: (.+)$/m.exec(chunk)?.[1];
        const data = /^data: (.+)$/m.exec(chunk)?.[1];
        if (event === 'ready' && !triggered) {
          triggered = true;
          await trigger();
        } else if (event && predicate(event, data && JSON.parse(data))) {
          return { event, data: JSON.parse(data) };
        }
      }
    }
  } finally {
    clearTimeout(timeout);
    ctrl.abort();
  }
}

let alice;
let bob;
let community;

test('serves the frontend', async () => {
  const res = await fetch(base + '/');
  assert.equal(res.status, 200);
  assert.match(await res.text(), /<title>Grove<\/title>/);
  const traversal = await fetch(base + '/..%2fserver.js');
  assert.notEqual(await traversal.text(), fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8'));
});

test('register, login and validation', async () => {
  const a = await call('POST', '/api/auth/register', { username: 'Alice', password: 'hunter22', displayName: 'Alice ✨' });
  assert.equal(a.status, 201);
  assert.equal(a.body.user.username, 'alice');
  alice = a.body.token;

  assert.equal((await call('POST', '/api/auth/register', { username: 'alice', password: 'whatever1' })).status, 409);
  assert.equal((await call('POST', '/api/auth/register', { username: 'b', password: 'whatever1' })).status, 400);
  assert.equal((await call('POST', '/api/auth/register', { username: 'bob', password: '123' })).status, 400);

  bob = (await call('POST', '/api/auth/register', { username: 'bob', password: 'password1' })).body.token;
  assert.equal((await call('POST', '/api/auth/login', { username: 'alice', password: 'nope' })).status, 401);
  const login = await call('POST', '/api/auth/login', { username: 'ALICE', password: 'hunter22' });
  assert.equal(login.status, 200);
  assert.equal((await call('GET', '/api/me', null, login.body.token)).body.displayName, 'Alice ✨');
  assert.equal((await call('GET', '/api/me')).status, 401);
});

test('communities, invites and channels', async () => {
  const c = await call('POST', '/api/communities', { name: 'Game Night', icon: '🎮' }, alice);
  assert.equal(c.status, 201);
  community = c.body;
  assert.deepEqual(community.channels.map((x) => x.name), ['welcome', 'general']);
  assert.ok(community.inviteCode);

  assert.equal((await call('GET', `/api/communities/${community.id}`, null, bob)).status, 404);
  const preview = await call('GET', `/api/invites/${community.inviteCode}`);
  assert.equal(preview.body.memberCount, 1);
  const joined = await call('POST', `/api/invites/${community.inviteCode}`, {}, bob);
  assert.equal(joined.status, 200);
  assert.equal(joined.body.members.length, 2);
  assert.equal(joined.body.inviteCode, undefined, 'members do not see the invite code');

  assert.equal((await call('POST', `/api/communities/${community.id}/channels`, { name: 'nope' }, bob)).status, 403);
  const ch = await call('POST', `/api/communities/${community.id}/channels`, { name: 'Clips & Memes', topic: 'lol' }, alice);
  assert.equal(ch.status, 201);
  assert.equal(ch.body.name, 'clips-memes');
  assert.equal((await call('POST', `/api/communities/${community.id}/channels`, { name: 'clips memes' }, alice)).status, 409);

  const reset = await call('POST', `/api/communities/${community.id}/invite`, {}, alice);
  assert.notEqual(reset.body.inviteCode, community.inviteCode);
  assert.equal((await call('GET', `/api/invites/${community.inviteCode}`)).status, 404);
});

test('messages: send, edit, react, delete, paginate', async () => {
  const general = community.channels[1].id;
  const sent = await call('POST', `/api/channels/${general}/messages`, { content: 'hi **all**' }, bob);
  assert.equal(sent.status, 201);
  assert.equal(sent.body.author.username, 'bob');
  assert.equal((await call('POST', `/api/channels/${general}/messages`, { content: '   ' }, bob)).status, 400);

  assert.equal((await call('PATCH', `/api/messages/${sent.body.id}`, { content: 'hacked' }, alice)).status, 403);
  const edited = await call('PATCH', `/api/messages/${sent.body.id}`, { content: 'hi everyone' }, bob);
  assert.equal(edited.body.content, 'hi everyone');
  assert.ok(edited.body.editedAt);

  let r = await call('POST', `/api/messages/${sent.body.id}/reactions`, { emoji: '🔥' }, alice);
  assert.deepEqual(r.body.reactions['🔥'].length, 1);
  r = await call('POST', `/api/messages/${sent.body.id}/reactions`, { emoji: '🔥' }, alice);
  assert.equal(r.body.reactions['🔥'], undefined);

  for (let i = 0; i < 60; i++) await call('POST', `/api/channels/${general}/messages`, { content: `m${i}` }, alice);
  const page = await call('GET', `/api/channels/${general}/messages`, null, alice);
  assert.equal(page.body.length, 50);
  assert.equal(page.body.at(-1).content, 'm59');
  const older = await call('GET', `/api/channels/${general}/messages?before=${page.body[0].id}`, null, alice);
  assert.equal(older.body.length, 11);
  assert.equal(older.body[0].content, 'hi everyone');

  // Owners can moderate, others cannot.
  const mine = page.body.at(-1);
  assert.equal((await call('DELETE', `/api/messages/${mine.id}`, null, bob)).status, 403);
  assert.equal((await call('DELETE', `/api/messages/${sent.body.id}`, null, alice)).status, 200);
});

test('realtime: members get new messages over SSE', async () => {
  const general = community.channels[1].id;
  const got = await nextEvent(bob, (e, d) => e === 'message:create' && d.content === 'live!', () =>
    call('POST', `/api/channels/${general}/messages`, { content: 'live!' }, alice));
  assert.equal(got.data.author.username, 'alice');
});

test('data persists to disk', () => {
  flush();
  const saved = JSON.parse(fs.readFileSync(path.join(dataDir, 'db.json'), 'utf8'));
  assert.equal(Object.keys(saved.users).length, 2);
  const user = Object.values(saved.users)[0];
  assert.ok(user.passHash && !JSON.stringify(saved).includes('hunter22'), 'passwords are hashed');
});

test('leaving and deleting', async () => {
  assert.equal((await call('POST', `/api/communities/${community.id}/leave`, {}, alice)).status, 400);
  assert.equal((await call('POST', `/api/communities/${community.id}/leave`, {}, bob)).status, 200);
  assert.equal((await call('GET', '/api/communities', null, bob)).body.length, 0);
  assert.equal((await call('DELETE', `/api/communities/${community.id}`, null, alice)).status, 200);
  assert.equal((await call('GET', `/api/communities/${community.id}`, null, alice)).status, 404);
});

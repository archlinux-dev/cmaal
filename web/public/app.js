// Grove frontend: routing, rendering and live updates. No frameworks.
'use strict';

const $ = (sel, root = document) => root.querySelector(sel);
const EMOJI = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👀', '✨', '🙏', '💯', '😎', '🥺', '😭', '🤔', '👋',
  '🍕', '🌳', '🚀', '✅', '❌', '💜', '🫶', '😈'];
const COLORS = ['#7c5cff', '#ff6b9d', '#20c997', '#f59f00', '#339af0', '#e64980', '#12b886', '#fd7e14'];
const GROUP_MS = 7 * 60 * 1000;

const state = {
  me: null,
  communities: [],
  current: null, // full community view
  channelId: null,
  messages: new Map(), // channelId -> [message]
  exhausted: new Set(), // channelIds with no older history
  unread: new Set(), // channelIds
  unreadCommunities: new Set(),
  typing: new Map(), // channelId -> Map(userId -> { name, until })
  source: null,
  editing: null,
  pendingInvite: null,
};

// ------------------------------------------------------------ utilities

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'html') el.innerHTML = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : String(c));
  return el;
}

function avatar(user, size = '') {
  const el = h('span', { class: `avatar ${size}`, title: user.displayName }, initial(user.displayName || user.username));
  el.style.background = user.color || COLORS[0];
  return el;
}

function initial(name) {
  return [...(name || '?').trim()][0]?.toUpperCase() || '?';
}

function fmtTime(iso) {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function fmtDay(iso) {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(Date.now() - 864e5);
  if (d.toDateString() === today.toDateString()) return 'Today';
  if (d.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
}

function fmtStamp(iso) {
  const day = fmtDay(iso);
  return `${day === 'Today' || day === 'Yesterday' ? day + ' at' : new Date(iso).toLocaleDateString() + ','} ${fmtTime(iso)}`;
}

let toastTimer;
function toast(text, bad = false) {
  const el = $('#toast');
  el.textContent = text;
  el.className = `toast${bad ? ' bad' : ''}`;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 3200);
}

function fail(err) {
  toast(err.message || String(err), true);
  if (err.status === 401) logout(true);
}

// Light markdown: code, bold, italics, underline, strike, spoilers, quotes, links, mentions.
function renderMarkdown(text) {
  const slots = [];
  const keep = (html) => `\u0000${slots.push(html) - 1}\u0000`;
  let s = escapeHtml(text);
  s = s.replace(/```(?:[a-z0-9+-]*\n)?([\s\S]*?)```/gi, (_, code) => keep(`<pre><code>${code.replace(/^\n|\n$/g, '')}</code></pre>`));
  s = s.replace(/`([^`\n]+)`/g, (_, code) => keep(`<code>${code}</code>`));
  s = s.replace(/\bhttps?:\/\/[^\s<]+[^\s<.,;:!?)\]'"]/g, (url) => keep(`<a href="${url}" target="_blank" rel="noopener noreferrer">${url}</a>`));
  s = s.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
    .replace(/__(.+?)__/g, '<u>$1</u>')
    .replace(/(^|[^*\w])\*(?!\s)(.+?)\*(?!\w)/g, '$1<i>$2</i>')
    .replace(/(^|[^_\w])_(?!\s)(.+?)_(?!\w)/g, '$1<i>$2</i>')
    .replace(/~~(.+?)~~/g, '<s>$1</s>')
    .replace(/\|\|(.+?)\|\|/g, '<span class="spoiler" title="Click to reveal">$1</span>')
    .replace(/(^|\s)@([a-z0-9_.]{3,24})\b/gi, (m, pre, name) =>
      state.current?.members.some((u) => u.username === name.toLowerCase()) ? `${pre}<span class="mention">@${name}</span>` : m)
    .replace(/^&gt; ?(.*)$/gm, '<blockquote>$1</blockquote>');
  s = s.replace(/(<\/blockquote>)\n/g, '$1');
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => slots[i]);
}

// ------------------------------------------------------------ routing

function go(hash) {
  if (location.hash === hash) route();
  else location.hash = hash;
}

function show(view) {
  for (const v of document.querySelectorAll('.view')) v.hidden = v.id !== `view-${view}`;
}

async function route() {
  const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
  const [page, a, b] = parts;
  closeModal();

  if (page === 'invite' && a) {
    state.pendingInvite = a;
    if (!Api.token) return go('#/register');
    await ensureApp();
    return go('#/app');
  }

  if (page === 'login' || page === 'register') {
    if (Api.token) return go('#/app');
    show('auth');
    return setAuthMode(page);
  }

  if (page === 'app') {
    if (!Api.token) return go('#/login');
    if (!(await ensureApp())) return;
    show('app');
    if (state.pendingInvite) {
      const code = state.pendingInvite;
      state.pendingInvite = null;
      openJoin(code);
    }
    return openRoute(a, b);
  }

  show('landing');
  const cta = $('#view-landing .nav-cta');
  cta.innerHTML = Api.token
    ? '<a class="btn btn-primary" href="#/app">Open Grove</a>'
    : '<a class="btn btn-ghost" href="#/login">Log in</a><a class="btn btn-primary" href="#/register">Get started</a>';
}

window.addEventListener('hashchange', route);

// Landing anchors (#features etc.) should scroll, not route.
document.addEventListener('click', (e) => {
  const a = e.target.closest('a[href^="#"]');
  if (!a || a.getAttribute('href').startsWith('#/')) return;
  const target = document.getElementById(a.getAttribute('href').slice(1));
  if (target) {
    e.preventDefault();
    target.scrollIntoView({ behavior: 'smooth' });
  }
});

// ------------------------------------------------------------ auth

let authMode = 'login';
function setAuthMode(mode) {
  authMode = mode;
  const reg = mode === 'register';
  $('#auth-title').textContent = reg ? 'Create an account' : 'Welcome back!';
  $('#auth-sub').textContent = state.pendingInvite
    ? 'Sign in to accept your invite.'
    : reg ? 'Join the grove. It only takes a second.' : "We're so excited to see you again.";
  $('#display-wrap').hidden = !reg;
  $('#auth-submit').textContent = reg ? 'Create account' : 'Log in';
  $('#auth-form [name=password]').autocomplete = reg ? 'new-password' : 'current-password';
  $('#auth-switch').innerHTML = reg
    ? 'Already have an account? <a href="#/login">Log in</a>'
    : 'Need an account? <a href="#/register">Register</a>';
  $('#auth-error').hidden = true;
  $('#auth-form [name=username]').focus();
}

$('#auth-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = new FormData(e.target);
  const btn = $('#auth-submit');
  btn.disabled = true;
  try {
    const res = authMode === 'register'
      ? await Api.register(form.get('username'), form.get('password'), form.get('displayName') || undefined)
      : await Api.login(form.get('username'), form.get('password'));
    Api.setToken(res.token);
    e.target.reset();
    go('#/app');
  } catch (err) {
    $('#auth-error').textContent = err.message;
    $('#auth-error').hidden = false;
  } finally {
    btn.disabled = false;
  }
});

async function logout(silent) {
  if (!silent) await Api.logout().catch(() => {});
  Api.setToken(null);
  state.source?.close();
  Object.assign(state, {
    me: null, communities: [], current: null, channelId: null, source: null,
    messages: new Map(), exhausted: new Set(), unread: new Set(), unreadCommunities: new Set(),
  });
  go('#/login');
}

// ------------------------------------------------------------ app bootstrap

let booting = null;
function ensureApp() {
  if (state.me) return Promise.resolve(true);
  booting ||= (async () => {
    try {
      state.me = await Api.me();
      state.communities = await Api.communities();
      // Learn which channel belongs to which community so unread dots work everywhere.
      const details = await Promise.all(state.communities.map((c) => Api.community(c.id).catch(() => null)));
      for (const d of details) for (const ch of d?.channels || []) channelMap.set(ch.id, d.id);
      connect();
      renderMe();
      renderRail();
      return true;
    } catch (err) {
      fail(err);
      return false;
    } finally {
      booting = null;
    }
  })();
  return booting;
}

async function openRoute(cid, chid) {
  closeDrawer();
  if (!cid) {
    if (state.communities.length) {
      let last = null;
      try { last = localStorage.getItem('grove.last'); } catch {}
      const target = state.communities.find((c) => c.id === last) || state.communities[0];
      return go(`#/app/${target.id}`);
    }
    return showHome();
  }
  if (state.current?.id !== cid) {
    try {
      state.current = await Api.community(cid);
    } catch (err) {
      toast(err.message, true);
      return go('#/app');
    }
  }
  const channels = state.current.channels;
  const channel = channels.find((c) => c.id === chid) || channels[0];
  if (!chid || !channels.some((c) => c.id === chid)) return go(`#/app/${cid}/${channel.id}`);
  try { localStorage.setItem('grove.last', cid); } catch {}
  state.unreadCommunities.delete(cid);
  state.channelId = channel.id;
  state.unread.delete(channel.id);
  state.editing = null;
  renderRail();
  renderSidebar();
  renderMembers();
  renderChatHead();
  $('#home-panel').hidden = true;
  $('#messages').hidden = false;
  $('#composer').hidden = false;
  $('#typing').hidden = false;
  $('#view-app').classList.remove('no-members');
  if (!state.messages.has(channel.id)) {
    $('#messages').replaceChildren();
    try {
      const list = await Api.messages(channel.id);
      state.messages.set(channel.id, list);
      if (list.length < 50) state.exhausted.add(channel.id);
    } catch (err) {
      return fail(err);
    }
  }
  if (state.channelId !== channel.id) return;
  renderMessages(true);
  renderTyping();
  const input = $('#composer-input');
  input.placeholder = `Message #${channel.name}`;
  if (matchMedia('(pointer: fine)').matches) input.focus();
}

function showHome() {
  state.current = null;
  state.channelId = null;
  renderRail();
  renderSidebar();
  $('#chat-title').textContent = 'Home';
  $('#chat-hash').hidden = true;
  $('#chat-topic').textContent = '';
  $('#home-name').textContent = state.me.displayName;
  $('#home-text').textContent = state.communities.length
    ? 'Pick a community on the left, or start another one.'
    : 'You are not in any community yet. Make one or join with an invite code.';
  $('#home-panel').hidden = false;
  $('#messages').hidden = true;
  $('#composer').hidden = true;
  $('#typing').hidden = true;
  $('#members-toggle').hidden = true;
  $('#view-app').classList.add('no-members');
  show('app');
}

// ------------------------------------------------------------ realtime

function connect() {
  state.source?.close();
  state.source = Api.events({
    ready: () => {},
    presence: ({ userId, online }) => {
      if (!state.current) return;
      const m = state.current.members.find((x) => x.id === userId);
      if (m) {
        m.online = online;
        renderMembers();
      }
    },
    'user:update': (user) => {
      if (user.id === state.me.id) {
        state.me = user;
        renderMe();
      }
      if (state.current) {
        const m = state.current.members.find((x) => x.id === user.id);
        if (m) Object.assign(m, user);
        renderMembers();
      }
      for (const list of state.messages.values()) {
        for (const msg of list) if (msg.authorId === user.id) msg.author = user;
      }
      renderMessages();
    },
    'message:create': (msg) => {
      const list = state.messages.get(msg.channelId);
      if (list && !list.some((m) => m.id === msg.id)) {
        const pending = list.findIndex((m) => m.pending && m.authorId === msg.authorId && m.content === msg.content);
        if (pending !== -1) list.splice(pending, 1, msg);
        else list.push(msg);
      }
      clearTyping(msg.channelId, msg.authorId);
      if (msg.channelId === state.channelId && document.visibilityState === 'visible') {
        renderMessages();
      } else if (msg.authorId !== state.me.id) {
        state.unread.add(msg.channelId);
        const ch = state.current?.channels.find((c) => c.id === msg.channelId);
        if (!ch) {
          const cid = findCommunityOfChannel(msg.channelId);
          if (cid) state.unreadCommunities.add(cid);
        }
        if (msg.channelId === state.channelId) renderMessages();
        renderSidebar();
        renderRail();
        notify(msg);
      }
    },
    'message:update': (msg) => {
      const list = state.messages.get(msg.channelId);
      const i = list ? list.findIndex((m) => m.id === msg.id) : -1;
      if (i !== -1) list[i] = msg;
      if (msg.channelId === state.channelId) renderMessages();
    },
    'message:delete': ({ id, channelId }) => {
      const list = state.messages.get(channelId);
      if (list) state.messages.set(channelId, list.filter((m) => m.id !== id));
      if (channelId === state.channelId) renderMessages();
    },
    typing: ({ channelId, user }) => {
      if (!state.typing.has(channelId)) state.typing.set(channelId, new Map());
      state.typing.get(channelId).set(user.id, { name: user.displayName, until: Date.now() + 6000 });
      if (channelId === state.channelId) renderTyping();
    },
    'channel:create': (ch) => {
      channelMap.set(ch.id, ch.communityId);
      if (state.current?.id !== ch.communityId) return;
      if (!state.current.channels.some((c) => c.id === ch.id)) state.current.channels.push(ch);
      renderSidebar();
    },
    'channel:update': (ch) => {
      if (state.current?.id !== ch.communityId) return;
      const i = state.current.channels.findIndex((c) => c.id === ch.id);
      if (i !== -1) state.current.channels[i] = ch;
      renderSidebar();
      if (ch.id === state.channelId) renderChatHead();
    },
    'channel:delete': ({ id, communityId }) => {
      state.messages.delete(id);
      if (state.current?.id !== communityId) return;
      state.current.channels = state.current.channels.filter((c) => c.id !== id);
      if (state.channelId === id) go(`#/app/${communityId}`);
      else renderSidebar();
    },
    'community:update': (c) => {
      const i = state.communities.findIndex((x) => x.id === c.id);
      if (i !== -1) state.communities[i] = c;
      if (state.current?.id === c.id) Object.assign(state.current, c);
      renderRail();
      renderSidebar();
    },
    'community:delete': ({ id }) => {
      state.communities = state.communities.filter((c) => c.id !== id);
      if (state.current?.id === id) {
        state.current = null;
        toast('That community is gone now');
        go('#/app');
      } else renderRail();
    },
    'member:join': ({ communityId, member }) => {
      if (state.current?.id !== communityId) return;
      if (!state.current.members.some((m) => m.id === member.id)) state.current.members.push(member);
      renderMembers();
    },
    'member:leave': ({ communityId, userId }) => {
      if (state.current?.id !== communityId) return;
      state.current.members = state.current.members.filter((m) => m.id !== userId);
      renderMembers();
    },
  });
  state.source.onerror = () => {
    // EventSource reconnects by itself. If our session died, bail out.
    Api.me().catch((err) => err.status === 401 && logout(true));
  };
}

// channelId -> communityId for channels we have seen, so unread dots land on the right community.
const channelMap = new Map();
function findCommunityOfChannel(channelId) {
  return channelMap.get(channelId);
}

function mentionPattern() {
  return new RegExp(`(^|\\s)@${state.me.username.replace(/\./g, '\\.')}(?![\\w.])`, 'i');
}

function notify(msg) {
  const mentioned = mentionPattern().test(msg.content);
  if (!mentioned || document.visibilityState === 'visible') return;
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(`${msg.author.displayName} mentioned you`, { body: msg.content.slice(0, 140) });
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && state.channelId) {
    state.unread.delete(state.channelId);
    renderMessages();
    renderSidebar();
  }
});

function clearTyping(channelId, userId) {
  state.typing.get(channelId)?.delete(userId);
  if (channelId === state.channelId) renderTyping();
}

setInterval(() => {
  const map = state.typing.get(state.channelId);
  if (!map) return;
  let changed = false;
  for (const [uid, t] of map) if (t.until < Date.now()) { map.delete(uid); changed = true; }
  if (changed) renderTyping();
}, 1000);

// ------------------------------------------------------------ rendering

function renderMe() {
  const me = state.me;
  $('#me-avatar').replaceWith(Object.assign(avatar({ ...me }, ''), { id: 'me-avatar' }));
  $('#me-avatar').dataset.online = 'true';
  $('#me-name').textContent = me.displayName;
  $('#me-status').textContent = me.status || `@${me.username}`;
}

function renderRail() {
  const list = $('#community-list');
  list.replaceChildren(...state.communities.map((c) => {
    const btn = h('button', {
      class: `rail-btn${state.current?.id === c.id ? ' active' : ''}`,
      title: c.name,
      onclick: () => go(`#/app/${c.id}`),
    }, c.icon || initial(c.name));
    btn.style.background = state.current?.id === c.id ? c.color : '';
    btn.addEventListener('mouseenter', () => (btn.style.background = c.color));
    btn.addEventListener('mouseleave', () => (btn.style.background = state.current?.id === c.id ? c.color : ''));
    if (state.unreadCommunities.has(c.id)) btn.append(h('span', { class: 'unread' }));
    return btn;
  }));
  $('#home-btn').classList.toggle('active', !state.current);
}

function renderSidebar() {
  const c = state.current;
  const owner = c && c.ownerId === state.me.id;
  $('#community-name').textContent = c ? c.name : 'Home';
  $('#community-menu-btn').hidden = !c;
  $('#channels-label').hidden = !c;
  $('#add-channel-btn').hidden = !owner;
  if (!c) return $('#channel-list').replaceChildren();
  for (const ch of c.channels) channelMap.set(ch.id, c.id);
  $('#channel-list').replaceChildren(...c.channels.map((ch) => h('li', {
    class: `channel${ch.id === state.channelId ? ' active' : ''}${state.unread.has(ch.id) ? ' unread' : ''}`,
    onclick: (e) => !e.target.closest('.ch-edit') && go(`#/app/${c.id}/${ch.id}`),
  },
  h('span', { class: 'hash' }, '#'),
  h('span', { class: 'name' }, ch.name),
  owner && h('button', { class: 'icon-btn small ch-edit', title: 'Edit channel', onclick: () => openChannelSettings(ch) }, '⚙'))));
}

function renderChatHead() {
  const ch = state.current?.channels.find((c) => c.id === state.channelId);
  if (!ch) return;
  $('#chat-hash').hidden = false;
  $('#chat-title').textContent = ch.name;
  $('#chat-topic').textContent = ch.topic || '';
  $('#members-toggle').hidden = false;
  document.title = `#${ch.name} | ${state.current.name} | Grove`;
}

function renderMembers() {
  if (!state.current) return;
  const members = [...state.current.members].sort((a, b) => a.displayName.localeCompare(b.displayName));
  const on = members.filter((m) => m.online || m.id === state.me.id);
  const off = members.filter((m) => !(m.online || m.id === state.me.id));
  const row = (m) => {
    const av = avatar(m);
    av.dataset.online = String(m.online || m.id === state.me.id);
    return h('div', { class: `member${on.includes(m) ? '' : ' offline'}`, onclick: () => openProfile(m) },
      av,
      h('div', { class: 'm-text' },
        h('b', {}, m.displayName, m.id === state.current.ownerId ? h('span', { class: 'crown', title: 'Owner' }, '👑') : null),
        m.status ? h('span', { class: 'muted small' }, m.status) : null));
  };
  $('#member-list').replaceChildren(
    h('h4', {}, `Online · ${on.length}`), ...on.map(row),
    ...(off.length ? [h('h4', {}, `Offline · ${off.length}`), ...off.map(row)] : []));
}

function renderTyping() {
  const map = state.typing.get(state.channelId);
  const names = map ? [...map.values()].map((t) => t.name) : [];
  const el = $('#typing');
  if (!names.length) el.textContent = '';
  else if (names.length === 1) el.innerHTML = `<b>${escapeHtml(names[0])}</b> is typing...`;
  else if (names.length < 4) el.innerHTML = `${names.map((n) => `<b>${escapeHtml(n)}</b>`).join(', ')} are typing...`;
  else el.textContent = 'Several people are typing...';
}

function renderMessages(scrollToEnd = false) {
  const box = $('#messages');
  const list = state.messages.get(state.channelId);
  const ch = state.current?.channels.find((c) => c.id === state.channelId);
  if (!list || !ch) return;
  const nearBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 120;
  const prevHeight = box.scrollHeight;
  const prevTop = box.scrollTop;

  const nodes = [];
  if (state.exhausted.has(ch.id)) {
    nodes.push(h('div', { class: 'intro' },
      h('div', { class: 'big-hash' }, '#'),
      h('h2', {}, `Welcome to #${ch.name}!`),
      h('p', { class: 'muted' }, ch.topic ? ch.topic : `This is the start of the #${ch.name} channel.`)));
  }
  let prev = null;
  const mentionRe = mentionPattern();
  for (const m of list) {
    const newDay = !prev || new Date(prev.createdAt).toDateString() !== new Date(m.createdAt).toDateString();
    if (newDay) nodes.push(h('div', { class: 'day' }, fmtDay(m.createdAt)));
    const cont = !newDay && prev.authorId === m.authorId && new Date(m.createdAt) - new Date(prev.createdAt) < GROUP_MS;
    nodes.push(messageNode(m, cont, mentionRe.test(m.content)));
    prev = m;
  }
  box.replaceChildren(...nodes);

  if (scrollToEnd || nearBottom) box.scrollTop = box.scrollHeight;
  else if (box.dataset.loadingOlder) box.scrollTop = box.scrollHeight - prevHeight + prevTop;
  else box.scrollTop = prevTop;
}

function messageNode(m, cont, mentioned) {
  const author = m.author || { displayName: 'Deleted user', username: 'deleted', color: '#666' };
  const mine = m.authorId === state.me.id;
  const canDelete = mine || state.current?.ownerId === state.me.id;
  const editing = state.editing === m.id;

  const body = editing ? editBox(m) : h('div', { class: 'body', html: renderMarkdown(m.content) + (m.editedAt ? '<span class="edited">(edited)</span>' : '') });

  const reactions = Object.entries(m.reactions || {});
  const node = h('div', { class: `msg${cont ? ' cont' : ''}${mentioned ? ' mentioned' : ''}${m.pending ? ' pending' : ''}`, dataset: { id: m.id } },
    Object.assign(avatar(author, 'lg'), { onclick: () => m.author && openProfile(m.author) }),
    h('span', { class: 'hover-time', title: fmtStamp(m.createdAt) }, fmtTime(m.createdAt)),
    h('div', { class: 'meta' },
      h('span', { class: 'author', style: `color:${author.color}`, onclick: () => m.author && openProfile(m.author) }, author.displayName),
      h('span', { class: 'time', title: new Date(m.createdAt).toLocaleString() }, fmtStamp(m.createdAt))),
    body,
    reactions.length ? h('div', { class: 'reactions' }, reactions.map(([emoji, users]) =>
      h('button', {
        class: `reaction${users.includes(state.me.id) ? ' mine' : ''}`,
        title: users.map((u) => state.current?.members.find((x) => x.id === u)?.displayName || 'someone').join(', '),
        onclick: () => react(m.id, emoji),
      }, `${emoji} ${users.length}`))) : null,
    m.pending || editing ? null : h('div', { class: 'msg-tools' },
      h('button', { class: 'icon-btn', title: 'Add reaction', onclick: (e) => pickEmoji(e.currentTarget, (emoji) => react(m.id, emoji)) }, '😊'),
      h('button', { class: 'icon-btn', title: 'Reply', onclick: () => quoteReply(m) }, '↩'),
      mine && h('button', { class: 'icon-btn', title: 'Edit', onclick: () => startEdit(m.id) }, '✏️'),
      canDelete && h('button', { class: 'icon-btn', title: 'Delete', onclick: (e) => deleteMessage(m, e.shiftKey) }, '🗑️')));
  return node;
}

function editBox(m) {
  const ta = h('textarea', { maxlength: 4000 });
  ta.value = m.content;
  const save = async () => {
    const content = ta.value.trim();
    if (!content) return deleteMessage(m);
    if (content === m.content) return stopEdit();
    try {
      await Api.editMessage(m.id, content);
      stopEdit();
    } catch (err) { fail(err); }
  };
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save(); }
    if (e.key === 'Escape') { e.preventDefault(); stopEdit(); }
  });
  requestAnimationFrame(() => { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); });
  return h('div', { class: 'edit-box' }, ta,
    h('div', { class: 'small muted' }, 'escape to ', h('a', { onclick: stopEdit }, 'cancel'), ' · enter to ', h('a', { onclick: save }, 'save')));
}

function startEdit(id) {
  state.editing = id;
  renderMessages();
}

function stopEdit() {
  state.editing = null;
  renderMessages();
  $('#composer-input').focus();
}

async function deleteMessage(m, skipConfirm) {
  if (!skipConfirm && !(await confirmBox('Delete message', 'Are you sure? This cannot be undone. (Tip: hold Shift to skip this.)', 'Delete'))) return;
  try {
    await Api.deleteMessage(m.id);
    if (state.editing === m.id) state.editing = null;
  } catch (err) { fail(err); }
}

async function react(id, emoji) {
  try { await Api.react(id, emoji); } catch (err) { fail(err); }
}

function quoteReply(m) {
  const input = $('#composer-input');
  const quote = m.content.split('\n').slice(0, 3).map((l) => `> ${l}`).join('\n');
  input.value = `${quote}\n@${m.author?.username || ''} ${input.value}`;
  autosize();
  input.focus();
}

function pickEmoji(anchor, done) {
  document.querySelector('.emoji-pop')?.remove();
  const pop = h('div', { class: 'emoji-pop' }, EMOJI.map((e) => h('button', { onclick: () => { pop.remove(); done(e); } }, e)));
  document.body.append(pop);
  const r = anchor.getBoundingClientRect();
  const w = pop.offsetWidth;
  const ht = pop.offsetHeight;
  pop.style.left = `${Math.max(8, Math.min(r.right - w, innerWidth - w - 8))}px`;
  pop.style.top = `${r.top - ht - 6 > 8 ? r.top - ht - 6 : r.bottom + 6}px`;
  setTimeout(() => document.addEventListener('click', function off(e) {
    if (!pop.contains(e.target)) { pop.remove(); document.removeEventListener('click', off); }
  }));
}

// Older history when scrolling up.
$('#messages').addEventListener('scroll', async (e) => {
  const box = e.target;
  const chid = state.channelId;
  if (box.scrollTop > 80 || !chid || state.exhausted.has(chid) || box.dataset.loadingOlder) return;
  const list = state.messages.get(chid);
  if (!list?.length) return;
  box.dataset.loadingOlder = '1';
  try {
    const older = await Api.messages(chid, list[0].id);
    if (older.length < 50) state.exhausted.add(chid);
    state.messages.set(chid, [...older, ...state.messages.get(chid)]);
    if (state.channelId === chid) renderMessages();
  } catch (err) {
    fail(err);
  } finally {
    delete box.dataset.loadingOlder;
  }
});

// Spoilers reveal on click.
$('#messages').addEventListener('click', (e) => e.target.closest('.spoiler')?.classList.add('shown'));

// ------------------------------------------------------------ composer

const input = $('#composer-input');
function autosize() {
  input.style.height = 'auto';
  input.style.height = `${Math.min(input.scrollHeight, 200)}px`;
}

let lastTyping = 0;
input.addEventListener('input', () => {
  autosize();
  if (input.value.trim() && Date.now() - lastTyping > 3000 && state.channelId) {
    lastTyping = Date.now();
    Api.typing(state.channelId).catch(() => {});
  }
});

input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
    e.preventDefault();
    $('#composer').requestSubmit();
  }
  if (e.key === 'ArrowUp' && !input.value) {
    const mine = [...(state.messages.get(state.channelId) || [])].reverse().find((m) => m.authorId === state.me.id && !m.pending);
    if (mine) { e.preventDefault(); startEdit(mine.id); }
  }
});

$('#composer').addEventListener('submit', async (e) => {
  e.preventDefault();
  const content = input.value.trim();
  const chid = state.channelId;
  if (!content || !chid) return;
  if (content.length > 4000) return toast('Messages can be at most 4000 characters', true);
  input.value = '';
  autosize();
  lastTyping = 0;
  const temp = {
    id: `tmp-${Math.random().toString(36).slice(2)}`, pending: true, channelId: chid, authorId: state.me.id,
    author: state.me, content, createdAt: new Date().toISOString(), reactions: {},
  };
  state.messages.get(chid).push(temp);
  renderMessages(true);
  try {
    const msg = await Api.send(chid, content);
    const list = state.messages.get(chid);
    const i = list.indexOf(temp);
    if (i !== -1) {
      if (list.some((m) => m.id === msg.id)) list.splice(i, 1);
      else list[i] = msg;
    }
  } catch (err) {
    const list = state.messages.get(chid);
    list.splice(list.indexOf(temp), 1);
    input.value = content;
    autosize();
    fail(err);
  }
  if (state.channelId === chid) renderMessages(true);
});

// ------------------------------------------------------------ modals

function openModal(...children) {
  const body = $('#modal-body');
  body.replaceChildren(...children);
  $('#modal').hidden = false;
  requestAnimationFrame(() => body.querySelector('input, textarea, button.btn-primary')?.focus());
}

function closeModal() {
  $('#modal').hidden = true;
  $('#modal-body').replaceChildren();
}

$('#modal').addEventListener('mousedown', (e) => e.target.id === 'modal' && closeModal());
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!$('#modal').hidden) closeModal();
    document.querySelector('.emoji-pop')?.remove();
    closeDrawer();
  }
});

function confirmBox(title, text, okLabel = 'OK') {
  return new Promise((resolve) => {
    const done = (v) => { closeModal(); resolve(v); };
    openModal(h('h2', {}, title), h('p', { class: 'muted' }, text),
      h('div', { class: 'row' },
        h('button', { class: 'btn btn-ghost', onclick: () => done(false) }, 'Cancel'),
        h('button', { class: 'btn btn-danger', onclick: () => done(true) }, okLabel)));
  });
}

function formModal(title, fields, submitLabel, onSubmit, extra = []) {
  const err = h('p', { class: 'error', hidden: true });
  const btn = h('button', { class: 'btn btn-primary', type: 'submit' }, submitLabel);
  const form = h('form', { class: 'modal-form', style: 'display:grid;gap:14px' },
    h('h2', {}, title), ...fields, err,
    h('div', { class: 'row' }, h('button', { class: 'btn btn-ghost', type: 'button', onclick: closeModal }, 'Cancel'), btn),
    ...extra);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btn.disabled = true;
    err.hidden = true;
    try {
      await onSubmit(new FormData(form));
    } catch (ex) {
      err.textContent = ex.message;
      err.hidden = false;
    } finally {
      btn.disabled = false;
    }
  });
  openModal(form);
}

function field(label, attrs, value = '') {
  const tag = attrs.type === 'textarea' ? 'textarea' : 'input';
  const el = h(tag, { ...attrs, type: tag === 'input' ? attrs.type || 'text' : null });
  el.value = value;
  return h('label', {}, label, el);
}

function openAddCommunity() {
  openModal(
    h('h2', {}, 'Add a community'),
    h('p', { class: 'muted' }, 'Your community is where you and your friends hang out.'),
    h('div', { class: 'split' },
      h('button', { class: 'choice', onclick: openCreate }, '🌱', h('b', {}, 'Create my own'), h('span', { class: 'muted small' }, 'Start fresh with #welcome and #general')),
      h('button', { class: 'choice', onclick: () => openJoin() }, '🔗', h('b', {}, 'Join one'), h('span', { class: 'muted small' }, 'Use an invite code from a friend'))));
}

function openCreate() {
  formModal('Create a community', [
    field('Name', { name: 'name', required: true, minlength: 2, maxlength: 40, placeholder: "mira's hangout" }),
    field('Icon (an emoji, optional)', { name: 'icon', maxlength: 8, placeholder: '🎮' }),
  ], 'Create', async (data) => {
    const c = await Api.createCommunity(data.get('name'), data.get('icon'));
    state.communities.push({ id: c.id, name: c.name, icon: c.icon, color: c.color, ownerId: c.ownerId });
    state.current = c;
    closeModal();
    go(`#/app/${c.id}`);
  });
}

function openJoin(prefill = '') {
  const preview = h('div', { class: 'muted small' });
  const codeField = field('Invite code or link', { name: 'code', required: true, placeholder: 'aB3dE6fG or http://localhost:3000/#/invite/aB3dE6fG' }, prefill);
  const parse = (v) => String(v).trim().split('/').pop();
  const showPreview = async () => {
    const code = parse(codeField.querySelector('input').value);
    if (!code) return (preview.textContent = '');
    try {
      const c = await Api.previewInvite(code);
      preview.textContent = `${c.icon || '🌳'} ${c.name} · ${c.memberCount} member${c.memberCount === 1 ? '' : 's'}`;
    } catch { preview.textContent = ''; }
  };
  codeField.querySelector('input').addEventListener('change', showPreview);
  formModal('Join a community', [h('p', { class: 'muted' }, 'Enter an invite to join an existing community.'), codeField, preview], 'Join', async (data) => {
    const c = await Api.joinInvite(parse(data.get('code')));
    if (!state.communities.some((x) => x.id === c.id)) {
      state.communities.push({ id: c.id, name: c.name, icon: c.icon, color: c.color, ownerId: c.ownerId });
    }
    state.current = c;
    closeModal();
    toast(`Welcome to ${c.name}!`);
    go(`#/app/${c.id}`);
  });
  if (prefill) showPreview();
}

function openCommunitySettings() {
  const c = state.current;
  if (!c) return;
  const owner = c.ownerId === state.me.id;
  if (!owner) {
    return openModal(h('h2', {}, c.name),
      h('p', { class: 'muted' }, `${c.members.length} members. Ask the owner for an invite link to bring friends.`),
      h('div', { class: 'danger-zone' },
        h('button', { class: 'btn btn-danger', onclick: async () => {
          if (!(await confirmBox(`Leave ${c.name}`, 'You will need a new invite to come back.', 'Leave'))) return;
          try { await Api.leaveCommunity(c.id); } catch (err) { fail(err); }
        } }, 'Leave community')),
      h('div', { class: 'row' }, h('button', { class: 'btn btn-ghost', onclick: closeModal }, 'Close')));
  }
  const link = () => `${location.origin}/#/invite/${c.inviteCode}`;
  const inviteInput = h('input', { readonly: true });
  inviteInput.value = link();
  formModal('Community settings', [
    field('Name', { name: 'name', required: true, minlength: 2, maxlength: 40 }, c.name),
    field('Icon (emoji)', { name: 'icon', maxlength: 8 }, c.icon),
    h('label', {}, 'Invite link',
      h('div', { class: 'invite-code' }, inviteInput,
        h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => copy(inviteInput.value) }, 'Copy'),
        h('button', { class: 'btn btn-ghost', type: 'button', title: 'Make a new code. The old one stops working.', onclick: async () => {
          try {
            c.inviteCode = (await Api.resetInvite(c.id)).inviteCode;
            inviteInput.value = link();
            toast('New invite code made');
          } catch (err) { fail(err); }
        } }, 'Reset'))),
  ], 'Save', async (data) => {
    await Api.updateCommunity(c.id, { name: data.get('name'), icon: data.get('icon') });
    closeModal();
    toast('Saved');
  }, [h('div', { class: 'danger-zone' },
    h('button', { class: 'btn btn-danger', type: 'button', onclick: async () => {
      if (!(await confirmBox(`Delete ${c.name}`, 'This deletes every channel and message for everyone. There is no undo.', 'Delete forever'))) return;
      try { await Api.deleteCommunity(c.id); } catch (err) { fail(err); }
    } }, 'Delete community'))]);
}

function openCreateChannel() {
  formModal('Create channel', [
    field('Channel name', { name: 'name', required: true, maxlength: 32, placeholder: 'new-channel' }),
    field('Topic (optional)', { name: 'topic', maxlength: 160 }),
  ], 'Create', async (data) => {
    const ch = await Api.createChannel(state.current.id, data.get('name'), data.get('topic'));
    if (!state.current.channels.some((c) => c.id === ch.id)) state.current.channels.push(ch);
    closeModal();
    go(`#/app/${state.current.id}/${ch.id}`);
  });
}

function openChannelSettings(ch) {
  formModal(`Edit #${ch.name}`, [
    field('Channel name', { name: 'name', required: true, maxlength: 32 }, ch.name),
    field('Topic', { name: 'topic', maxlength: 160 }, ch.topic),
  ], 'Save', async (data) => {
    await Api.updateChannel(ch.id, { name: data.get('name'), topic: data.get('topic') });
    closeModal();
  }, [h('div', { class: 'danger-zone' },
    h('button', { class: 'btn btn-danger', type: 'button', onclick: async () => {
      if (!(await confirmBox(`Delete #${ch.name}`, 'All messages in this channel will be gone.', 'Delete'))) return;
      try { await Api.deleteChannel(ch.id); } catch (err) { fail(err); }
    } }, 'Delete channel'))]);
}

function openProfile(u) {
  const av = avatar(u, 'xl');
  av.dataset.online = String(u.online || u.id === state.me.id);
  openModal(h('div', { class: 'profile-card' }, av,
    h('h2', {}, u.displayName),
    h('span', { class: 'muted' }, `@${u.username}`),
    u.status ? h('p', {}, u.status) : null,
    u.createdAt ? h('span', { class: 'muted small' }, `Member since ${new Date(u.createdAt).toLocaleDateString()}`) : null),
  h('div', { class: 'row' },
    u.id !== state.me.id && state.channelId && h('button', { class: 'btn btn-ghost', onclick: () => {
      closeModal();
      input.value = `@${u.username} ${input.value}`;
      input.focus();
    } }, 'Mention'),
    h('button', { class: 'btn btn-primary', onclick: closeModal }, 'Close')));
}

function openSettings() {
  const me = state.me;
  let color = me.color;
  const swatches = h('div', { class: 'swatches' }, COLORS.map((c) => {
    const s = h('span', { class: `swatch${c === color ? ' on' : ''}`, title: c, onclick: () => {
      color = c;
      for (const x of swatches.children) x.classList.toggle('on', x === s);
    } });
    s.style.background = c;
    return s;
  }));
  let theme = 'system';
  try { theme = localStorage.getItem('grove.theme') || 'system'; } catch {}
  const themeSel = h('select', { name: 'theme' }, ['system', 'dark', 'light'].map((t) => h('option', { value: t, selected: t === theme }, t[0].toUpperCase() + t.slice(1))));
  const notif = 'Notification' in window && Notification.permission !== 'granted'
    ? h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => Notification.requestPermission().then((p) => toast(p === 'granted' ? 'Mention notifications on' : 'Notifications blocked')) }, '🔔 Enable mention notifications')
    : null;
  formModal('My account', [
    field('Display name', { name: 'displayName', required: true, maxlength: 32 }, me.displayName),
    field('Status', { name: 'status', maxlength: 80, placeholder: 'vibing 🎧' }, me.status),
    h('label', {}, 'Avatar color', swatches),
    h('label', {}, 'Theme', themeSel),
    h('details', {}, h('summary', { class: 'small muted', style: 'cursor:pointer' }, 'Change password'),
      h('div', { style: 'display:grid;gap:10px;margin-top:10px' },
        field('Current password', { name: 'currentPassword', type: 'password', autocomplete: 'current-password' }),
        field('New password', { name: 'password', type: 'password', minlength: 6, autocomplete: 'new-password' }))),
    notif,
  ], 'Save', async (data) => {
    const fields = { displayName: data.get('displayName'), status: data.get('status'), color };
    if (data.get('password')) Object.assign(fields, { password: data.get('password'), currentPassword: data.get('currentPassword') });
    state.me = await Api.updateMe(fields);
    applyTheme(data.get('theme'));
    renderMe();
    closeModal();
    toast('Saved');
  }, [h('div', { class: 'danger-zone' }, h('button', { class: 'btn btn-danger', type: 'button', onclick: () => logout() }, 'Log out'))]);
}

function applyTheme(t) {
  try { localStorage.setItem('grove.theme', t); } catch {}
  if (t === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = t;
}

async function copy(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast('Copied!');
  } catch {
    toast('Could not copy. Select it and copy by hand.', true);
  }
}

// ------------------------------------------------------------ wiring

function closeDrawer() { $('#view-app').classList.remove('drawer'); }

$('#home-btn').addEventListener('click', () => { state.current = null; showHome(); history.replaceState(null, '', '#/app'); try { localStorage.removeItem('grove.last'); } catch {} });
$('#add-community-btn').addEventListener('click', openAddCommunity);
$('#community-menu-btn').addEventListener('click', openCommunitySettings);
$('#community-head').addEventListener('dblclick', openCommunitySettings);
$('#add-channel-btn').addEventListener('click', openCreateChannel);
$('#settings-btn').addEventListener('click', openSettings);
$('#me-panel').addEventListener('click', (e) => !e.target.closest('button') && openProfile(state.me));
$('#menu-toggle').addEventListener('click', () => $('#view-app').classList.toggle('drawer'));
$('#members-toggle').addEventListener('click', () => {
  const app = $('#view-app');
  if (innerWidth <= 1100) app.classList.toggle('show-members');
  else app.classList.toggle('no-members');
});
$('#chat').addEventListener('click', (e) => {
  if (!e.target.closest('#menu-toggle')) closeDrawer();
  if (!e.target.closest('#members-toggle')) $('#view-app').classList.remove('show-members');
});
$('#home-panel').addEventListener('click', (e) => {
  const action = e.target.closest('[data-action]')?.dataset.action;
  if (action === 'create') openCreate();
  if (action === 'join') openJoin();
});

try { applyTheme(localStorage.getItem('grove.theme') || 'system'); } catch {}
route();

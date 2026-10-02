// Tiny client for the Grove REST API and its live event stream.
'use strict';

const Api = (() => {
  let token = null;
  try { token = localStorage.getItem('grove.token'); } catch {}

  function setToken(t) {
    token = t;
    try {
      if (t) localStorage.setItem('grove.token', t);
      else localStorage.removeItem('grove.token');
    } catch {}
  }

  async function request(method, path, body) {
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let res;
    try {
      res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    } catch {
      throw Object.assign(new Error('Cannot reach the Grove server. Is it running?'), { status: 0 });
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw Object.assign(new Error(data.error || `Request failed (${res.status})`), { status: res.status });
    return data;
  }

  const get = (p) => request('GET', p);
  const post = (p, b = {}) => request('POST', p, b);
  const patch = (p, b) => request('PATCH', p, b);
  const del = (p) => request('DELETE', p);
  const enc = encodeURIComponent;

  function events(handlers) {
    const source = new EventSource(`/api/events?token=${enc(token)}`);
    for (const [name, fn] of Object.entries(handlers)) {
      source.addEventListener(name, (e) => fn(e.data ? JSON.parse(e.data) : null));
    }
    return source;
  }

  return {
    get token() { return token; },
    setToken,
    events,
    register: (username, password, displayName) => post('/api/auth/register', { username, password, displayName }),
    login: (username, password) => post('/api/auth/login', { username, password }),
    logout: () => post('/api/auth/logout'),
    me: () => get('/api/me'),
    updateMe: (fields) => patch('/api/me', fields),
    communities: () => get('/api/communities'),
    community: (id) => get(`/api/communities/${enc(id)}`),
    createCommunity: (name, icon) => post('/api/communities', { name, icon }),
    updateCommunity: (id, fields) => patch(`/api/communities/${enc(id)}`, fields),
    deleteCommunity: (id) => del(`/api/communities/${enc(id)}`),
    leaveCommunity: (id) => post(`/api/communities/${enc(id)}/leave`),
    resetInvite: (id) => post(`/api/communities/${enc(id)}/invite`),
    previewInvite: (code) => get(`/api/invites/${enc(code)}`),
    joinInvite: (code) => post(`/api/invites/${enc(code)}`),
    createChannel: (cid, name, topic) => post(`/api/communities/${enc(cid)}/channels`, { name, topic }),
    updateChannel: (id, fields) => patch(`/api/channels/${enc(id)}`, fields),
    deleteChannel: (id) => del(`/api/channels/${enc(id)}`),
    messages: (chid, before) => get(`/api/channels/${enc(chid)}/messages${before ? `?before=${enc(before)}` : ''}`),
    send: (chid, content) => post(`/api/channels/${enc(chid)}/messages`, { content }),
    editMessage: (id, content) => patch(`/api/messages/${enc(id)}`, { content }),
    deleteMessage: (id) => del(`/api/messages/${enc(id)}`),
    react: (id, emoji) => post(`/api/messages/${enc(id)}/reactions`, { emoji }),
    typing: (chid) => post(`/api/channels/${enc(chid)}/typing`),
  };
})();

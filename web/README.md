# Grove

A community chat app that runs entirely on your own machine. Communities, channels, realtime chat, reactions, invite links, presence and typing indicators. Plain HTML, CSS and JavaScript on the front, a zero-dependency Node server on the back.

## Run it

You need Node 18 or newer. Nothing to install.

```bash
cd web
npm start
```

Open http://localhost:3000, make an account and start a community.

To let other devices on your network join, listen on all interfaces:

```bash
HOST=0.0.0.0 PORT=8080 npm start
```

| Variable     | Default       | What it does                    |
|--------------|---------------|---------------------------------|
| `PORT`       | `3000`        | Port to listen on               |
| `HOST`       | `127.0.0.1`   | Address to bind                 |
| `GROVE_DATA` | `web/data`    | Folder where `db.json` is kept  |

Everything is stored in `data/db.json`. Passwords are hashed with scrypt. Delete the file to start over.

## Features

- Accounts with display names, statuses, avatar colors and password changes
- Communities with an emoji icon, created with `#welcome` and `#general`
- Invite links that the owner can copy or reset
- Channels with topics (owners can create, rename and delete)
- Realtime messages, edits, deletes and emoji reactions
- Online and offline members, typing indicators, unread markers
- Markdown: `**bold**`, `*italic*`, `__underline__`, `~~strike~~`, `` `code` ``, code blocks, `||spoilers||`, `> quotes`, links and `@mentions`
- Mention notifications when the tab is in the background
- Light, dark or system theme, and a phone layout
- Keyboard: Enter sends, Shift+Enter adds a line, Up arrow edits your last message, Escape cancels

## API

All endpoints take and return JSON. Send `Authorization: Bearer <token>` after logging in.

| Method | Path | Notes |
|--------|------|-------|
| POST | `/api/auth/register` | `{username, password, displayName?}` returns `{token, user}` |
| POST | `/api/auth/login` | `{username, password}` returns `{token, user}` |
| POST | `/api/auth/logout` | |
| GET / PATCH | `/api/me` | PATCH takes `displayName`, `status`, `color`, `password` + `currentPassword` |
| GET / POST | `/api/communities` | POST takes `{name, icon?}` |
| GET / PATCH / DELETE | `/api/communities/:id` | PATCH and DELETE are owner only |
| POST | `/api/communities/:id/leave` | |
| POST | `/api/communities/:id/invite` | Owner only. Makes a new invite code |
| GET / POST | `/api/invites/:code` | GET previews (no login needed), POST joins |
| POST | `/api/communities/:id/channels` | Owner only. `{name, topic?}` |
| PATCH / DELETE | `/api/channels/:id` | Owner only |
| GET / POST | `/api/channels/:id/messages` | GET takes `?before=<messageId>&limit=50` |
| PATCH / DELETE | `/api/messages/:id` | Edit is author only. Delete is author or owner |
| POST | `/api/messages/:id/reactions` | `{emoji}` toggles your reaction |
| POST | `/api/channels/:id/typing` | |
| GET | `/api/events?token=` | Server-Sent Events stream |

Events on the stream: `ready`, `presence`, `user:update`, `message:create`, `message:update`, `message:delete`, `typing`, `channel:create`, `channel:update`, `channel:delete`, `community:update`, `community:delete`, `member:join`, `member:leave`.

## Tests

```bash
npm test
```

## Layout

```
web/
  server.js        HTTP server, REST API, event stream, JSON storage
  public/
    index.html     Landing page, login and the app shell
    styles.css     All styling, light and dark
    api.js         Small API client
    app.js         Routing, rendering and live updates
  test/            API tests (node:test)
```

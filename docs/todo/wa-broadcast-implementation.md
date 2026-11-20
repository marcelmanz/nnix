# WhatsApp broadcast service — implementation

## Goal

Send the same message to many bridged WhatsApp chats (via mautrix-whatsapp)
as a **persistent, supervised service** on mlab — not a fire-and-forget script.
The service must answer three questions at any time:

- **what** was not sent
- **why** it failed (the error)
- **when** it will retry (countdown)

This replaces the "matrix-commander loop / in-memory Python retry" walkthrough
with something that survives a reboot, a crash, or a rate-limit, and tells you
its own state.

## Why not the pasted walkthrough (as-is)

- **It ignores E2E.** Our bridge has `encryption.require = true`
  (`hosts/mlab/mautrix-whatsapp.nix`). A plaintext `m.room.message` from a dumb
  HTTP client is **not relayed** — the bridge only forwards messages it can
  decrypt and refuses unencrypted ones. The sender **must** be a Megolm-capable
  Matrix client logged in as `@admin:marcel.cool` (the single bridge user). This
  is the one detail that decides whether anything delivers at all.
- **It's fire-and-forget.** matrix-commander and the in-memory 5-retry loop lose
  all state when the process exits. "See unsent + why + when retry" is a
  **durable, queryable outbox** — there is no way to get that without
  persistence. So: SQLite, one table, the source of truth.
- **Its "rate-limit" section is correct and worth keeping** (WhatsApp spam
  heuristics are outside the bridge's control). The pacing + caps below are the
  operational form of that section.

## Architecture

```
            enqueue (CLI)                      worker (daemon)
  wa-broadcast enqueue ──┐                ┌─► drain due rows
   "text" --rooms a,b    │                │  send via matrix-nio (E2E)
                         ▼                │  update row (sent/retry/dead)
                  ┌─────────────┐         │
                  │  SQLite     │◄────────┘
                  │  outbox     │
                  │ (queue=src) │
                  └─────────────┘
                         ▲
                         │             status (CLI)        future: web (phase 2)
                         └──── wa-broadcast status ──┐   https://wa.marcel.cool
                              reads the same table    │   behind Authelia (proxy.nix)
```

- **One Python package** `wa-broadcast` (CLI + worker, same binary, subcommands).
- **One systemd service** `wa-broadcast-worker` — long-lived, `Restart=on-failure`.
- **One SQLite file** `/var/lib/wa-broadcast/queue.db` — the queue _and_ the
  status view; no second store.
- **One nio session** as `@admin:marcel.cool`, device `WABBCAST`, crypto store
  persisted next to the DB — no per-message re-login/re-sync.
- **nixpkgs has all deps**: `matrix-nio`, `python-olm` (libolm bindings),
  `matrix-commander` (unused here, but available). Verified against the flake's
  nixpkgs. `olm-3.2.16` is already in `permittedInsecurePackages` (flake.nix).

## Prerequisites (user does these, outside Nix)

One-time, ~2 minutes. Goal: a long-lived access token for a **dedicated device**
on the account that owns the bridged WhatsApp number (`@admin:marcel.cool`).

1. **Create the device + token** (fresh `device_id`, so it's revocable and not
   tied to your main Element session):

   ```bash
   curl -XPOST http://localhost:8088/_matrix/client/v3/login \
     -H 'Content-Type: application/json' \
     -d '{
       "type":"m.login.password",
       "identifier":{"type":"m.id.user","user":"admin"},
       "password":"<admin password>",
       "device_id":"WABBCAST"
     }' | jq .access_token
   ```

   (Run on mlab, or point at `https://matrix.marcel.cool` from your laptop.)
   Copy the `access_token` value.

2. **Verify the new device** — required so the bridge shares Megolm room keys to
   it. mautrix-whatsapp defaults to `key_sharing.require_verification = true`, so
   an unverified device receives _no_ keys and can't encrypt to the portals. In
   Element (your existing, verified admin session) → Settings → Security &
   Privacy → "Verify this session" (or Sessions → `WABBCAST` → Verify). One click;
   never repeats for that device.

   > If you'd rather not verify: set the bridge
   > `encryption.key_sharing.require_verification = false` (less secure — shares
   > keys to any of admin's devices). Not recommended; verify-once is cleaner.

3. **Store the token in sops** (`secrets/mlab.yaml`):

   ```yaml
   wa_broadcast_matrix_token: <paste the access token>
   ```

## Outbox schema

The table _is_ the "see unsent + why + when retry" view — no dashboard needed
for MVP.

```sql
CREATE TABLE outbox (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id      TEXT NOT NULL,                       -- one enqueue call = one batch
  room_id       TEXT NOT NULL,
  body          TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending',      -- pending | sent | retry | dead
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT,                                -- the "why" (NULL until a failure)
  next_retry_at INTEGER,                             -- unix s; NULL = not retrying
  event_id      TEXT,                                -- Matrix event id on success
  created_at    INTEGER NOT NULL,
  sent_at       INTEGER
);
CREATE INDEX idx_drain ON outbox(status, next_retry_at) WHERE status IN ('pending','retry');
```

## Worker — failure taxonomy

Drain loop (every ~1s; `WA_PACE_SECONDS` sleep between sends, default 0.4):

```sql
SELECT * FROM outbox
 WHERE status IN ('pending','retry')
   AND (next_retry_at IS NULL OR next_retry_at <= strftime('%s','now'))
 ORDER BY id LIMIT 50;
```

Send one via `AsyncClient.room_send(...)` (nio encrypts transparently for
encrypted rooms once the crypto store is loaded), then update the row:

| Outcome                           | status  | next_retry_at             | last_error            |
| --------------------------------- | ------- | ------------------------- | --------------------- |
| sent                              | `sent`  | NULL                      | NULL (set event_id)   |
| 429 + `Retry-After: N`            | `retry` | now + N                   | `429 retry_after=Ns`  |
| 5xx / network / timeout           | `retry` | now + min(2^attempts, 1h) | the error             |
| attempts ≥ `WA_MAX_ATTEMPTS` (10) | `dead`  | NULL                      | `max_attempts: <err>` |
| 403 / 404 / 400 (permanent)       | `dead`  | NULL immediately          | `http 403 …`          |

Permanent 4xx → dead on the first hit (never retried). Transient → exponential
backoff capped at 1h, up to 10 attempts. The inter-message `sleep(0.4)` keeps
you off WhatsApp's spam heuristics (see section 3 of the original walkthrough —
that part is correct and retained).

## CLI

```
wa-broadcast enqueue  "🚀 Deploy succeeded" --rooms !a:marcel.cool,!b:marcel.cool
wa-broadcast enqueue  "🚀 Deploy succeeded" --rooms-file wa-rooms.txt
wa-broadcast status                      # not-sent rows: id, batch, room, status,
                                          #   attempts, last_error, retry-in (humanized)
wa-broadcast status --all                # include sent
wa-broadcast retry   <id>                 # dead → pending, retry now
wa-broadcast forget  <id>                # delete a row
wa-broadcast worker                      # the daemon (systemd runs this)
```

`--rooms-file` is one Matrix room MXID per line (Element → room settings →
Internal Room ID, or `matrix-commander -l`). Auto-discovery of bridged rooms
(scan joined rooms for the bridge's `m.bridge` state) is phase 2 — see below.

## Code changes — all in this repo

### 1. `packages/wa-broadcast/` — the Python package (3 files)

Follows the `discogs2xlsx` house pattern (`buildPythonApplication` + overlay).

**`packages/wa-broadcast/pyproject.toml`**

```toml
[project]
name = "wa-broadcast"
version = "0.1.0"
dependencies = ["matrix-nio", "python-olm"]

[project.scripts]
wa-broadcast = "wa_broadcast.cli:main"

[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[tool.setuptools]
py-modules = ["wa_broadcast"]
```

**`packages/wa-broadcast/wa_broadcast.py`** — single module:

- `init_db(path)` — create the schema above (idempotent).
- `enqueue(db, body, room_ids)` — insert rows, one `batch_id` (uuid4).
- `worker()` — login (token from env), `load_store()`, drain loop, send+update
  with the taxonomy above, `asyncio.sleep(WA_PACE_SECONDS)` between sends.
- `status(db, all=False)` / `retry(db, id)` / `forget(db, id)` — thin SQL.
- `cli:main(argv)` — dispatch subcommands.
- **Self-check** (ponytail rule, one runnable check, no framework): a `if
  __name__ == "__main__" and os.environ.get("WA_SELFTEST")` block that opens a
  temp DB, enqueues two rows, fakes a 429 + a success, asserts status flips to
  `retry`/`sent` and `next_retry_at` set correctly. Exits non-zero on mismatch.

  Key send call (the E2E-critical bit — nio encrypts when the room is encrypted
  and the store is loaded):

  ```python
  resp = await client.room_send(
      room_id,
      message_type="m.room.message",
      content={"msgtype": "m.text", "body": body},
      encrypt=True,
  )
  ```

**`packages/wa-broadcast/package.nix`**

```nix
{pkgs}:
pkgs.python3Packages.buildPythonApplication {
  pname = "wa-broadcast";
  version = "0.1.0";
  format = "pyproject";
  src = ./wa-broadcast;
  nativeBuildInputs = [ pkgs.python3Packages.setuptools ];
  propagatedBuildInputs = with pkgs.python3Packages; [ matrix-nio python-olm ];
  doCheck = false;
}
```

> Smaller alternative (not recommended): inline the Python via
> `writers.writePython3Application` in the module — one file, but untestable and
> the module balloons. A real service earns its own 3-file package.

### 2. `flake.nix` — register the overlay

Add one line beside the `discogs2xlsx`/`haralyzer` entries in the `overlays`
list:

```nix
(final: prev: {wa-broadcast = import ./packages/wa-broadcast/package.nix {inherit pkgs;};})
```

### 3. `hosts/mlab/wa-broadcast.nix` — the NixOS module

```nix
{config, pkgs, lib, ...}: {
  sops.secrets."wa_broadcast_matrix_token" = {owner = "wa-broadcast";};

  sops.templates."wa-broadcast.env" = {
    content = ''
      WA_MATRIX_HOMESERVER=http://localhost:8088   # Synapse direct, same as the bridge
      WA_MATRIX_USER=@admin:marcel.cool
      WA_MATRIX_DEVICE=WABBCAST
      WA_MATRIX_TOKEN=${config.sops.placeholder.wa_broadcast_matrix_token}
      WA_DB_PATH=/var/lib/wa-broadcast/queue.db
      WA_STORE_PATH=/var/lib/wa-broadcast/store
      WA_PACE_SECONDS=0.4
      WA_MAX_ATTEMPTS=10
    '';
    owner = "wa-broadcast";
    mode = "0400";
  };

  users.users.wa-broadcast = {
    isSystemUser = true;
    group = "wa-broadcast";
    home = "/var/lib/wa-broadcast";
    createHome = true;
  };
  users.groups.wa-broadcast = {};

  systemd.services.wa-broadcast-worker = {
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "matrix-synapse.service" "mautrix-whatsapp.service"];
    serviceConfig = {
      User = "wa-broadcast";
      Group = "wa-broadcast";
      StateDirectory = "wa-broadcast";
      EnvironmentFile = config.sops.templates."wa-broadcast.env".path;
      ExecStart = "${pkgs.wa-broadcast}/bin/wa-broadcast worker";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  environment.systemPackages = [pkgs.wa-broadcast];
}
```

`StateDirectory` creates `/var/lib/wa-broadcast` (owned by the service user);
the SQLite DB and nio crypto store live there and survive restarts/reboots. The
nio store persists Megolm keys, so a service restart re-loads them — no
re-verify, no re-key.

### 4. `hosts/mlab/default.nix` — import the module

Add to the `imports` list (alphabetical-ish, beside the other mlab modules):

```nix
    ./wa-broadcast.nix
```

## Deploy + test

```bash
nixos-rebuild switch --flake .#mlab --target-host root@mlab
```

1. **Self-test** (no Matrix round-trip): on mlab as root,

   ```bash
   sudo -u wa-broadcast WA_SELFTEST=1 wa-broadcast worker  # or however the entrypoint exposes it
   ```

   Expect exit 0. This proves the queue logic before touching the network.

2. **Unit check** — service up, store warm:

   ```bash
   ssh mlab 'systemctl status wa-broadcast-worker'
   ssh mlab 'journalctl -u wa-broadcast-worker -n 20 --no-pager'
   ```

   Look for "synced" / "logged in as @admin:marcel.cool (WABBCAST)".

3. **End-to-end** — enqueue to **one** room you control first (not the whole
   list), watch it deliver in WhatsApp, then check status:

   ```bash
   ssh mlab 'wa-broadcast enqueue "test from wa-broadcast" --rooms !<your-test-room>:marcel.cool'
   ssh mlab 'wa-broadcast status'
   ```

   Expect that row `status=sent`, `event_id` set, `last_error` NULL.

4. **Failure path** — enqueue with a bogus room id (`!not-a-real-room:marcel.cool`):
   expect `status=dead`, `last_error` ~ `http 404 …` on the first drain (permanent
   4xx, never retried). Enqueue many fast to a real room to confirm a 429 lands
   as `status=retry` with `next_retry_at` set — then delivers on retry.

5. **Verify E2E really happened** (the silent-fail risk): if a message shows
   `sent` but never appears in WhatsApp, the device isn't getting room keys —
   re-check step 2 of Prerequisites (device verification). Symptom in logs:
   nio "unable to encrypt" / "no session" warnings.

## Future generalization (NOT done now — listed so the design pays off)

### Phase 2a — status web page behind Authelia

Your `proxy.nix` already auto-gates any `services` entry with `protected = true`
via `auth_request`. Adding the page is ~one proxy entry + a read-only endpoint:

```nix
# in proxy.nix services attrset:
wabroadcast = {
  port = 8094;                         # choose a free port
  href = "https://wa.marcel.cool";
  protected = true;                    # ← Authelia gate applied automatically
};
```

Laziest implementation: add a `--serve-status :8094` mode to the **worker
process itself** (it already holds the DB open) returning read-only JSON of the
outbox + a tiny static HTML table. No second process, no second DB handle, no
new auth code — Authelia in front does the gating exactly as it does for
`searxng`, `pinchflat`, `stalwartadmin`. Keep it read-only (no enqueue button)
until you specifically want remote triggering.

### Phase 2b — auto-discovery of bridged WhatsApp rooms

~20 lines: on enqueue with no `--rooms`, sync joined rooms and filter by the
mautrix-whatsapp bridge marker (the `m.bridge` / `m.bridge` state event with
`bridge`/`com.beeper.whatsapp`), or by the portal room's `io.mautrix.whatsapp.*`
account-data. Then `enqueue "text"` with no args = "send to all my WhatsApp
chats" (pair with an `--exclude` list for the loud ones). Build after MVP so
phase 1 ships unblocked.

## Rollback

`systemctl stop wa-broadcast-worker`, revert the 4 code changes, `nixos-rebuild
switch`. The SQLite DB at `/var/lib/wa-broadcast/queue.db` stays harmlessly on
disk (delete it manually to fully clean up). The `WABBCAST` device on
`@admin:marcel.cool` survives — revoke it in Element → Settings → Sessions if
you want the token fully invalidated.

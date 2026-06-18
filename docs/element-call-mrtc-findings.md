# Element Call mRtc Setup — Findings

## Symptom
Element Call (served from `call.matrix.marcel.cool`) fails to establish a call
against the `marcel.cool` Synapse + LiveKit + lk-jwt-service stack. The browser
attempts to POST a LiveKit JWT request to a server-local URL it cannot reach.

## The real failure chain (all verified live on mlab)

### 1. Synapse advertises a browser-unreachable `livekit_service_url`  ← root cause
`hosts/mlab/matrix.nix` sets, in the Synapse `matrix_rtc` block:
```nix
matrix_rtc = {
  transports = [{
    type = "livekit";
    livekit_service_url = "http://localhost:8090";   # ← BUG: server-local
  }];
};
```
Verified live with an admin access token:
```
GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports (authed)
→ {"rtc_transports":[{"livekit_service_url":"http://localhost:8090","type":"livekit"}]}
```
A browser resolves `localhost` against the *user's own machine*, where no
lk-jwt-service runs → connection refused. (CORS would also fail since the
browser origin can't talk to `localhost:8090`.)

This is internally inconsistent with the rest of `matrix.nix`, which advertises
the public `https://matrix.marcel.cool/livekit/jwt` in both the element-call
`config.json` and the `.well-known` `rtc_foci`. But Synapse's value wins
(see discovery priority below), so the bad URL overrides the good ones.

### 2. nginx `/livekit/jwt/` proxy doesn't strip the prefix → lk-jwt 404s
```nix
locations."/livekit/jwt/" = {
  proxyPass = "http://127.0.0.1:8090";   # ← BUG: no trailing slash
  ...
};
```
Without a trailing slash on `proxy_pass`, nginx forwards the **full original
URI** to the upstream. So `POST /livekit/jwt/sfu/get` → upstream
`/livekit/jwt/sfu/get` → lk-jwt-service has no such route → `404 page not found`.

Verified: every public probe (`/livekit/jwt`, `/livekit/jwt/`, `/livekit/jwt/get_token`)
returns 404 through nginx, while the same paths work directly on `:8090` once the
prefix is stripped.

### 3. `.well-known` `rtc_foci` is an array of strings, not objects
```nix
"org.matrix.msc4143.rtc_foci" = ["https://${domain}/livekit/jwt"];
```  (string array — wrong)
Element Call 0.18 expects an array of `{type, livekit_service_url}` objects
(proven from the deployed bundle's source map, `LocalTransport.ts`:
`getFirstUsableTransport(wellKnownFoci)`). A string element has no `.type`, so
`getFirstUsableTransport` skips it and the well-known fallback silently no-ops.

This is latent (Synapse `rtc/transports` has higher priority, so the well-known
isn't reached while bug #1 is active), but it's still wrong per the MSC4143
contract and the official self-hosting guide.

## How Element Call discovers the transport (proven from bundle source)

Reverse-engineered from the deployed `element-call-0.18.0` bundle's source map
(`assets/index-CN5lfP4r.js.map` → `sourcesContent`). Transport selection
priority in `makeTransport` (`src/state/CallViewModel/localMember/LocalTransport.ts`):

1. dev setting `customLivekitUrl`
2. **`client._unstable_getRTCTransports()`** → `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports` (authed) → `.rtc_transports[].livekit_service_url`  ← used by default
3. `.well-known/matrix/client` → `org.matrix.msc4143.rtc_foci` (array of objects)
4. `Config.get().livekit.livekit_service_url` (from `/config.json`)

Then the JWT is fetched by appending a path to the chosen `livekit_service_url`
(`src/livekit/openIDSFU.ts`):
- **Legacy mode (default)** → `POST {livekit_service_url}/sfu/get`
  body: `{room, openid_token, device_id}`
- **Matrix 2.0 mode** → `POST {livekit_service_url}/get_token`
  body: `{room_id, slot_id, openid_token, member, delay_*}`

`matrixRTCMode` defaults to `Legacy` (`src/settings/settings.ts`). So with the
current bad config the browser issues exactly:
```
POST http://localhost:8090/sfu/get
```
and dies. No `/jwt`, no `/versions`, no `MISSING_MATRIX_RTC_TRANSPORT` — the
old doc's whole `/versions` narrative was chasing a ghost.

## The canonical fix (per official docs)

Sources: `element-hq/element-call` `docs/self_hosting.md` (master/livekit
branch) and `element-hq/lk-jwt-service` README (v0.4.4). Three coordinated
edits in `hosts/mlab/matrix.nix`:

1. **Synapse block** — advertise the public URL:
   ```nix
   livekit_service_url = "https://${domain}/livekit/jwt";
   ```
2. **nginx `/livekit/jwt/` location** — trailing slash on `proxyPass` to strip
   the prefix (official nginx example uses `proxy_pass http://localhost:8080/;`):
   ```nix
   locations."/livekit/jwt/" = {
     proxyPass = "http://127.0.0.1:8090/";   # ← trailing slash
     ...
   };
   ```
   This makes `/livekit/jwt/sfu/get` → upstream `/sfu/get` and
   `/livekit/jwt/get_token` → upstream `/get_token`, both served by
   lk-jwt-service 0.4.4. No rewrites, no second location.
3. **`.well-known` `rtc_foci`** — array of objects:
   ```nix
   "org.matrix.msc4143.rtc_foci" = [{
     type = "livekit";
     livekit_service_url = "https://${domain}/livekit/jwt";
   }];
   ```

### Discovery eagerly fetches a JWT (this is why the next bug surfaces as `MISSING_MATRIX_RTC_TRANSPORT`)

`makeTransport` does not just *list* candidate SFU URLs — for each candidate it
**calls `getSFUConfigWithOpenID` which POSTs `/sfu/get` (or `/get_token`) to get a
real LiveKit JWT**, treating a successful JWT response as proof the SFU is usable.
Only if every candidate's JWT fetch fails does it `throw new Mtt(...)` →
`MISSING_MATRIX_RTC_TRANSPORT`. So the error does **not** mean "no transport
URL was advertised"; it means "every advertised URL failed to yield a JWT."
That's why fixing #1–#3 alone was insufficient — the JWT fetch itself was broken.

### 4. LiveKit key file: shared secret in wrong format on both sides

lk-jwt-service (`LIVEKIT_KEY_FILE`) and livekit-server (`--key-file`) must hold
**the same key** so lk-jwt can mint JWTs the SFU accepts for room creation.
Two independent breakages:

- **lk-jwt side (`default.nix` sops template):** content was
  `LIVEKIT_KEYS=KEY:SECRET`. lk-jwt's parser (upstream `readKeySecret`):
  `strings.Split(content, ":")`, requires exactly 2 parts, `key = parts[0]`, then
  trims ws. The `LIVEKIT_KEYS=` prefix survived into the parsed key, so lk-jwt
  signed JWTs with key `LIVEKIT_KEYS=devkey_...` → SFU rejected them.
- **livekit-server side (`livekit.nix`):** `keyFile = "/etc/livekit/secrets.env"`
  where that file was written via `environment.etc` using sops placeholders.
  `environment.etc` does **not** render sops placeholders (only `sops.secrets` /
  `sops.templates` do), so livekit-server read literal `<SOPS:...:PLACEHOLDER>`
  strings as its key.

Net effect: `POST /sfu/get` returned `500 {"errcode":"M_UNKNOWN","error":
"Unable to create room on SFU"}` with a *valid* OpenID token, because lk-jwt's
key didn't match livekit-server's key. Discovery swallowed the 500, fell
through every candidate, and threw `MISSING_MATRIX_RTC_TRANSPORT`.

**Fix:** one shared sops template, format `KEY: SECRET` (space after colon):
```nix
sops.templates."livekit-secrets" = {
  content = "${config.sops.placeholder.livekit_api_key}: ${config.sops.placeholder.livekit_api_secret}";
  owner = "root";
  mode = "0600";
};
# services.lk-jwt-service.keyFile = config.sops.templates."livekit-secrets".path;
# services.livekit.keyFile         = config.sops.templates."livekit-secrets".path;
```
Why the space-after-colon matters: livekit-server's `--key-file` YAML-unmarshals
into `map[string]string` — bare `KEY:SECRET` is a scalar ("cannot unmarshal
!!str"), but `KEY: SECRET` is a valid single-entry map. lk-jwt splits on `:` then
`strings.Trim`s ws off both fields, so the space is harmless there. Deleted the
broken `environment.etc."livekit/secrets.env"` block.

CORS: lk-jwt-service 0.4.4 already returns
`Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: POST`, and
`Access-Control-Allow-Headers: Accept, Content-Type, ...` itself (verified
live on `/get_token`). No nginx CORS config needed for the JWT endpoint.

lk-jwt-service 0.4.4 routes (from upstream `main.go`):
```
/sfu/get    legacy handler — accepts {room, openid_token, device_id}
/get_token  modern handler — accepts {room_id, slot_id, openid_token, member, delay_*}
/healthz
```
No handler at `/` (returns 404). This is why every unprefixed probe 404'd.

## Verification commands (live, on mlab)

```bash
# Synapse advertises the public URL (admin token from the matrix DB):
tok=$(sudo -u postgres psql matrix -tAc "SELECT token FROM access_tokens \
  WHERE user_id='@admin:marcel.cool' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
curl -s -H "Authorization: Bearer $tok" \
  https://matrix.marcel.cool/_matrix/client/unstable/org.matrix.msc4143/rtc/transports
# → {"rtc_transports":[{"livekit_service_url":"https://matrix.marcel.cool/livekit/jwt",...}]}

# Full JWT chain with a real OpenID token (proves room creation on the SFU):
oid=$(curl -s -X POST -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
  -d '{}' https://matrix.marcel.cool/_matrix/client/v3/user/%40admin:marcel.cool/openid/request_token)
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"room\":\"!test:marcel.cool\",\"openid_token\":$oid,\"device_id\":\"X\"}" \
  https://matrix.marcel.cool/livekit/jwt/sfu/get
# → HTTP 200, {"url":"wss://livekit.marcel.cool","jwt":"eyJ..."}

# Both key files identical (after fixing the shared template):
diff /run/credentials/lk-jwt-service.service/livekit-secrets \
     /run/credentials/livekit.service/livekit-secrets   # → no output
```

## What the previous version of this doc got wrong

- **Finding #3 was a ghost.** It claimed Element Call checks `/versions` for
  mRtc advertising and that a nginx `content_by_lua` / `versionsInterceptorLua`
  interceptor was added to inject transports. The interceptor was never written
  (only a comment exists in `matrix.nix`), and the premise is false: element-call
  0.18 does **not** read `/versions` for transports — it reads the authed MSC4143
  `rtc/transports` endpoint (priority 2 above).
- **Finding #4 inverted the truth.** It claimed element-call uses `/versions`,
  not the MSC4143 endpoint. The reverse is true: the MSC4143 endpoint is the
  primary discovery path.
- **The "Verified Working" block** listed `livekit_service_url: http://localhost:8090`
  as correct. That value is the root cause.

Findings #1 (`msc4143_enabled`) and #2 (`matrix_rtc: {transports:[...]}` shape)
were correctly fixed and are verified live in the deployed Synapse config.

## Key files
- `hosts/mlab/matrix.nix` — Synapse `matrix_rtc`, nginx vhost, well-known, lk-jwt service
- Deployed element-call bundle: `/nix/store/8bb4swis20d955j46hj6q0fn1kvlzjjy-element-call-0.18.0`
  (source map at `assets/index-CN5lfP4r.js.map`)
- Deployed lk-jwt-service: `/nix/store/kbb6k7jyckg530178axcvzgk3fgw7gji-lk-jwt-service-0.4.4`

## Services involved
| Service | Status | Notes |
|---------|--------|-------|
| Synapse | ✅ running | `msc4143_enabled`, `matrix_rtc` shape, and public `livekit_service_url` all correct |
| nginx | ✅ fixed | `/livekit/jwt/` proxyPass has trailing slash (prefix stripped) |
| `.well-known` | ✅ fixed | `rtc_foci` is array of `{type, livekit_service_url}` objects |
| lk-jwt-service 0.4.4 | ✅ running, key fixed | Reads shared sops template; routes `/sfu/get`, `/get_token`, `/healthz`; CORS OK |
| LiveKit SFU | ✅ running, key fixed | Reads same shared sops template; `wss://livekit.marcel.cool` |
| coturn | ✅ running | TURN for WebRTC |
| Element Call 0.18 | ✅ deployed | Behaviour confirmed from source map; JWT chain verified end-to-end |

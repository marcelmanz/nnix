# Element Call mRtc Setup — Findings

## Symptom
Element Call fails with `MISSING_MATRIX_RTC_TRANSPORT` on domain `marcel.cool`.

## Root Cause Chain

### 1. Wrong experimental feature key (FIXED)
- Original: `experimental_features.mrtc = true` — Synapse ignored this, it's not a valid key
- Fixed: `experimental_features.msc4143_enabled = true`

### 2. Wrong config structure (FIXED)
- Original: `matrix_rtc_session = { livekit_service_url = "..." }`
- Fixed: `matrix_rtc = { transports = [{ type = "livekit"; livekit_service_url = "..." }] }`

### 3. `/versions` endpoint doesn't advertise mRtc (FIXED)
- Synapse 1.154 has mRtc support but its `/versions` endpoint is **hardcoded** and does NOT include:
  - `org.matrix.msc4075.mrtc` in `unstable_features`
  - A `transports` object
- Element Call checks `/versions` for mRtc advertising → fails with `MISSING_MATRIX_RTC_TRANSPORT`
- **Fix**: nginx `content_by_lua` interceptor fetches from Synapse, injects `transports` into the response

### 4. MSC4143 endpoint exists but needs auth (WORKAROUND)
- `/_matrix/client/unstable/org.matrix.msc4143/rtc/transports` works (200 with transports)
- `/_matrix/client/r0/org.matrix.msc4143/rtc/transports` returns 404 (only `unstable` path)
- Requires authentication (401 without token)
- Element Call doesn't use this endpoint for the initial check — it uses `/versions`

## Verified Working (via SSH to mlab)
```
experimental_features:
  msc4143_enabled: true
matrix_rtc:
  transports:
  - livekit_service_url: http://localhost:8090
    type: livekit
```

## What Still Needs Fixing
**RESOLVED** — nginx `content_by_lua` interceptor in `versionsInterceptorLua` handles this.

## Services Involved
| Service | Status | Notes |
|---------|--------|-------|
| Synapse | ✅ Running | Config correct, `/versions` limitation is upstream |
| LiveKit | ✅ Running | `wss://livekit.marcel.cool` |
| lk-jwt-service | ✅ Running | Port 8090, proxies JWT generation |
| coturn | ✅ Running | TURN for WebRTC |
| Element Call | ✅ Should work | Nginx interceptor injects transports into `/versions` |

## Key Files
- `/home/marcel/.config/nix/hosts/mlab/matrix.nix`

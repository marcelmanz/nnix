# Radio program on the public page — plan

Goal: show a daily program (schedule) on https://radio.marcel.cool/, generated from the
AzuraCast playlist schedule, with every unscheduled gap filled with "Banging tunes".

## Facts established

- **Data source**: `GET /api/station/radio_marcel/schedule` (public, no auth, verified live).
  Returns upcoming occurrences, e.g.:
  ```json
  [{"id":1,"type":"playlist","name":"news","start":"2026-08-31T08:00:00+02:00",
    "end":"2026-08-31T08:15:00+02:00","is_now":false}]
  ```
  Note: `/api/schedule` and `/api/playlists` do NOT exist on the public API (405) —
  only `/api/nowplaying`, `/api/stations`, `/api/status`, `/api/time`. The working
  endpoint lives under `/api/station/{shortcode}/schedule`.
- **Current schedule** (from `station_schedules`, see `default.nix`): news playlist airs
  08:00–08:15 and 17:00–17:15 Europe/Madrid. Everything else is the default music playlist.
- **Deploy path**: edits go into `public.js` / `public.css` in this
  repo; the `azuracast-settings` systemd unit re-pushes them into AzuraCast on rebuild.
  No other files change.
- **Page structure**: `<main id="main"><div id="public-radio-player" class="vue-component">`
  is the only content; everything else on the page is fixed-position HUD chips
  (top-left: stream URL + listen-time, top-right: calm, bottom-left: background picker,
  bottom-right: listener count). All four corners are taken.
- **Design language**: neon-HUD, Courier New, notched corners (clip-path), `--hud-*`
  CSS variables, light-theme (`html.az-light`) and calm-mode (`html.az-calm`) variants.

## Plan

1. **Fetch**: on page load, `fetch('/api/station/radio_marcel/schedule')`.
   Convert `start`/`end` to local `HH:MM` (they arrive with the station's offset).
2. **Build the day grid**: sort occurrences by start time, fill every gap (including
   before the first and after the last, wrapping midnight) with
   `Banging tunes`. Example output:
   ```
   00:00 – 08:00  Banging tunes
   08:00 – 08:15  news
   08:15 – 17:00  Banging tunes
   17:00 – 17:15  news
   17:15 – 24:00  Banging tunes
   ```
   Program label = playlist `name` as-is, so future scheduled playlists appear
   automatically with no code change.
3. **Render + highlight**: emit a `<div class="az-program">` into `main#main` as a
   sibling after the Vue player root (Vue owns `#public-radio-player`, not `main`, so a
   sibling is stable). Highlight the currently-airing row (client-side time compare;
   `is_now` from the API as a fallback cross-check). Keep it cheap: one fetch on load,
   no polling (the lineup only changes on rebuild).
4. **Placement & style**: compact fixed panel on the left edge (only free side; the
   player widget is horizontally centered), reusing the HUD chip look — `--hud-bg`,
   notched corner, Courier New, 2px cyan border; light-theme and calm-mode variants via
   the existing `html.az-light` / `html.az-calm` selectors. Collapsible (a small header
   row toggles the list) so it doesn't fight the player on short screens; on mobile
   (<768px) it starts collapsed / shrinks to a slim bar like the existing chips do.
5. **Resilience**: if the fetch fails or returns an empty array, hide the panel
   (page already works without it). No new dependencies, no backend changes.

## Out of scope / skipped (YAGNI)

- No caching layer or polling — schedule is effectively static between rebuilds.
- No editor/admin UI — schedule changes flow from `default.nix` (`ensure_schedule`).
- No per-playlist artwork/descriptions — `name` + times is the whole feature.

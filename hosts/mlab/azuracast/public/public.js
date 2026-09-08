(function () {
  if (location.pathname !== "/" && location.pathname !== "/public/radio_marcel") return;

  // Muted-autoplay-where-allowed + unmute on first user gesture.
  // Chrome/Firefox allow muted autoplay without a gesture; Brave (and Chromium with autoplay
  // disabled) block even muted play() until the user interacts. We probe below and only attempt
  // load-time muted play where it will succeed; where it's blocked we stay paused (flashing PLAY
  // overlay) and start on the first gesture, which is always allowed. The store boots muted
  // (localStorage "player_muted" = "true") so a successful muted autoplay is silent until the
  // user clicks to unmute, keeping store + UI in sync.
  // Mute state IS saved (the store persists player_muted on every toggle) - but the muted boot
  // is what makes autoplay legal, so we remember a saved UNMUTED state here and restore it in
  // start() once the muted autoplay is actually playing: unmuting an already-playing <audio>
  // needs no user gesture, so the icon and the sound come back exactly as the user left them.
  var wasUnmuted = false;
  try {
    wasUnmuted = localStorage.getItem("player_muted") === "false";
  } catch (e) {}
  try {
    localStorage.setItem("player_muted", "true");
  } catch (e) {}
  // New users (no saved volume) start at 75%, not the store's 55: the store reads its
  // player_volume key from localStorage on first access, which happens after this script
  // (same hook the muted pre-seed above rides on), so seeding the key here is what the store
  // boots with. Returning users keep their saved value.
  try {
    if (localStorage.getItem("player_volume") === null) localStorage.setItem("player_volume", "75");
  } catch (e) {}

  function getPlayButton() {
    return document.querySelector(".radio-control-play-button");
  }
  function getMuteButton() {
    // :not(.dropdown-toggle) - the quality selector rides inside the volume pill (see relocate())
    // and its toggle is a .btn too, first in DOM order.
    return document.querySelector(".radio-control-volume .btn:not(.dropdown-toggle)");
  }
  function getAudioEl() {
    return document.querySelector("audio");
  }

  // Shared top HUD bar: the stream-info button, radio program button and calm button each live
  // in one of its three flex slots (left/center/right - see .az-hud-top in the CSS) instead of
  // being independently position:fixed, so the browser's own flex layout keeps them aligned and
  // gives the center slot only as much room as the side buttons leave, shrinking/eliding its
  // content instead of overlapping them. Built lazily by whichever of the three widgets below
  // runs first.
  function getHudSlot(name) {
    var top = document.querySelector(".az-hud-top");
    if (!top) {
      top = document.createElement("div");
      top.className = "az-hud-top";
      top.innerHTML =
        '<div class="az-hud-left"></div><div class="az-hud-center"></div><div class="az-hud-right"></div>';
      document.body.appendChild(top);
    }
    return top.querySelector(".az-hud-" + name);
  }

  // --- debug (gated on ?azdebug); remove once autoplay is confirmed ---
  var DBG = (function () {
    if (location.search.indexOf("azdebug") === -1) return function () {};
    var log = (window.__azLog = []);
    function emit() {
      var args = [].slice.call(arguments);
      log.push(((performance.now() / 100) | 0) + " " + args.join(" "));
      try {
        console.log.apply(console, args);
      } catch (e) {}
    }
    emit("azdebug ON");

    function attachAudioLog() {
      var audio = getAudioEl();
      if (!audio || audio._azDbg) return;
      audio._azDbg = 1;
      [
        "play",
        "playing",
        "pause",
        "ended",
        "error",
        "suspend",
        "stalled",
        "emptied",
        "loadstart",
        "canplay",
        "waiting",
        "abort",
        "ratechange",
      ].forEach(function (ev) {
        audio.addEventListener(
          ev,
          function () {
            emit(
              "audio." + ev,
              "paused=" + audio.paused,
              "muted=" + audio.muted,
              "readyState=" + audio.readyState,
              audio.error ? "err=" + audio.error.code : "",
            );
          },
          true,
        );
      });
    }
    setInterval(attachAudioLog, 200);

    function watchBtn(sel, label) {
      var btn = document.querySelector(sel);
      if (!btn || btn._azDbg) return;
      btn._azDbg = 1;
      new MutationObserver(function () {
        emit(label, "icon-> isPlaying=" + isPlaying() + " isMuted=" + isMuted());
      }).observe(btn, { childList: true, subtree: true, attributes: true });
    }
    setInterval(function () {
      watchBtn(".radio-control-play-button", "PLAYBTN");
      watchBtn(".radio-control-volume .btn:not(.dropdown-toggle)", "MUTEBTN");
    }, 200);

    // attachAudioLog only ever instruments the FIRST <audio> found. If AzuraCast ever leaves a
    // stale element behind while playing through a new one, its events are invisible above, so
    // report the element count whenever it changes.
    var lastCount = -1;
    setInterval(function () {
      var els = document.querySelectorAll("audio");
      if (els.length === lastCount) return;
      lastCount = els.length;
      var states = [];
      for (var i = 0; i < els.length; i++)
        states.push(
          i +
            ":paused=" +
            els[i].paused +
            ",t=" +
            els[i].currentTime.toFixed(1) +
            ",rs=" +
            els[i].readyState,
        );
      emit("AUDIO ELEMENTS n=" + els.length, states.join(" | "));
    }, 250);

    return emit;
  })();

  // --- stream auto-recovery ---
  // A network interruption can kill the stream without the browser or AzuraCast ever reconnecting
  // on their own. Recovery is what already works manually: toggle the real play button.
  //
  // Liveness is judged by currentTime ADVANCING, not by media events. An earlier version listened
  // for the 'playing' event, bound via a poll racing AzuraCast's own element-swap-on-toggle -
  // that race was lost constantly and produced a self-sustaining reconnect loop that strangled a
  // healthy stream every ~8s (see report.md for the full incident). A playing stream always
  // advances currentTime, so polling progress has no event to miss and cannot misfire on a
  // healthy stream.
  var recoveryEl = null,
    recoveryLastTime = -1,
    recoverySeenProgress = false,
    recoveryStalledSince = 0;
  var STALL_MS = 10000; // zero progress this long while unpaused = a real outage, not a blip

  function resetRecoveryProgress(audio) {
    recoveryEl = audio;
    recoveryLastTime = audio ? audio.currentTime : -1;
    recoverySeenProgress = false;
    recoveryStalledSince = 0;
  }

  setInterval(function () {
    var audio = getAudioEl();
    // paused is the user's choice, not ours to "fix"; no element yet means nothing to watch
    if (!audio || audio.paused) {
      resetRecoveryProgress(audio);
      return;
    }
    // element swapped -> rebase, don't compare currentTime across two different elements
    // (the new one restarts near 0, which would read as a huge backwards jump)
    if (audio !== recoveryEl) {
      resetRecoveryProgress(audio);
      return;
    }
    // abs(), not >: a backward jump (the browser reconnecting internally on the same element,
    // restarting currentTime near 0) also proves the element is alive. A forward-only test would
    // get stuck at the old high-water mark and read every later second as "no progress".
    if (Math.abs(audio.currentTime - recoveryLastTime) > 0.1) {
      recoveryLastTime = audio.currentTime;
      recoverySeenProgress = true;
      recoveryStalledSince = 0;
      return;
    }
    // Only ever act on "was playing, then stopped" - a stream that never started belongs to the
    // autoplay / ensurePlaying() path below, and clicking at it from here would fight it.
    if (!recoverySeenProgress) return;
    if (!recoveryStalledSince) recoveryStalledSince = performance.now();
    if (performance.now() - recoveryStalledSince < STALL_MS) return;
    recoveryStalledSince = 0; // give this retry a full fresh window
    DBG("recovery: soft retry (no progress for " + STALL_MS + "ms)");
    var playBtn = getPlayButton();
    if (playBtn) {
      playBtn.click();
      setTimeout(function () {
        var btn = getPlayButton();
        if (btn) btn.click();
      }, 300);
    }
  }, 1000);

  // Brave (and Chromium with autoplay disabled) block even muted play() until the user interacts.
  // AzuraCast flips isPlaying=true *before* play() resolves, so a blocked muted-autoplay desyncs
  // the store (icon says "pause", audio is silent) and the gesture handler below would trust that
  // icon and never restart -> dead silence. So: probe muted autoplay first (below), and only
  // attempt load-time play where it will succeed. Where it's blocked we stay paused (flashing PLAY
  // overlay) and start on the first user gesture, which is always allowed. Any NotAllowedError
  // that slips through is swallowed so the console stays clean; the gesture handler recovers
  // playback regardless.
  window.addEventListener("unhandledrejection", function (e) {
    if (e && e.reason && e.reason.name === "NotAllowedError") e.preventDefault();
  });

  var started = false,
    autoplayPollId,
    autoplayOk = null; // null = probe pending; true/false once resolved

  // Phones get no muted-autoplay-then-restore-unmute dance at all, regardless of what the probe
  // below would say: treating them like an autoplay-blocked browser (e.g. Brave) reuses that
  // already-working fallback - stay paused, flashing PLAY overlay, start on the first real tap,
  // which always lands inside a genuine user gesture instead of racing a synthetic one.
  var IS_MOBILE = window.matchMedia("(max-width: 767px)").matches;

  (function probeAutoplay() {
    if (IS_MOBILE) {
      autoplayOk = false;
      return;
    }
    try {
      var probe = new Audio();
      probe.muted = true;
      probe.src =
        "data:audio/wav;base64,UklGRiYAAABXQVZFZm10IBAAAAABAAEAIlYAAESsAAAQABAAZGF0YQIAAAAAAA==";
      var playPromise = probe.play();
      if (playPromise && playPromise.then) {
        playPromise.then(
          function () {
            autoplayOk = true;
          },
          function (err) {
            if (err && err.name === "NotAllowedError") {
              autoplayOk = false;
              clearInterval(autoplayPollId);
            } else autoplayOk = true; // any other failure (e.g. bad src) isn't an autoplay block
          },
        );
      } else {
        autoplayOk = true;
      }
    } catch (e) {
      autoplayOk = false;
      clearInterval(autoplayPollId);
    }
  })();

  // Start playback on AzuraCast's own controls, honoring the visitor's saved stream pick
  // (az_stream_pick, saved by the delegated listener in relocate()). The pick is applied
  // HERE - never on page load: a synthetic dropdown click at load pre-commits the store's
  // current stream, so start()'s play click would toggle it straight back off (toggle
  // semantics: same URL = stop), and the muted-autoplay unmute restore never runs -> the
  // page wakes up silent in every browser. Clicking the item runs setActiveStream -> toggle,
  // which starts the picked stream itself; with no (or matching) pick, the play button is
  // exactly the old behavior. FLAC is never auto-picked (matched on the label, which names the
  // format - see the mount display_name in azuracast/default.nix): browsers do play Ogg-FLAC,
  // but on a live stream the granule positions make their buffering heuristics stutter.
  function applyPickOrPlay() {
    var pick = null;
    try {
      pick = localStorage.getItem("az_stream_pick");
    } catch (e) {}
    var selBox = document.querySelector(
      ".radio-player-widget .radio-control-select-stream",
    );
    var selBtn = document.getElementById("btn-select-stream");
    if (pick && pick.indexOf("flac") === -1 && selBox && selBtn) {
      var items = selBox.querySelectorAll(".dropdown-item");
      var currentName = selBtn.textContent.trim().toLowerCase();
      for (var j = 0; j < items.length; j++) {
        var name = items[j].textContent.trim().toLowerCase();
        if (name === pick && currentName !== name) {
          DBG("applyPickOrPlay: picking '" + name + "' via dropdown item");
          items[j].click();
          return; // the item click already starts the stream
        }
      }
    }
    DBG("applyPickOrPlay: play button");
    var playBtn = getPlayButton();
    if (playBtn) playBtn.click();
  }

  function start() {
    DBG("start", "started=" + started, "autoplayOk=" + autoplayOk);
    if (started) return;
    if (autoplayOk !== true) return;
    var playBtn = getPlayButton();
    if (!playBtn) return;
    started = true;
    DBG("start -> applyPickOrPlay()");
    applyPickOrPlay();
    if (wasUnmuted) unmuteAfterPlay(); // restore the saved unmuted state once playback lands
    // AzuraCast's current stream is still null until now-playing lands, and toggle(null) is a
    // no-op stop: the click creates no <audio> at all. So keep the poll alive and re-arm until
    // a click actually lands playback, instead of latching started=true on a dead click.
    setTimeout(function () {
      if (getAudioEl()) clearInterval(autoplayPollId);
      else {
        DBG("start: no <audio> after click -> re-arm");
        started = false;
      }
    }, 700);
  }
  // AzuraCast fires 'now-playing' on the document when stream metadata arrives (same hook native autoplay uses).
  document.addEventListener(
    "now-playing",
    function () {
      setTimeout(start, 0);
    },
    { once: true },
  );
  autoplayPollId = setInterval(function () {
    if (getPlayButton()) setTimeout(start, 0);
  }, 300);
  setTimeout(function () {
    clearInterval(autoplayPollId);
  }, 10000);

  function cleanupGestureListeners() {
    ["pointerdown", "keydown", "touchstart", "wheel"].forEach(function (ev) {
      window.removeEventListener(ev, unmute, true);
    });
  }

  // Trust the <audio> element's real state, NOT the play-button icon. On mobile, the autoplay
  // probe may pass so start() auto-clicks the play button with NO user gesture; the real stream
  // play() (deferred to a nextTick, no activation) is then blocked, but AzuraCast has already
  // flipped isPlaying=true -> store desyncs (icon says "playing", audio is paused). So: if the
  // audio is actually paused, call play() directly inside this gesture (always allowed on
  // mobile), resuming the already-loaded stream; only if no stream is loaded yet do we click the
  // play button to make AzuraCast load+play it.
  function ensurePlaying() {
    var audio = getAudioEl();
    if (audio && !audio.paused) {
      DBG("ensurePlaying: already playing -> unmute");
      unmuteAfterPlay();
      return;
    }
    if (audio && audio.src) {
      // paused but stream loaded (autoplay blocked / desynced)
      audio.muted = isMuted();
      DBG("ensurePlaying: paused+src -> a.play() in gesture (muted=" + audio.muted + ")");
      var playPromise = audio.play();
      if (playPromise && playPromise.catch) playPromise.catch(function () {});
      unmuteAfterPlay();
      return;
    }
    DBG("ensurePlaying: no src -> applyPickOrPlay() start");
    started = true;
    clearInterval(autoplayPollId);
    applyPickOrPlay(); // no stream loaded -> the picked item or play button loads+plays it
    unmuteAfterPlay();
  }

  function unmute(e) {
    initEq(); // first user gesture -> boot the Web Audio analyser (needs a gesture)
    DBG(
      "unmute",
      e.type,
      "isPlaying=" + isPlaying(),
      "isMuted=" + isMuted(),
      "audioPaused=" + (getAudioEl() ? getAudioEl().paused : "no-audio"),
      "target=" + (e.target && (e.target.className || e.target.tagName)),
    );
    // pointer/touch on the album art precede a click handled by the art click handler (start+unmute); defer those.
    if (
      (e.type === "pointerdown" || e.type === "touchstart") &&
      e &&
      e.target &&
      e.target.closest &&
      e.target.closest(".now-playing-art")
    ) {
      DBG("unmute: defer to art handler");
      return;
    }
    // Anti-seizure button: a UI toggle, not a "start the radio" gesture. Return BEFORE cleanup()
    // so the listeners stay bound and the next real gesture still starts playback.
    if (e && e.target && e.target.closest && e.target.closest(".az-calm-btn")) {
      DBG("unmute: on calm btn, skip");
      return;
    }
    cleanupGestureListeners();
    if (e && e.target && e.target.closest) {
      // let the volume/mute control and the play button run their OWN real click (avoids a
      // double-toggle: our synthetic click + the real click = start then stop)
      if (
        e.target.closest(".radio-control-volume") &&
        !e.target.closest(".radio-control-select-stream")
      ) {
        DBG("unmute: on volume ctrl, skip");
        return;
      }
      if (e.target.closest(".radio-control-play-button")) {
        DBG("unmute: on play btn, just unmute-after");
        unmuteAfterPlay();
        return;
      }
    }
    ensurePlaying();
  }

  // Toggle play/pause from any user gesture (album-art click or Space key). Pauses only when
  // actually playing AND unmuted; otherwise starts/unmutes - trusting the real <audio> state
  // (not the play-button icon), same logic as the art click.
  function togglePlayPause() {
    initEq(); // spacebar gesture -> boot analyser (idempotent)
    cleanupGestureListeners();
    var audio = getAudioEl(),
      playBtn = getPlayButton();
    if (audio && !audio.paused && !isMuted()) {
      if (playBtn) playBtn.click();
    } // playing+unmuted -> pause
    else {
      ensurePlaying();
    } // paused or muted -> start/unmute
  }

  // Zoom lightbox trigger, shared between the ZOOM corner click and the 'z' keydown below.
  // triggeringZoom guards against double-handling: link.click() bubbles a click back up through
  // .now-playing-art, which the art click handler (see relocate()) would otherwise also catch.
  var triggeringZoom = false;
  function triggerZoom() {
    var link = document.querySelector(".radio-player-widget .now-playing-art a.album-art");
    if (!link) return;
    triggeringZoom = true;
    link.click();
    triggeringZoom = false;
  }

  // Spacebar toggles play/pause; ArrowUp/ArrowDown raise/lower volume; z toggles the album art
  // zoom lightbox; m toggles mute; w toggles the wave overlay (+ footer player); c toggles
  // anti-seizure mode; t/T iterate the background themes forward/back (party -> device ->
  // white -> black -> neon, plus the custom photo as a stop when one is set). Registered
  // BEFORE the window 'unmute' keydown (capture) so
  // stopImmediatePropagation stops it also firing ensurePlaying (which would re-start right
  // after a pause). preventDefault stops the page scrolling on Space/arrow keys. Skipped while
  // focus is in an input/textarea/contenteditable so we don't hijack typing, and a focused
  // volume slider keeps its native arrow handling instead of double-applying.
  // Filled in by the background picker IIFE below: re-applies the stored custom photo as the
  // 't' theme cycle's final stop. null until the picker runs.
  var azBgCycleCustom = null;
  // 't'/'T' theme cycle, shared with the keydown below: click the swatch after (dir>0) or
  // before (dir<0) the selected one. The custom photo (when set) is a stop between the last
  // preset and the first - azBgCycleCustom() re-applies it and returns false when none is
  // set, so the cycle simply wraps. Clicking reuses the swatch path (localStorage + apply
  // + selected state).
  function cycleTheme(dir) {
    var swatches = document.querySelectorAll(".az-bg-swatch");
    var n = swatches.length;
    if (!n) return;
    var selIdx = -1;
    for (var i = 0; i < swatches.length; i++) {
      if (swatches[i].classList.contains("az-selected")) {
        selIdx = i;
        break;
      }
    }
    // selIdx=-1 = the custom photo itself is active; it is a stop BETWEEN the last and first
    // preset (not a preset index), so each direction resolves its own target:
    var target, hitsPhoto;
    if (dir > 0) {
      target = selIdx === -1 ? 0 : (selIdx + 1) % n; // photo -> first preset
      hitsPhoto = selIdx !== -1 && target === 0; // last -> first boundary
    } else {
      target = selIdx === -1 ? n - 1 : (selIdx - 1 + n) % n; // photo -> last preset
      hitsPhoto = selIdx !== -1 && target === n - 1; // first -> last boundary
    }
    // Crossing the boundary lands on the custom photo (if set); from the photo there is no
    // stop, it already WAS the stop.
    if (hitsPhoto && azBgCycleCustom && azBgCycleCustom()) return;
    swatches[target].click();
  }
  window.addEventListener(
    "keydown",
    function (e) {
      var isSpace = e.key === " " || e.code === "Space";
      var isVol = e.key === "ArrowUp" || e.key === "ArrowDown";
      var isZoom = e.key === "z" || e.key === "Z";
      var isMute = e.key === "m" || e.key === "M";
      var isWaves = e.key === "w" || e.key === "W";
      var isCalm = e.key === "c" || e.key === "C";
      var isThemeFwd = e.key === "t";
      var isThemeBwd = e.key === "T";
      if (
        !isSpace &&
        !isVol &&
        !isZoom &&
        !isMute &&
        !isWaves &&
        !isCalm &&
        !isThemeFwd &&
        !isThemeBwd
      )
        return;
      var target = e.target;
      // Only defer to a REAL text-entry control. Matching a focused <input type=range> here would
      // silently swallow Space/z; it keeps its own native arrow-key handling below regardless.
      if (
        target &&
        (target.isContentEditable ||
          /^(TEXTAREA|SELECT)$/.test(target.tagName) ||
          (target.tagName === "INPUT" && target.type !== "range"))
      )
        return;
      if (isVol && target && target.tagName === "INPUT" && target.type === "range") return;
      e.preventDefault();
      e.stopImmediatePropagation(); // block the 'unmute' keydown (same target+phase, registered later)
      if (isSpace) {
        if (e.repeat) return; // held Space: still block scroll, but don't toggle again
        togglePlayPause();
      } else if (isZoom) {
        if (e.repeat) return;
        triggerZoom();
      } else if (isMute) {
        if (e.repeat) return;
        var muteBtn = getMuteButton();
        if (muteBtn) muteBtn.click(); // same real click the mute button itself would get
      } else if (isWaves) {
        if (e.repeat) return;
        var wbtn = document.querySelector(".az-waves-btn");
        // Route through the button when it's up: same path a click takes (class + aria-pressed
        // + localStorage). Only a bare pre-DOM keypress falls back to the raw setter.
        if (wbtn) wbtn.click();
        else setWavesBg(!document.documentElement.classList.contains("az-waves"));
      } else if (isCalm) {
        if (e.repeat) return;
        // Route through the button: it owns the 'calm' flag, label, aria-pressed, localStorage
        // and idle fade. A bare pre-DOM keypress would flip the class but leave the button label
        // (read from localStorage) stale, so it's skipped rather than set raw.
        var calmBtn = document.querySelector(".az-calm-btn");
        if (calmBtn) calmBtn.click();
      } else if (isThemeFwd || isThemeBwd) {
        if (e.repeat) return;
        cycleTheme(isThemeFwd ? 1 : -1);
      } else {
        bumpVolume(e.key === "ArrowUp" ? 5 : -5); // repeats allowed: hold to ramp volume
      }
    },
    true,
  );
  ["pointerdown", "keydown", "touchstart", "wheel"].forEach(function (ev) {
    window.addEventListener(ev, unmute, { capture: true, passive: true });
  });

  // Read play state from the real button's SVG icon (the store's isPlaying, locale-independent):
  // stop-circle icon (path has "H8V8") = playing; play-circle icon (triangle) = paused.
  function isPlaying() {
    var playBtn = getPlayButton();
    if (!playBtn) return false;
    var path = playBtn.querySelector("path");
    return !!(path && (path.getAttribute("d") || "").indexOf("H8V8") !== -1);
  }
  // Read mute state from the volume button's SVG icon (locale-independent):
  // volume-off icon (path has "4.27 3L3 4.27") = muted; volume-down/up = unmuted.
  function isMuted() {
    var muteBtn = getMuteButton();
    if (!muteBtn) return false;
    var path = muteBtn.querySelector("path");
    return !!(path && (path.getAttribute("d") || "").indexOf("4.27 3L3 4.27") !== -1);
  }

  // Drives the stopped-state card border (html.az-stopped, see the CSS). Deliberately its own
  // poller rather than piggybacking on the art-overlay's sync() (which only exists once a track
  // WITH cover art has loaded) - a track with no art at all would otherwise never get the border.
  setInterval(function () {
    document.documentElement.classList.toggle("az-stopped", !isPlaying());
  }, 300);

  // Arrow keys adjust volume by setting the range input's value and dispatching an 'input' event,
  // which Vue's v-model picks up, updates the store, and persists to localStorage. If muted,
  // unmute on up so the change is audible; down on a muted stream does nothing (already silent).
  var VOL_STEP = 5;
  function bumpVolume(delta) {
    var input = document.querySelector(".radio-control-volume .form-range");
    if (!input) return; // iOS: volume controls disabled (audio.volume not settable)
    var raw = Number(input.value);
    var cur = isNaN(raw) ? 50 : raw; // NOT `|| 50` -> that treats a real 0 as falsy and jumps to 50
    var next = Math.max(0, Math.min(100, cur + delta));
    if (next === cur) return;
    input.value = next;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    if (delta > 0 && next > 0 && isMuted()) {
      var muteBtn = getMuteButton();
      if (muteBtn) muteBtn.click();
    }
  }

  // Drives the mushroom<->mouth volume-bar theme (see CSS): --vol (0-1) lets the track fill and
  // the mouth glow react to the same number. Delegated on document (bubbles) so it works
  // regardless of when Vue mounts the input; bumpVolume's synthetic 'input' event triggers it
  // too. Rising edge into max spawns the "1UP" (.az-1up in CSS) and the chomp; falling edge
  // resets the flag so it can fire again next time volume is pushed back to max.
  var AZ_BITE_MS = 500; // mouth-bite animation length
  var AZ_HIDDEN_MS = 3000; // how long the mushroom stays eaten once the bite ends
  // Eaten-item rotation: each chomp eats whatever the thumb currently is; when the volume drops
  // back below max the NEXT item from AZ_ITEMS comes back as the thumb. --az-item-ch (brain slot
  // while at max) + --az-item-img (thumb) carry it to the pseudo-elements; the CSS defaults match
  // the pill (AZ_ITEMS[0]) if JS never runs.
  var AZ_ITEMS = ["💊", "🍄", "🐴", "🧪", "🍬", "🥤", "🍕"];
  var azItemIdx = 0;
  // Each item's own "trip": eating it swaps the background's whole shake/zoom/glow character
  // (read by setBgFx, below) to match its vibe, instead of just cycling the thumb emoji. Index
  // matches AZ_ITEMS 1:1 - AZ_ITEMS.length wraps forever, so pill is always back to its own
  // baseline trip the next lap (nothing carries over from drink/potion/etc into it). Pizza is
  // the deliberate "come back down" reset. phrase is what floats up instead of "1UP" (see
  // spawn1Up) - mushroom keeps the literal 1UP text, everything else gets its own callout.
  // eqSets (read by eqFrame) doubles/triples the equalizer lines while this item is active.
  var AZ_TRIP = [
    {
      scaleMul: 1.0,
      shakeMul: 1.0,
      speedMs: 50,
      glowMul: 1.0,
      hueDps: 0,
      wobbleAmp: 0,
      phrase: "RUSH",
    }, // pill - current/dancy ecstasy
    {
      scaleMul: 1.15,
      shakeMul: 1.2,
      speedMs: 60,
      glowMul: 1.0,
      hueDps: 10,
      wobbleAmp: 0,
      phrase: "1UP",
    }, // mushroom - tripy
    {
      scaleMul: 0.55,
      shakeMul: 1.5,
      speedMs: 450,
      glowMul: 0.8,
      hueDps: 0,
      wobbleAmp: 12,
      phrase: "WHOA",
      eqSets: 2,
    }, // horse - slow + dizzy, double lines
    {
      scaleMul: 1.5,
      shakeMul: 1.7,
      speedMs: 60,
      glowMul: 1.15,
      hueDps: 30,
      wobbleAmp: 0,
      phrase: "TRIP",
      eqSets: 3,
    }, // potion (LSD) - really tripy, triple lines
    {
      scaleMul: 1.15,
      shakeMul: 1.1,
      speedMs: 35,
      glowMul: 1.7,
      hueDps: 0,
      wobbleAmp: 0,
      phrase: "SUGAR",
    }, // candy - light + energy
    {
      scaleMul: 0.8,
      shakeMul: 0.8,
      speedMs: 220,
      glowMul: 0.9,
      hueDps: 0,
      wobbleAmp: 0,
      phrase: "CHILL",
    }, // drink - slow down a bit
    {
      scaleMul: 0.3,
      shakeMul: 0.3,
      speedMs: 50,
      glowMul: 0.7,
      hueDps: 0,
      wobbleAmp: 0,
      phrase: "CALM",
    }, // pizza - back to normal
  ];
  var azTrip = AZ_TRIP[0];
  var azMaxed = false; // mirror of input._azMaxed so eqFrame knows the trip is live
  function setAzItem(volCtrl) {
    var em = AZ_ITEMS[azItemIdx % AZ_ITEMS.length];
    volCtrl.style.setProperty("--az-item-ch", '"' + em + '"');
    volCtrl.style.setProperty(
      "--az-item-img",
      "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3E%3Ctext x='10' y='16' font-size='18' text-anchor='middle'%3E" +
        encodeURIComponent(em) +
        '%3C/text%3E%3C/svg%3E")',
    );
  }
  function syncVolVar(input) {
    var volCtrl = document.querySelector(".radio-control-volume");
    if (!volCtrl) return;
    var frac = (Number(input.value) || 0) / 100;
    volCtrl.style.setProperty("--vol", frac);
    if (frac >= 1) {
      volCtrl.classList.add("az-maxed"); // mouth stays gone while parked at max (see CSS)
      if (!input._azMaxed) {
        input._azMaxed = true;
        azMaxed = true;
        azTrip = AZ_TRIP[azItemIdx % AZ_TRIP.length]; // the item being eaten right now, pre-increment
        bgFxRoot.setProperty("--az-bg-speed", azTrip.speedMs + "ms");
        spawn1Up(volCtrl, azTrip.phrase);
        chompMushroom(volCtrl);
      }
    } else {
      // Dropped below max: the eaten item is done for this round -> the next one comes back.
      if (input._azMaxed) {
        azItemIdx++;
        setAzItem(volCtrl);
      }
      input._azMaxed = false;
      azMaxed = false;
      volCtrl.classList.remove("az-chomp", "az-eaten", "az-maxed"); // dragged back down -> thumb must be grabbable again
    }
  }
  // Mouth bites, then the mushroom stays hidden for AZ_HIDDEN_MS after the bite ends, then
  // comes back. --az-bite-ms feeds the azchomp animation-duration in CSS so the two never
  // drift apart. Every timer only REMOVES classes, so overlapping chomps/drags can't leave
  // the thumb stuck hidden.
  function chompMushroom(volCtrl) {
    volCtrl.style.setProperty("--az-bite-ms", AZ_BITE_MS + "ms");
    volCtrl.classList.add("az-chomp", "az-eaten");
    setTimeout(function () {
      volCtrl.classList.remove("az-chomp");
    }, AZ_BITE_MS);
    setTimeout(function () {
      volCtrl.classList.remove("az-eaten");
    }, AZ_BITE_MS + AZ_HIDDEN_MS);
  }
  function spawn1Up(volCtrl, text) {
    var el = document.createElement("span");
    el.className = "az-1up";
    el.textContent = text || "1UP";
    el.addEventListener("animationend", function () {
      el.remove();
    });
    volCtrl.appendChild(el);
  }
  document.addEventListener(
    "input",
    function (e) {
      if (e.target.matches && e.target.matches(".radio-control-volume .form-range"))
        syncVolVar(e.target);
    },
    true,
  );

  // Unmute WITHOUT racing play(). AzuraCast's play() runs in a Vue nextTick and reads isMuted at
  // that moment: toggling the store before that nextTick makes Vue flush the isMuted watcher
  // first, so play() runs UNMUTED and gets blocked on mobile (a fresh gesture is needed, and the
  // microtask loses it). So the store must stay MUTED until play() lands, then we unmute on the
  // 'play' event (unmuting an already-playing element needs no gesture).
  //
  // On first interaction there's no <audio> in the DOM yet - AzuraCast creates it in that same
  // nextTick. We must NOT unmute now (that flips the store before the audio exists, so
  // AzuraCast's play() runs unmuted and gets blocked). Instead wait for the <audio> to be
  // inserted (a MutationObserver microtask fires before the 'play' event task), then attach the
  // unmute listener so the store flips only after muted play() succeeds.
  function doUnmute(audio) {
    if (!audio.paused) {
      // already playing (muted) -> unmute now, no new play()
      DBG("doUnmute: playing -> unmute now");
      if (isMuted()) {
        var muteBtn = getMuteButton();
        if (muteBtn) muteBtn.click();
      }
      return;
    }
    var onPlay = function () {
      // muted play() will land -> unmute the store then
      audio.removeEventListener("play", onPlay);
      DBG("doUnmute: play event -> unmute");
      if (isMuted()) {
        var muteBtn = getMuteButton();
        if (muteBtn) muteBtn.click();
      }
    };
    audio.addEventListener("play", onPlay, { once: true });
    setTimeout(function () {
      // safety: if 'play' never fires (load stall), unmute after 2s
      audio.removeEventListener("play", onPlay);
      DBG("doUnmute: 2s safety", "isMuted=" + isMuted());
      if (isMuted()) {
        var muteBtn = getMuteButton();
        if (muteBtn) muteBtn.click();
      }
    }, 2000);
  }
  function unmuteAfterPlay() {
    var audio = getAudioEl();
    if (audio) {
      doUnmute(audio);
      return;
    }
    DBG("unmuteAfterPlay: no <audio> yet -> wait for insertion (keep store muted)");
    var obs = new MutationObserver(function () {
      var newAudio = getAudioEl();
      if (newAudio) {
        obs.disconnect();
        DBG("audio appeared -> doUnmute", "paused=" + newAudio.paused);
        doUnmute(newAudio);
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () {
      obs.disconnect();
    }, 3000);
  }

  // Album art overlay: flashing PLAY/PAUSE text (center) + ZOOM corner.
  // Clicking the art toggles play/pause (the <a> lightbox is blocked); the zoom corner opens the lightbox.
  // artObserver/artSyncTimer track the PREVIOUS art node's watchers so relocate() can tear them
  // down before attaching new ones. Without this, every art-less track (Player.vue destroys and
  // rebuilds .now-playing-art on a v-if) left the old observer+interval running forever on a
  // detached node - a MutationObserver keeps its target alive even with no JS references to it,
  // so this was an unbounded leak over a long listening session.
  var artObserver = null,
    artSyncTimer = null;
  function relocate() {
    var art = document.querySelector(".radio-player-widget .now-playing-art");
    var playBtn = getPlayButton();
    var volInput = document.querySelector(".radio-control-volume .form-range");
    if (volInput && !volInput._azVolSynced) {
      volInput._azVolSynced = true;
      syncVolVar(volInput);
    }
    // Quality selector rides INSIDE the volume pill, so it always sits immediately left of
    // the mute button + slider wherever the pill lives: corner-pinned over the card (normal
    // desktop), in-row (mobile) or in the docked footer bar (waves mode). Re-applied by this
    // poller because AzuraCast re-renders; the node keeps its dropdown listeners when moved.
    var selStream = document.querySelector(".radio-player-widget .radio-control-select-stream");
    var volCtrl = document.querySelector(".radio-player-widget .radio-control-volume");
    if (selStream && volCtrl && selStream.parentElement !== volCtrl) {
      volCtrl.insertBefore(selStream, volCtrl.firstChild);
    }
    // Why the lossless item comes with a caveat: see applyPickOrPlay. Set here (not there, which
    // only runs at start) so every visitor gets it, and re-applied by this poller across Vue's
    // re-renders. Matched on the label, which names the format (mount display_name, default.nix).
    if (selStream) {
      var selItems = selStream.querySelectorAll(".dropdown-item");
      for (var s2 = 0; s2 < selItems.length; s2++) {
        if (
          !selItems[s2].title &&
          selItems[s2].textContent.toLowerCase().indexOf("flac") !== -1
        )
          selItems[s2].title =
            "lossless, for radio apps - a live FLAC stream stutters in most browsers";
      }
    }
    // Remember the visitor's stream pick (localStorage) for applyPickOrPlay() to honor at
    // start time. Delegated capture listener, registered once - it survives AzuraCast
    // re-renders, unlike the dropdown nodes themselves.
    if (!window._azPickListener) {
      window._azPickListener = true;
      document.addEventListener(
        "click",
        function (e) {
          var it =
            e.target.closest &&
            e.target.closest(".radio-control-select-stream .dropdown-item");
          if (it)
            localStorage.setItem(
              "az_stream_pick",
              it.textContent.trim().toLowerCase(),
            );
        },
        true,
      );
    }
    if (!art || !playBtn || art._azInit) return !!(art && playBtn);
    art._azInit = true;

    if (artObserver) {
      artObserver.disconnect();
      artObserver = null;
    }
    if (artSyncTimer) {
      clearInterval(artSyncTimer);
      artSyncTimer = null;
    }

    var overlay = document.createElement("div");
    overlay.className = "az-overlay-play";
    art.appendChild(overlay);

    var zoomCorner = document.createElement("div");
    zoomCorner.className = "az-zoom";
    zoomCorner.textContent = "ZOOM";
    art.appendChild(zoomCorner);

    function sync() {
      var playing = isPlaying();
      var label = playing ? "PAUSE" : "PLAY";
      if (overlay.textContent !== label) overlay.textContent = label;
      art.classList.toggle("az-paused", !playing);
    }
    // MutationObserver: the button's icon swaps when isPlaying changes -> update immediately.
    artObserver = new MutationObserver(sync);
    artObserver.observe(playBtn, { childList: true, subtree: true, attributes: true });
    artSyncTimer = setInterval(sync, 500); // safety-net poll
    sync();

    art.addEventListener(
      "click",
      function (e) {
        if (triggeringZoom) return; // synthetic click from zoom corner/'z' key -> let <a> lightbox fire
        if (e.target.closest(".az-zoom")) {
          // zoom corner -> open lightbox via the <a>
          e.stopPropagation();
          e.preventDefault();
          triggerZoom();
          return;
        }
        e.stopPropagation();
        e.preventDefault(); // block <a> lightbox; image click toggles play
        togglePlayPause();
        setTimeout(sync, 0); // reflect the new state immediately
      },
      true,
    );
    return true;
  }
  // Persistent: .now-playing-art is behind a v-if on song.art, so an art-less track destroys the
  // container and the overlay/click handlers along with it. Guarded per node by art._azInit.
  setInterval(relocate, 200);

  // --- real audio-reactive equalizer, multiple LINES (placeholder; custom visualizer later) ---
  // One Web Audio AnalyserNode taps the <audio>; several SVG path ribbons trace different
  // frequency bands, each its own color + granularity + smoothing. DOM is built eagerly (polled)
  // so the 44px slot is reserved from page load -> no layout shift on fade. AudioContext is lazy
  // (needs a gesture) so muted autoplay isn't blocked. Same-origin guard: a cross-origin stream
  // bound to MediaElementSource taints it -> silence, so we skip. Per-track smoothing is done in
  // JS (analyser smoothing is global) so bass reads smooth, mids spiky, highs very spiky - and
  // each snaps up faster than it sinks down (bounce). eqFrame
  // re-binds each new <audio> (AzuraCast swaps it across pause/play) and resumes a
  // Chrome-auto-suspended context so data doesn't go flat.
  var eqCtx,
    eqAn,
    eqSrc,
    eqData,
    eqTime,
    eqRAF,
    eqInit,
    eqBoundEl,
    eqBox,
    eqLastSound = 0;
  // band = fraction of frequency bins [lo,hi]; pts = granularity; atk/rel = per-track
  // attack/release smoothing (0=snap, 1=frozen) - fast attack + slow release = the bounce;
  // amp = vertical half-amplitude and base = baseline, both in viewBox units (0-40), so a loud
  // track pushes a line past y=0 and it spills over the top of the strip (CSS overflow:visible).
  // src: 'hist' = time-domain scroll (a level per `push` ms into a ring buffer -> the shape
  // travels left like an audio-editor waveform), 'spec' = the frequency spread across x.
  // curve = Catmull-Rom tension: 1 = rounded wave, 0 = jagged scope line. th = line thickness,
  // kept thin and decreasing with frequency so five lines stack without swallowing each other;
  // the baselines sit 4 units apart so at rest they read as five separate lines.
  var EQ_TRACKS = [
    // bass -> scrolling waveform, slow and rounded, thickest, cyan
    // drift: the thick line slowly wanders through the spectrum and breathes its opacity, so
    // the heaviest line is never sitting at the same color twice
    {
      color: "#00e5ff",
      band: [0.0, 0.1],
      pts: 72,
      atk: 0.3,
      rel: 0.8,
      amp: 14,
      base: 34,
      src: "hist",
      push: 30,
      curve: 1,
      th: 2.4,
      drift: 1,
    },
    // low-mid -> rounded spectrum ribbon, green
    {
      color: "#00ff9d",
      band: [0.1, 0.22],
      pts: 40,
      atk: 0.12,
      rel: 0.82,
      amp: 18,
      base: 30,
      src: "spec",
      curve: 0.9,
      th: 1.8,
    },
    // mid -> half-curved, grainier, magenta
    {
      color: "#ff3df0",
      band: [0.22, 0.4],
      pts: 56,
      atk: 0.05,
      rel: 0.84,
      amp: 22,
      base: 26,
      src: "spec",
      curve: 0.6,
      th: 1.4,
    },
    // high-mid -> nearly straight segments, orange
    {
      color: "#ff8a00",
      band: [0.4, 0.58],
      pts: 80,
      atk: 0.02,
      rel: 0.87,
      amp: 27,
      base: 22,
      src: "spec",
      curve: 0.3,
      th: 1.1,
    },
    // high -> jagged scope line, no curve, thinnest, biggest amp so spikes overflow the top.
    // Capped at 0.80, not 1.00: a compressed stream carries no data up to Nyquist, so the top
    // of the spectrum is dead bins that sit flat all the time.
    {
      color: "#ffe600",
      band: [0.58, 0.8],
      pts: 96,
      atk: 0.0,
      rel: 0.9,
      amp: 34,
      base: 18,
      src: "spec",
      curve: 0,
      th: 0.8,
    },
  ];
  // Catmull-Rom -> cubic bezier. t=0 keeps the straight segments (jagged scope), t=1 gives the
  // rounded travelling curve of a waveform editor. Returns a coordinate + segment list, so it
  // can follow either an 'M' or an 'L'.
  function eqSeg(p, t) {
    var s = p[0][0].toFixed(1) + "," + p[0][1].toFixed(1);
    for (var i = 0; i < p.length - 1; i++) {
      var p1 = p[i],
        p2 = p[i + 1];
      if (!t) {
        s += " L" + p2[0].toFixed(1) + "," + p2[1].toFixed(1);
        continue;
      }
      var p0 = p[i - 1] || p1,
        p3 = p[i + 2] || p2;
      s +=
        " C" +
        (p1[0] + ((p2[0] - p0[0]) / 6) * t).toFixed(1) +
        "," +
        (p1[1] + ((p2[1] - p0[1]) / 6) * t).toFixed(1) +
        " " +
        (p2[0] - ((p3[0] - p1[0]) / 6) * t).toFixed(1) +
        "," +
        (p2[1] - ((p3[1] - p1[1]) / 6) * t).toFixed(1) +
        " " +
        p2[0].toFixed(1) +
        "," +
        p2[1].toFixed(1);
    }
    return s;
  }
  function buildEqDom() {
    if (eqBox) return;
    var host = document.querySelector(".radio-player-widget");
    if (!host) return;
    eqBox = document.createElement("div");
    eqBox.className = "az-eq";
    var NS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 100 40");
    svg.setAttribute("preserveAspectRatio", "none");
    EQ_TRACKS.forEach(function (track, i) {
      // set 0 is the base line; sets 1/2 are hidden "echo" ribbons that share the same d, just
      // hung lower and fainter - shown only while a maxed item doubles (horse) or triples
      // (potion) the lines, per azTrip.eqSets.
      track.els = [];
      for (var s = 0; s < 3; s++) {
        var el = document.createElementNS(NS, "path");
        el.setAttribute("fill", track.color);
        el._azOp = (0.9 - i * 0.12) * (s === 0 ? 1 : s === 1 ? 0.45 : 0.25);
        el.style.opacity = el._azOp;
        if (s > 0) {
          el.setAttribute("transform", "translate(0 " + s * 1.8 + ")"); // echo hangs lower
          el.style.display = "none";
        }
        svg.appendChild(el);
        track.els.push(el);
      }
      track._sets = 1;
      track.sm = new Float32Array(track.pts); // per-track smoothed buffer (ring, for src:'hist')
      track.hp = 0;
      track.cur = 0;
      track.lastPush = 0;
    });
    eqBox.appendChild(svg);
    var main = host.querySelector(".now-playing-main"); // same column as title/artist, where the time-display bar used to sit
    if (main) {
      main.appendChild(eqBox);
    } else {
      var ctrl = host.querySelector(".radio-controls");
      if (ctrl) host.insertBefore(eqBox, ctrl);
      else host.appendChild(eqBox);
    }
  }
  var eqDomPollId = setInterval(function () {
    if (document.querySelector(".radio-player-widget")) {
      buildEqDom();
      clearInterval(eqDomPollId);
    }
  }, 200);
  setTimeout(function () {
    clearInterval(eqDomPollId);
  }, 10000);

  function initEq() {
    if (eqInit) return;
    eqInit = true;
    buildEqDom(); // safety: ensure DOM exists even if the poll hasn't fired yet
    try {
      eqCtx = new (window.AudioContext || window.webkitAudioContext)();
      // iOS: resume() must fire inside the user gesture that created the context; a resume() from
      // the RAF loop (eqFrame) is ignored, leaving it suspended -> analyser returns zeros.
      if (eqCtx.state === "suspended" && eqCtx.resume) eqCtx.resume();
      eqAn = eqCtx.createAnalyser();
      eqAn.fftSize = 512; // 256 bins -> enough detail for the grainy top line
      eqAn.smoothingTimeConstant = 0; // raw -> per-track smoothing in JS (each line its own feel)
      eqAn.connect(eqCtx.destination);
      eqData = new Uint8Array(eqAn.frequencyBinCount);
      eqTime = new Uint8Array(eqAn.fftSize); // raw waveform - feeds the fullscreen wave background
    } catch (e) {
      eqCtx = null;
      return;
    }
    if (!eqRAF) eqFrame();
  }
  function attachEqSource(audio) {
    if (!eqCtx || !audio || audio === eqBoundEl) return;
    if (audio._azEqSrc) {
      eqBoundEl = audio;
      return;
    } // already bound -> just record
    audio._azEqSrc = 1;
    try {
      if (new URL(audio.src || "", location.href).origin !== location.origin) {
        eqBoundEl = audio;
        return;
      } // cross-origin -> skip (would silence)
      eqSrc = eqCtx.createMediaElementSource(audio);
      eqSrc.connect(eqAn);
      audio.addEventListener("play", function () {
        if (eqCtx && eqCtx.state === "suspended") eqCtx.resume();
      });
    } catch (e) {
      /* already bound to another context / unavailable -> no viz */
    }
    eqBoundEl = audio;
  }
  function eqFrame() {
    eqRAF = requestAnimationFrame(eqFrame);
    var audio = getAudioEl();
    if (audio && audio !== eqBoundEl) attachEqSource(audio); // <audio> swapped across pause/play -> rebind
    if (eqCtx && eqCtx.state === "suspended") eqCtx.resume(); // Chrome auto-suspends idle contexts
    // Muted-but-playing does NOT stop the lines/effects: the element mutes at the source, so
    // the analyser would read zeros - instead the wave data below free-runs on synthetic
    // per-band drift. Only paused (or no analyser/audio) actually stops everything.
    var muted = isMuted();
    if (!eqAn || !audio || audio.paused || !eqBox || !EQ_TRACKS[0].els[0]) {
      if (eqBox) eqBox.style.opacity = 0;
      setBgFx(0, 0, 0, 0); // paused/no audio -> background goes still
      return;
    }
    if (!muted) eqAn.getByteFrequencyData(eqData);
    var len = eqData.length,
      gmax = 0,
      peaks = [0, 0, 0, 0, 0],
      now = performance.now();
    if (!muted && eqTime) {
      eqAn.getByteTimeDomainData(eqTime);
      bgwFreshAt = now;
    } // raw waveform for the bg waves
    for (var k = 0; k < EQ_TRACKS.length; k++) {
      var track = EQ_TRACKS[k];
      var b0 = Math.floor(track.band[0] * len);
      var b1 = Math.max(b0 + 1, Math.floor(track.band[1] * len));
      var span = b1 - b0,
        pts = track.pts,
        top = [],
        bot = [];
      // Trip reactions while volume is maxed - each line its own way, front line (k=2) always
      // responding hardest: glowMul scales height (candy jumps, drink/pizza settle), wobbleAmp
      // is the horse's dizziness, speedMs sets a micro-sway (fast = pill/candy rush), and the
      // hue-rotate below color-cycles the trippy items (mushroom/potion) at a different rate per
      // line. Gated on azMaxed so the last trip doesn't linger after the volume drops.
      var ampMul = 1,
        swayAmp = 0,
        swaySpd = 0;
      if (azMaxed) {
        ampMul = Math.min(1.25, 1 + (azTrip.glowMul - 1) * 0.35 * (k + 1));
        swayAmp = Math.min(
          3,
          azTrip.wobbleAmp * (0.15 + 0.1 * k) || (60 / azTrip.speedMs) * 0.5 * (0.5 + 0.25 * k),
        );
        swaySpd = (60 / azTrip.speedMs) * (1 + 0.2 * k);
      }
      if (track.src === "hist") {
        // One band level per frame, smoothed, pushed into the ring every `push` ms - rendering
        // from the write head reads oldest->newest, so the wave scrolls left with no seam.
        var lvl = 0;
        if (muted)
          lvl = 70 + 45 * Math.sin(now / 700) + Math.random() * 25; // free-run, see below
        else {
          for (var j = b0; j < b1; j++) if (eqData[j] > lvl) lvl = eqData[j];
          lvl = Math.min(255, lvl * 1.3);
        }
        var hk = lvl > track.cur ? track.atk : track.rel; // snap up, sink down -> bounce
        track.cur = track.cur * hk + lvl * (1 - hk);
        if (now - track.lastPush > 500) track.lastPush = now; // backgrounded tab -> don't replay the gap
        while (now - track.lastPush >= track.push) {
          track.lastPush += track.push;
          track.sm[track.hp] = track.cur;
          track.hp = (track.hp + 1) % pts;
        }
      }
      for (var i = 0; i < pts; i++) {
        var v;
        if (track.src === "hist") {
          v = track.sm[(track.hp + i) % pts]; // write head = oldest sample -> x is time
        } else {
          if (muted) {
            // Free-run idle wave: slow per-band sine + jitter. Freq/phase-slope/jitter grow with
            // k so bass undulates, mids ripple, highs shimmer - the real bands' character, minus
            // the (zeroed) analyser. Still feeds peaks/gmax, so the background fx keep living too.
            v =
              60 +
              50 * Math.sin((now / 1000) * (0.8 + k * 0.5) + i * (0.25 + k * 0.1)) +
              (Math.random() * 2 - 1) * (6 + k * 14);
            if (v < 0) v = 0;
          } else {
            var s0 = b0 + Math.floor((i / pts) * span);
            var s1 = Math.max(s0 + 1, b0 + Math.floor(((i + 1) / pts) * span));
            v = 0;
            for (var j = s0; j < s1 && j < b1; j++) if (eqData[j] > v) v = eqData[j]; // max -> spikes (granularity)
            v = Math.min(255, v * 1.3); // gain -> lift detail
          }
          var kk = v > track.sm[i] ? track.atk : track.rel; // snap up, sink down -> bounce
          track.sm[i] = track.sm[i] * kk + v * (1 - kk);
          v = track.sm[i];
        }
        if (v > gmax) gmax = v;
        if (v > peaks[k]) peaks[k] = v; // per-band peak this frame -> drives the background fx
        var lv = v / 255;
        var x = (i / (pts - 1)) * 100;
        // trip sway, per-line phase; the i term makes it travel along the line instead of
        // lifting it rigidly
        var yb =
          track.base +
          (swayAmp ? Math.sin((now / 1000) * swaySpd + i * 0.3 + k * 2.1) * swayAmp : 0);
        var a = lv * track.amp * ampMul; // trip: taller (candy) or settled (drink/pizza)
        var th = track.th * (1 + lv); // thickness ∝ level, but only up to double -> stays a line
        top.push([x, yb - a - th / 2]);
        bot.push([x, yb - a + th / 2]);
      }
      bot.reverse(); // R-to-L -> path closes cleanly
      var d = "M" + eqSeg(top, track.curve) + " L" + eqSeg(bot, track.curve) + " Z";
      // horse doubles / LSD potion triples the lines (azTrip.eqSets): the echo ribbons share
      // this same d, so one layout drives all of them.
      var sets = azMaxed ? Math.min(3, azTrip.eqSets || 1) : 1;
      if (track._sets !== sets) {
        for (var s = 0; s < 3; s++) track.els[s].style.display = s < sets ? "" : "none";
        track._sets = sets;
      }
      var hue = azMaxed && azTrip.hueDps ? bgTripHue * (1 + 0.6 * k) : 0; // trippy items: color-cycle
      if (track.drift) hue += (now / 24000) * 360; // ~24s to walk the whole wheel - a slow wander, not a strobe
      for (var s = 0; s < sets; s++) {
        var el = track.els[s];
        el.setAttribute("d", d);
        var f = hue ? "hue-rotate(" + (hue * (1 + 0.35 * s)).toFixed(1) + "deg)" : ""; // each line its own rate
        if (el.style.filter !== f) el.style.filter = f;
        // breathe the opacity on its own (longer) cycle so it never lines up with the color walk
        if (track.drift)
          el.style.opacity = (el._azOp * (0.62 + 0.38 * Math.sin(now / 5200 + s))).toFixed(3);
      }
    }
    for (var b = 0; b < peaks.length; b++) bgwBands[b] = bgwBands[b] * 0.8 + (peaks[b] / 255) * 0.2; // -> bg waves
    if (gmax > 8) eqLastSound = now;
    eqBox.style.opacity = now - eqLastSound < 250 ? "1" : "0";
    setBgFx(gmax / 255, peaks[0] / 255, peaks[2] / 255, peaks[4] / 255); // low/mid/high of the five
  }

  // --- fullscreen wave overlay (the "≈" toggle, independent of the background picker) ---
  // A second, much bigger visualizer that does NOT replace the player strip: many oscillating
  // lines across the whole viewport, each its own wavelength, speed, amplitude and color.
  // Unlike the strip (a spectrum envelope riding a baseline) these are real waves centred on
  // mid-screen - a crest climbs about half the viewport up and the trough the same down, so the
  // tallest ones sweep nearly the full height. Shape = a travelling sine carrier (the
  // wavelength) mixed with the analyser's time-domain samples (the real waveform detail),
  // scaled by the matching equalizer band's level. Its own RAF loop, so it keeps flowing while
  // paused or muted - free-running on sines when there is no audio to read.
  var BGW_N = 12,
    BGW_PTS = 84;
  var BGW_COLORS = ["#00e5ff", "#00ff9d", "#ff3df0", "#ff8a00", "#ffe600", "#7b5cff"];
  var bgwSvg,
    bgwOn = false,
    bgwRAF = 0,
    bgwFreshAt = 0,
    bgwBands = [0, 0, 0, 0, 0],
    bgwWaves = [];
  for (var bw = 0; bw < BGW_N; bw++) {
    bgwWaves.push({
      amp: 14 + bw * 2.0, // 14..36 of a 100-tall viewBox
      k: 1.2 + (bw % 5) * 0.9, // crests across the screen = wavelength
      spd: (bw % 2 ? -1 : 1) * (0.25 + (bw % 4) * 0.18), // alternating directions -> no marching in step
      cy: 50 + Math.sin(bw * 1.7) * 6,
      stride: 3 + (bw % 6), // waveform samples per point = detail grain
      band: bw % 5, // which equalizer band drives its height
      color: BGW_COLORS[bw % BGW_COLORS.length],
      op: 1, // full strength - the lines ARE the effect
      sw: 1 + (bw % 3),
    });
  }
  function buildBgWaves() {
    if (bgwSvg || !document.body) return;
    var NS = "http://www.w3.org/2000/svg";
    bgwSvg = document.createElementNS(NS, "svg");
    bgwSvg.setAttribute("class", "az-bgwaves");
    bgwSvg.setAttribute("viewBox", "0 0 100 100");
    bgwSvg.setAttribute("preserveAspectRatio", "none");
    bgwSvg.setAttribute("aria-hidden", "true");
    bgwWaves.forEach(function (wv) {
      var el = document.createElementNS(NS, "path");
      el.setAttribute("fill", "none");
      el.setAttribute("stroke", wv.color);
      el.setAttribute("stroke-width", wv.sw);
      el.setAttribute("stroke-linecap", "round");
      el.setAttribute("vector-effect", "non-scaling-stroke"); // the viewBox is stretched to the window
      el.style.opacity = wv.op;
      bgwSvg.appendChild(el);
      wv.el = el;
    });
    document.body.appendChild(bgwSvg);
  }
  function bgWaveFrame() {
    bgwRAF = requestAnimationFrame(bgWaveFrame);
    if (!bgwOn || !bgwSvg) return; // calm mode on purpose keeps the waves flowing
    var now = performance.now(),
      t = now / 1000;
    var live = !!eqTime && now - bgwFreshAt < 200; // stale (paused/muted) -> free-run instead of freezing
    for (var w = 0; w < BGW_N; w++) {
      var wv = bgwWaves[w],
        pts = [];
      var lvl = live ? bgwBands[wv.band] : 0.45 + 0.25 * Math.sin(t * (0.3 + wv.band * 0.11));
      // 0.45 floor so even a quiet passage still sweeps well over half the viewport; loud peaks
      // on the biggest waves run just past the edges, which is the point
      var a = wv.amp * (0.45 + 0.55 * lvl);
      var roll = Math.sin(t * 0.23 + w) * 4; // slow vertical roll so the field is never a static stack
      for (var i = 0; i < BGW_PTS; i++) {
        var u = i / (BGW_PTS - 1);
        var sv = Math.sin(u * wv.k * Math.PI * 2 + t * wv.spd * 3 + w);
        if (live) {
          var idx = (i * wv.stride + Math.floor(t * 60)) % eqTime.length; // scroll the read head -> travels
          sv = sv * 0.55 + ((eqTime[idx] - 128) / 128) * 0.75; // carrier + real waveform detail
        }
        pts.push([u * 100, wv.cy + sv * a + roll]);
      }
      wv.el.setAttribute("d", "M" + eqSeg(pts, 1));
    }
  }
  var WAVES_KEY = "az_waves_on";
  function setWavesBg(on) {
    bgwOn = !!on;
    document.documentElement.classList.toggle("az-waves", bgwOn);
    try {
      localStorage.setItem(WAVES_KEY, bgwOn ? "1" : "0");
    } catch (e) {}
    if (!bgwOn) return;
    buildBgWaves();
    if (!bgwSvg) {
      document.addEventListener("DOMContentLoaded", buildBgWaves);
    } // body not up yet
    if (!bgwRAF) bgWaveFrame();
  }
  // Restore last state. The overlay rides on top of whatever background is picked - it is its
  // own layer, so the background picker no longer switches it on/off.
  try {
    if (localStorage.getItem(WAVES_KEY) === "1") setWavesBg(true);
  } catch (e) {}
  function addWavesToggle() {
    if (!document.body || document.querySelector(".az-waves-btn")) return;
    var b = document.createElement("button");
    b.type = "button";
    b.className = "az-waves-btn" + (bgwOn ? " az-on" : "");
    b.textContent = "≈";
    b.setAttribute("aria-label", "Toggle wave overlay");
    b.setAttribute("aria-pressed", String(bgwOn));
    b.addEventListener("click", function () {
      setWavesBg(!bgwOn);
      b.classList.toggle("az-on", bgwOn);
      b.setAttribute("aria-pressed", String(bgwOn));
    });
    document.body.appendChild(b);
  }
  if (document.body) addWavesToggle();
  else document.addEventListener("DOMContentLoaded", addWavesToggle);

  // Background vibrate + glow, driven by the same analyser data as the equalizer: bass -> zoom
  // pulse, mid/high -> a small shake offset, overall loudness -> glow strength. Color follows
  // whichever band is loudest (matches the eq track colors).
  //
  // Drop detection: bgBassAvg is a slow rolling average of the bass band ("what's normal right
  // now"). A frame where bass suddenly jumps well above that average is a hit (kick/drop), not
  // just a loud sustained bassline. Each hit relocates the glow to a random spot and injects
  // bgDropEnergy, which exponentially decays over the next ~0.3-0.5s -> a punch, not a toggle.
  var bgFxRoot = document.documentElement.style;
  var bgBassAvg = 0,
    bgDropEnergy = 0,
    bgLastHit = 0;
  // Floor so the glow stays faintly visible (and cursor-dodgeable) even when quiet/paused -
  // without this, opacity tracked audio loudness straight to 0, so hovering only ever seemed to
  // move it right around play/pause, where a brief decode spike made it flash into view.
  var GLOW_BASE_OPACITY = 0.16;
  var bgTripHue = 0,
    bgTripHueLastT = 0;
  // Glow drifts like a bubble in water: bgGlowX/Y is where it's currently drawn, bgGlowTargetX/Y
  // is where it's heading, and driftGlow() eases the former toward the latter every frame (not a
  // snap, not a CSS transition - custom properties inside a gradient() don't transition). Getting
  // the cursor close relocates the TARGET to a fresh spot on the far side of the screen, so the
  // light actually crosses the page rather than just nudging aside. Runs its own persistent RAF
  // loop, independent of the audio-driven eqFrame, so hover still works while paused. Skipped
  // entirely under prefers-reduced-motion (CSS already hides the ::after layer there).
  var bgGlowX = 50,
    bgGlowY = 35,
    bgGlowTargetX = 50,
    bgGlowTargetY = 35;
  var bgMouseX = -9999,
    bgMouseY = -9999;
  var GLOW_FLEE_R = 240; // px - cursor distance that triggers a flee
  var GLOW_FLEE_COOLDOWN_MS = 550; // don't re-flee faster than this while the cursor stays close
  var GLOW_EASE = 0.045; // per-frame lerp toward the target - lower = slower/floatier
  var bgGlowLastFlee = 0;
  function pickFleeTarget() {
    // Biased to the opposite side of the screen from the cursor, so it reads as crossing the
    // page rather than jittering in place.
    var fromLeft = bgMouseX < window.innerWidth / 2;
    return {
      x: fromLeft ? 58 + Math.random() * 32 : 10 + Math.random() * 32,
      y: 12 + Math.random() * 66,
    };
  }
  function maybeFlee() {
    var w = window.innerWidth,
      h = window.innerHeight;
    var bx = (bgGlowX / 100) * w,
      by = (bgGlowY / 100) * h;
    var dist = Math.hypot(bx - bgMouseX, by - bgMouseY);
    var now = performance.now();
    if (dist < GLOW_FLEE_R && now - bgGlowLastFlee > GLOW_FLEE_COOLDOWN_MS) {
      bgGlowLastFlee = now;
      var t = pickFleeTarget();
      bgGlowTargetX = t.x;
      bgGlowTargetY = t.y;
    }
  }
  function driftGlow() {
    requestAnimationFrame(driftGlow);
    if (document.documentElement.classList.contains("az-calm")) return;
    bgGlowX += (bgGlowTargetX - bgGlowX) * GLOW_EASE;
    bgGlowY += (bgGlowTargetY - bgGlowY) * GLOW_EASE;
    bgFxRoot.setProperty("--az-glow-x", bgGlowX.toFixed(2) + "%");
    bgFxRoot.setProperty("--az-glow-y", bgGlowY.toFixed(2) + "%");
  }
  if (!window.matchMedia || !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    window.addEventListener("mousemove", function (e) {
      if (document.documentElement.classList.contains("az-calm")) return; // hidden by CSS in calm mode - skip the trig
      bgMouseX = e.clientX;
      bgMouseY = e.clientY;
      maybeFlee();
    });
    driftGlow();
  }
  function setBgFx(punch, bassN, midN, highN) {
    // Anti-seizure mode hides zoom/shake/glow entirely via CSS (html.az-calm) - none of the
    // work below has any visible effect while it's on, so skip it rather than compute for nothing.
    if (document.documentElement.classList.contains("az-calm")) return;
    bgBassAvg = bgBassAvg * 0.97 + bassN * 0.03;
    var now = performance.now();
    if (bassN > 0.35 && bassN > bgBassAvg * 1.35 && now - bgLastHit > 120) {
      bgLastHit = now;
      bgDropEnergy = 1;
      var t = pickFleeTarget();
      bgGlowTargetX = t.x;
      bgGlowTargetY = t.y;
    } else {
      bgDropEnergy *= 0.9;
    }
    // wobble: a slow independent circular drift, NOT tied to the audio - horse's "dizziness" is
    // disorientation, not just bigger reactive shake, so it needs motion that keeps going even
    // over a quiet passage.
    var wobbleX = 0,
      wobbleY = 0;
    if (azTrip.wobbleAmp) {
      var wt = now / 1000;
      wobbleX = Math.sin(wt * 0.6) * azTrip.wobbleAmp;
      wobbleY = Math.cos(wt * 0.5) * azTrip.wobbleAmp * 0.7;
    }
    bgFxRoot.setProperty(
      "--az-bg-scale",
      (1 + bassN * 0.045 * azTrip.scaleMul + bgDropEnergy * 0.14 * azTrip.scaleMul).toFixed(4),
    );
    bgFxRoot.setProperty(
      "--az-bg-x",
      ((midN - 0.5) * 14 * azTrip.shakeMul + wobbleX).toFixed(2) + "px",
    );
    bgFxRoot.setProperty(
      "--az-bg-y",
      ((highN - 0.5) * 10 * azTrip.shakeMul + wobbleY).toFixed(2) + "px",
    );
    // With the wave overlay on, the beat glow would wash the thin wave lines out (it paints
    // above them) - cap it lower so the waves stay readable while the pulse still comes through.
    var glowCap = bgwOn ? 0.3 : 0.85;
    bgFxRoot.setProperty(
      "--az-glow-opacity",
      Math.min(
        glowCap,
        (GLOW_BASE_OPACITY + punch * 0.5 + bgDropEnergy * 0.5) * azTrip.glowMul,
      ).toFixed(3),
    );
    bgFxRoot.setProperty(
      "--az-glow-color",
      bassN >= midN && bassN >= highN ? "#1e40ff" : midN >= highN ? "#ff3df0" : "#ffe600",
    );
    // Trip hue-rotate (mushroom/potion "tripping" color-cycle): accumulate by real elapsed time,
    // not a fixed per-frame step, so it doesn't speed up/slow down with the frame rate.
    var dt = bgTripHueLastT ? (now - bgTripHueLastT) / 1000 : 0;
    bgTripHueLastT = now;
    if (azTrip.hueDps) {
      bgTripHue = (bgTripHue + azTrip.hueDps * dt) % 360;
      bgFxRoot.setProperty("--az-trip-hue", bgTripHue.toFixed(1) + "deg");
    } else if (bgTripHue !== 0) {
      bgTripHue = 0;
      bgFxRoot.setProperty("--az-trip-hue", "0deg");
    }
  }

  // Marquee: scroll title/artist side-to-side when text overflows its column.
  var GAP = 48,
    SPEED = 60; // px/s
  function updateMarquee(el) {
    var text = (el.textContent || "").trim();
    if (text !== el.getAttribute("data-az-text")) el.setAttribute("data-az-text", text);
    el.classList.remove("az-marquee"); // measure in block state (no ::after)
    var textW = el.scrollWidth,
      cw = el.clientWidth;
    if (textW > cw + 1) {
      // overflow -> scroll
      el.style.setProperty("--az-shift", -(textW + GAP) + "px");
      el.style.setProperty("--az-dur", Math.max(6, Math.min(20, (textW + GAP) / SPEED)) + "s");
      el.classList.add("az-marquee");
    }
  }
  // marqueeObservers tracks the PREVIOUS title/artist node's observer per selector, so a Vue
  // rebuild (title/artist live in one of three keyed v-if branches - see below) can disconnect
  // the stale one instead of leaking it forever on a detached node (same leak class as relocate()'s art watcher).
  var marqueeObservers = {};
  function setupMarquee() {
    [".now-playing-title", ".now-playing-artist"].forEach(function (sel) {
      var el = document.querySelector(".radio-player-widget " + sel);
      if (!el || el._azMarquee) return;
      el._azMarquee = true;
      var isArtist = sel === ".now-playing-artist";
      if (isArtist) applyArtistLink();
      updateMarquee(el);
      if (marqueeObservers[sel]) marqueeObservers[sel].disconnect();
      // Vue updates the text node -> re-measure. attributes (class/style) excluded -> no self-loop.
      marqueeObservers[sel] = new MutationObserver(function () {
        updateMarquee(el);
        if (isArtist) applyArtistLink();
      });
      marqueeObservers[sel].observe(el, { childList: true, subtree: true, characterData: true });
    });
  }
  // Persistent for the same reason as the art watcher: Player.vue renders title/artist in one of
  // three keyed v-if branches, so whenever is_online or song.title changes truthiness Vue throws
  // the h4/h5 away and builds new ones - precisely when the uplink flaps. setupMarquee is a
  // guarded no-op per node (el._azMarquee).
  setInterval(setupMarquee, 300);
  var resizeTimer;
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(setupMarquee, 150);
  });

  // Keyboard-shortcut hint: pinned to the bottom-right corner of now-playing-details (see CSS
  // .az-hint), not its own row, so it adds no extra card height. Lives inside now-playing-details
  // (not the outer widget) because that's the box position:relative is actually set on. Desktop
  // only - CSS hides it under 768px (touch devices have no arrow keys).
  function setupHint() {
    var host = document.querySelector(".radio-player-widget .now-playing-details");
    if (!host || host.querySelector(".az-hint")) return !!host;
    var hint = document.createElement("div");
    hint.className = "az-hint";
    hint.textContent =
      "↑/↓ volume  ·  space play/pause  ·  m mute  ·  z zoom  ·  w waves  ·  c calm  ·  t/T theme";
    host.appendChild(hint);
    return true;
  }
  var hintPollId = setInterval(function () {
    if (setupHint()) clearInterval(hintPollId);
  }, 300);
  setTimeout(function () {
    clearInterval(hintPollId);
  }, 10000);

  // --- anti-seizure toggle ---
  // Everything it disables (background zoom/shake, beat glow, animated text colors) is driven by
  // CSS, so one class on <html> is the whole switch - see html.az-calm in the CSS. The class is
  // applied before the button exists so a reloaded page never flashes the effects first.
  (function () {
    var CALM_KEY = "az_calm";
    var calm = false;
    try {
      calm = localStorage.getItem(CALM_KEY) === "1";
    } catch (e) {}
    document.documentElement.classList.toggle("az-calm", calm);

    function addCalmButton() {
      if (!document.body || document.querySelector(".az-calm-btn")) return;
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "az-calm-btn";
      // Compact label on mobile: the full "I am having a seizure" is too wide to share the top
      // bar with the listen-time counter at phone widths, so on narrow viewports it shows a
      // short label instead (button stays right-anchored, counter stays left, no collision).
      var compactMq = window.matchMedia ? window.matchMedia("(max-width: 767px)") : null;
      function label() {
        var compact = !!(compactMq && compactMq.matches);
        btn.textContent = calm
          ? compact
            ? "SEIZURE ON"
            : "Anti Seizure Mode"
          : compact
            ? "SEIZURE OFF"
            : "I am having a seizure";
      }
      label();
      if (compactMq) {
        var onMq = function () {
          label();
        };
        if (compactMq.addEventListener) compactMq.addEventListener("change", onMq);
        else if (compactMq.addListener) compactMq.addListener(onMq);
      }
      btn.setAttribute("aria-pressed", String(calm));

      // Idle timer: the button only screams while you're near it. .az-calm-idle (CSS) fades it
      // to a near-invisible still ghost 2s after the pointer leaves - EXCEPT when the music is
      // stopped, then it stays fully visible (see syncPlay below), so a paused page can't hide
      // the one control that kills the strobing.
      var idleTimer,
        hovering = false;
      function idle(on) {
        clearTimeout(idleTimer);
        if (on) {
          idleTimer = setTimeout(function () {
            if (!isPlaying()) return; // stopped -> never go idle, stay fully visible
            btn.classList.add("az-calm-idle");
          }, 2000);
        } else {
          btn.classList.remove("az-calm-idle");
        }
      }
      btn.addEventListener("pointerenter", function () {
        hovering = true;
        idle(false);
      });
      btn.addEventListener("pointerleave", function () {
        hovering = false;
        idle(true);
      });
      btn.addEventListener("focus", function () {
        hovering = true;
        idle(false);
      });
      btn.addEventListener("blur", function () {
        hovering = false;
        idle(true);
      });
      btn.addEventListener("click", function () {
        calm = !calm;
        document.documentElement.classList.toggle("az-calm", calm);
        label();
        btn.setAttribute("aria-pressed", String(calm));
        try {
          localStorage.setItem(CALM_KEY, calm ? "1" : "0");
        } catch (e) {}
        idle(false); // touch has no hover: a tap must reveal it, then re-idle on leave
      });
      getHudSlot("right").appendChild(btn);

      // Music stopped -> button stays fully visible (no idle fade); playing -> usual hover/idle.
      // Polled: isPlaying() reads the play-button icon, which fires no event we can hook here.
      var wasStopped = null;
      function syncPlay() {
        var stopped = !isPlaying();
        if (stopped === wasStopped) return;
        wasStopped = stopped;
        if (stopped)
          btn.classList.remove("az-calm-idle"); // paused -> always show
        else if (!hovering) idle(true); // resumed -> fade after 2s (unless hovering)
      }
      syncPlay();
      setInterval(syncPlay, 300);
    }
    if (document.body) addCalmButton();
    else document.addEventListener("DOMContentLoaded", addCalmButton);
  })();

  // --- art change watcher ---
  // AzuraCast's own SSE drives title/artist/art reactively; no app-level polling needed for those.
  //
  // Deliberately NO cache-busting here. AzuraCast's art URLs are already unique and immutable per
  // track (/api/station/radio_marcel/art/<media-id>-<mtime>.jpg) and served with a one-year
  // cache-control. An earlier version appended a rising ?_az=N param on every now-playing event,
  // which defeated that cache and re-downloaded the ~390KB cover on every SSE tick - see
  // report.md for the full incident. Unique URL in, browser cache does the rest.
  (function () {
    function attachImgWatch() {
      var img = document.querySelector(".radio-player-widget .now-playing-art img");
      if (!img || img._azCacheWatch) return !!img;
      img._azCacheWatch = true;
      // AzuraCast's AlbumArt.vue renders loading="lazy", which lets the browser defer a track
      // change's cover fetch to a later rendering opportunity (indefinitely in a background tab).
      // This image is always in view and is the point of the page - fetch it eagerly.
      img.loading = "eager";
      img.setAttribute("fetchpriority", "high");
      new MutationObserver(function (muts) {
        muts.forEach(function (mut) {
          if (mut.attributeName !== "src") return;
          var newSrc = img.getAttribute("src") || "";
          DBG("img src mutation", "old=" + mut.oldValue, "new=" + newSrc);
          if (mut.oldValue && newSrc && mut.oldValue !== newSrc) playArtPush(mut.oldValue, newSrc);
        });
      }).observe(img, { attributes: true, attributeFilter: ["src"], attributeOldValue: true });
      return true;
    }
    // Persistent, not "poll until found then stop": .now-playing-art is behind a v-if on song.art,
    // so a track with no cover destroys the container and the next track with art builds a NEW
    // <img>. attachImgWatch is a guarded no-op per node (img._azCacheWatch).
    setInterval(attachImgWatch, 300);
  })();

  // Track-change "push": two throwaway <img> clones (old cover + new cover) layered above the
  // real <img> - which already has the new src by the time this runs - while the clones slide.
  // See .az-art-slide/-incoming/-outgoing in CSS for the movement itself.
  var PUSH_MS = 1400;
  var PUSH_WAIT_MS = 600;
  // Don't animate a cover that has no pixels yet - a slow fetch used to play the "push" over an
  // empty rectangle. preloadArt() below normally has the next cover cached already, so decode
  // resolves in the same tick; PUSH_WAIT_MS caps the wait for a cold fetch so a slow/failed load
  // degrades to the old behavior instead of dropping the transition entirely.
  function playArtPush(oldSrc, newSrc) {
    var pre = new Image();
    pre.src = newSrc;
    if (pre.complete) {
      startArtPush(oldSrc, newSrc);
      return;
    }
    var fired = false;
    var go = function () {
      if (fired) return;
      fired = true;
      DBG("playArtPush: new cover ready=" + pre.complete);
      startArtPush(oldSrc, newSrc);
    };
    pre.onload = pre.onerror = go;
    setTimeout(go, PUSH_WAIT_MS);
  }
  function startArtPush(oldSrc, newSrc) {
    var art = document.querySelector(".radio-player-widget .now-playing-art");
    var img = art && art.querySelector("img");
    if (!art || !img) return;
    // playArtPush defers this call behind an async preload (up to PUSH_WAIT_MS), and preloads
    // don't resolve in call order - a second, faster track change can call startArtPush before
    // an earlier, slower one's preload finishes. When that earlier call's callback finally
    // fires, img.src has already moved past newSrc: running it anyway would layer a stale cover
    // over the current one, which is the "photo gets duplicated" bug. Skip it.
    if (img.getAttribute("src") !== newSrc) {
      DBG("playArtPush: stale (img already moved on) - skipped");
      return;
    }

    DBG("playArtPush", art._azPushTimer ? "RESTART (previous push still in flight)" : "start");
    if (art._azPushTimer) clearTimeout(art._azPushTimer); // a transition was already mid-flight -> its cleanup must not fire late and cut this one short
    var leftover = art.querySelectorAll(".az-art-slide");
    for (var i = 0; i < leftover.length; i++) leftover[i].remove();

    var outgoing = document.createElement("img");
    outgoing.src = oldSrc;
    outgoing.className = "az-art-slide az-art-outgoing";
    art.appendChild(outgoing);

    var incoming = document.createElement("img");
    incoming.src = newSrc;
    incoming.className = "az-art-slide az-art-incoming";
    art.appendChild(incoming);

    art._azPushTimer = setTimeout(function () {
      art._azPushTimer = null;
      outgoing.remove();
      incoming.remove();
    }, PUSH_MS);
  }

  // --- artist name -> bandcamp album link ---
  // bandcampsync publishes an exact "artist|album" -> bandcamp url map (the real url from the
  // bandcamp API, not a guess) at bcsync.marcel.cool/links.json. The nowplaying API gives us
  // song.album (not present in the DOM); the artist TEXT stays fully Vue-owned, we just wrap it
  // in a link once both the map and a matching Vue-rendered artist agree.
  var bcLinks = null,
    lastSong = null;
  fetch("https://bcsync.marcel.cool/links.json", { cache: "no-store" })
    .then(function (r) {
      return r.ok ? r.json() : {};
    })
    .then(function (j) {
      bcLinks = j || {};
      applyArtistLink();
    })
    .catch(function () {
      bcLinks = {};
    });

  // Matches bandcampsync_report.py's norm(): folder names are filesystem-sanitized (apostrophes
  // stripped, etc.) and differ from the raw tags AzuraCast reports.
  function bcNorm(s) {
    return (s || "")
      .toLowerCase()
      .replace(/['’]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }
  function applyArtistLink() {
    if (bcLinks === null || !lastSong) return;
    var el = document.querySelector(".radio-player-widget .now-playing-artist");
    var artist = (lastSong.artist || "").trim();
    if (!el || !artist || (el.textContent || "").trim() !== artist) return; // Vue hasn't rendered this artist yet
    var url = bcLinks[bcNorm(artist) + "|" + bcNorm(lastSong.album)] || "";
    var link = el.querySelector("a.az-bc-link");
    if (link ? link.href === url : !url) return; // already correct (incl. no link available)
    el.textContent = artist;
    if (!url) return;
    link = document.createElement("a");
    link.className = "az-bc-link";
    link.href = url;
    link.target = "_blank";
    link.rel = "noopener";
    link.textContent = artist;
    el.textContent = "";
    el.appendChild(link);
  }

  (function () {
    // Hardcoded, not derived from location.pathname: the homepage serves this station's public
    // page directly at "/" (no redirect), so a /public/<shortcode> match never fires there.
    // Single-station page -> just hardcode it, matching homepage_redirect_url in azuracast.nix.
    var apiUrl = location.origin + "/api/nowplaying/radio_marcel";
    // Warm the browser cache with the NEXT track's cover while the current one is still playing.
    // The response already carries playing_next.song.art, and art URLs are immutable per track,
    // so by the time Vue swaps the src the bytes are local: the push transition starts instantly
    // instead of racing a ~390KB download.
    var preloaded = {};
    function preloadArt(url) {
      if (!url || preloaded[url]) return;
      preloaded[url] = new Image();
      preloaded[url].src = url;
    }
    // AzuraCast's player only ever binds art to now_playing.song.art; it never reads live.art
    // (the streamer's uploaded image), even though the API sends it. .now-playing-art is Vue's
    // v-if on song.art, so with no song metadata during a live set the container doesn't exist -
    // build the same markup AlbumArt.vue would so relocate()/attachImgWatch treat it the same.
    function applyLiveArt(live, songArt) {
      var details = document.querySelector(".radio-player-widget .now-playing-details");
      if (!details) return;
      var isLive = !!(live && live.is_live && live.art);
      var art = details.querySelector(".now-playing-art");
      if (isLive) {
        if (!art) {
          art = document.createElement("div");
          art.className = "now-playing-art";
          art._azLiveSynthetic = true;
          var mainCol = details.querySelector(".now-playing-main");
          if (mainCol) details.insertBefore(art, mainCol);
          else details.appendChild(art);
          var link = document.createElement("a");
          link.className = "album-art";
          link.target = "_blank";
          link.href = live.art;
          var img = document.createElement("img");
          img.className = "album_art";
          img.alt = "";
          img.src = live.art;
          link.appendChild(img);
          art.appendChild(link);
        } else {
          if (!art._azLiveSynthetic) art._azLiveOverridden = true; // was Vue's node - remember to restore it
          var existingImg = art.querySelector("img");
          var existingLink = art.querySelector("a.album-art");
          if (existingImg && existingImg.src !== live.art) existingImg.src = live.art;
          if (existingLink && existingLink.href !== live.art) existingLink.href = live.art;
        }
      } else if (art) {
        if (art._azLiveSynthetic) {
          art.remove();
        } else if (art._azLiveOverridden) {
          art._azLiveOverridden = false;
          var restoreImg = art.querySelector("img");
          var restoreLink = art.querySelector("a.album-art");
          if (restoreImg && songArt) restoreImg.src = songArt;
          if (restoreLink && songArt) restoreLink.href = songArt;
        }
      }
    }
    // Same gap as the art: now_playing.song.title/artist stay frozen on the last AutoDJ track
    // for the whole live broadcast. Idempotent (always sets what the current poll says is
    // correct), so no create/restore bookkeeping needed like the art container.
    function applyLiveText(live, song) {
      var titleEl = document.querySelector(".radio-player-widget .now-playing-title");
      var artistEl = document.querySelector(".radio-player-widget .now-playing-artist");
      if (!titleEl) return;
      if (live && live.is_live) {
        var name = window.azLiveTextOverride || live.streamer_name || "Live Broadcast";
        if (titleEl.textContent !== name) titleEl.textContent = name;
        if (artistEl && artistEl.style.display !== "none") artistEl.style.display = "none";
      } else {
        var title = (song && song.title) || "";
        var artist = (song && song.artist) || "";
        if (titleEl.textContent !== title) titleEl.textContent = title;
        if (artistEl) {
          if (artistEl.style.display === "none") artistEl.style.display = "";
          if (artistEl.textContent !== artist) artistEl.textContent = artist;
        }
      }
    }
    function fetchSong() {
      fetch(apiUrl, { cache: "no-store" })
        .then(function (r) {
          return r.ok ? r.json() : null;
        })
        .then(function (data) {
          if (data && data.playing_next && data.playing_next.song)
            preloadArt(data.playing_next.song.art);
          var song = data && data.now_playing && data.now_playing.song;
          applyLiveArt(data && data.live, song && song.art);
          applyLiveText(data && data.live, song);
          if (!song) return;
          lastSong = song;
          applyArtistLink();
        })
        .catch(function () {});
    }
    document.addEventListener("now-playing", function () {
      setTimeout(fetchSong, 0);
    });
    fetchSong();
  })();

  // --- live webcam ---
  // Only mounted once the admin flips the "go live" toggle at streamcam.marcel.cool
  // (webcam-control.py); /webcam-status is same-origin, unauthenticated, cheap to poll. Same
  // WHEP negotiation as the private test page - MediaMTX allows any origin to read the stream
  // (webrtcAllowOrigins), so the only gate on whether this ever shows is the status flag.
  (function () {
    var STATUS_URL = "/webcam-status";
    var WHEP_URL = "https://radio.marcel.cool/webcam/whep";
    var POLL_MS = 5000;
    var pc = null,
      videoEl = null,
      mounted = false,
      offlineEl = null;

    function mount() {
      if (mounted) return;
      mounted = true;
      var host = document.querySelector(".radio-player-widget");
      if (!host) {
        mounted = false;
        return;
      }
      videoEl = document.createElement("video");
      videoEl.className = "az-webcam";
      videoEl.autoplay = true;
      videoEl.muted = true;
      videoEl.playsInline = true;
      videoEl.poster =
        "data:image/svg+xml," +
        encodeURIComponent(
          '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="225">' +
            '<rect width="100%" height="100%" fill="#000"/>' +
            '<text x="50%" y="50%" fill="#0ce5ff" font-family="monospace" font-size="16" text-anchor="middle" dominant-baseline="middle">Connecting to live stream…</text>' +
            "</svg>"
        );
      videoEl.addEventListener("click", function () {
        if (videoEl.paused) {
          videoEl.muted = false;
          videoEl.play();
        } else {
          videoEl.pause();
        }
      });
      host.insertBefore(videoEl, host.firstChild);

      pc = new RTCPeerConnection();
      pc.ontrack = function (e) {
        videoEl.srcObject = e.streams[0];
      };
      pc.addTransceiver("video", { direction: "recvonly" });
      pc
        .createOffer()
        .then(function (offer) {
          return pc.setLocalDescription(offer).then(function () {
            return fetch(WHEP_URL, {
              method: "POST",
              headers: { "Content-Type": "application/sdp" },
              body: offer.sdp,
            });
          });
        })
        .then(function (res) {
          return res.ok ? res.text() : Promise.reject();
        })
        .then(function (answer) {
          return pc.setRemoteDescription({ type: "answer", sdp: answer });
        })
        .catch(function () {
          unmount();
        });
    }

    function unmount() {
      mounted = false;
      if (pc) {
        pc.close();
        pc = null;
      }
      if (videoEl) {
        videoEl.remove();
        videoEl = null;
      }
    }

    // Shown in the video's place while the cam is off - text set at streamcam.marcel.cool
    // (webcam-control.py), falls back to its own default when nothing's been set.
    function showOffline(text) {
      var host = document.querySelector(".radio-player-widget");
      if (!host) return;
      if (!offlineEl) {
        offlineEl = document.createElement("div");
        offlineEl.className = "az-webcam-offline";
        host.insertBefore(offlineEl, host.firstChild);
      }
      if (offlineEl.textContent !== text) offlineEl.textContent = text;
    }

    function hideOffline() {
      if (offlineEl) {
        offlineEl.remove();
        offlineEl = null;
      }
    }

    function poll() {
      fetch(STATUS_URL, { cache: "no-store" })
        .then(function (r) {
          return r.ok ? r.json() : { live: false };
        })
        .then(function (data) {
          // Read by the mobile live layout below - it needs to know this without polling
          // /webcam-status itself a second time.
          window.azWebcamLive = !!(data && data.live);
          if (data && data.live) {
            hideOffline();
            mount();
          } else {
            unmount();
            showOffline((data && data.offline_text) || "");
          }
        })
        .catch(function () {});
    }
    poll();
    setInterval(poll, POLL_MS);
  })();

  // --- bandcamp nudge tooltip ---
  // Until the user clicks the artist's bandcamp link (persisted in localStorage), a tooltip to
  // the right of the artist name (arrow pointing left at it) shows up once in a while: hidden
  // until nextAt, up for SHOW_MS, then a random 10-60s pause. Only shown while the link exists
  // (no bandcamp url for this artist -> nothing to point at) and not in calm mode. While up,
  // the artist name gets .az-nudge-on = the hover rainbow/wiggle (CSS; calm mode is excluded).
  // The tip is a child of .now-playing-details (stable) rather than the artist <h5> (Vue
  // destroys it per track); its position is pure CSS (bottom-left of the card), so no
  // per-show measurement and no drift across track changes or viewports.
  // pointer-events:none so it never blocks the click it is trying to get.
  (function () {
    var KEY = "az_bc_clicked";
    var SHOW_MS = 8000;
    var nextAt = Date.now() + 20000; // first appearance ~20s in
    var showAt = 0; // >0 while the tooltip is up
    function clicked() {
      try {
        return localStorage.getItem(KEY) === "1";
      } catch (e) {
        return false;
      }
    }
    function getTip() {
      // Stable parent: .now-playing-main (the title/artist column, persists across track
      // changes - the <h5> itself is rebuilt per track). The tip floats absolute over the
      // card (see CSS), so its DOM position is irrelevant; it is created once and appended.
      var main = document.querySelector(".radio-player-widget .now-playing-main");
      if (!main) return null;
      var tip = main.querySelector(":scope > .az-bc-tip");
      if (tip) return tip;
      tip = document.createElement("div");
      tip.className = "az-bc-tip";
      tip.textContent = "Enjoying this tune? Click on the artist name for more!";
      main.appendChild(tip);
      return tip;
    }
    document.addEventListener(
      "click",
      function (e) {
        var link =
          e.target && e.target.closest && e.target.closest(".now-playing-artist a.az-bc-link");
        if (!link) return;
        try {
          localStorage.setItem(KEY, "1");
        } catch (e2) {}
        link.parentElement.classList.remove("az-nudge-on");
        var tip = getTip();
        if (tip) tip.classList.remove("az-on");
      },
      true,
    );
    setInterval(function () {
      var tip = getTip();
      var link = document.querySelector(".radio-player-widget .now-playing-artist a.az-bc-link");
      if (!tip || !link || clicked() || document.documentElement.classList.contains("az-calm")) {
        if (tip) tip.classList.remove("az-on");
        if (link) link.parentElement.classList.remove("az-nudge-on");
        showAt = 0;
        return;
      }
      var row = link.parentElement;
      var now = Date.now();
      if (showAt && now - showAt >= SHOW_MS) {
        showAt = 0;
        tip.classList.remove("az-on");
        row.classList.remove("az-nudge-on");
        nextAt = now + 10000 + Math.random() * 50000; // random pause, then show again
      } else if (!showAt && now >= nextAt) {
        // Pin it under the artist: measure the h5's bottom edge inside .now-playing-main
        // (its offsetParent) and float the tip 8px below it; the arrow eats ~6px of that gap
        // so its point lands right at the name. Measured on every show, so a track change
        // that re-sizes the title/name keeps the tip under the new name.
        tip.style.top = row.offsetTop + row.offsetHeight + 8 + "px";
        // Point the arrow at the BOTTOM-CENTER of the name: the bandcamp link IS the artist
        // name, so its bounding box is the name box. Map its center onto the tip's own space
        // and expose it as --az-arrow-x (the ::before arrow reads it). Clamped so a very short
        // or very long name can't push the arrow off the chip. getBoundingClientRect is used
        // (not offsetLeft) so marquee/inline-block/transform layouts all measure correctly.
        var main = tip.parentElement;
        var mainRect = main.getBoundingClientRect();
        var nameRect = link.getBoundingClientRect();
        var nameCenterX = nameRect.left + nameRect.width / 2 - mainRect.left; // name center, rel to main
        var tipW = tip.offsetWidth;
        var tipLeftX = mainRect.width / 2 - tipW / 2; // tip's left edge (centered on column)
        var arrowX = nameCenterX - tipLeftX; // arrow x, rel to tip
        if (arrowX < 12) arrowX = 12;
        else if (arrowX > tipW - 12) arrowX = tipW - 12;
        tip.style.setProperty("--az-arrow-x", arrowX + "px");
        row.classList.add("az-nudge-on"); // artist name rainbow+wiggles while the tip is up
        showAt = now;
        tip.classList.add("az-on");
      }
    }, 1000);
  })();

  // --- listen-time counter (server-backed, per-IP) ---
  // Shows how long THIS visitor has been listening: current session + all-time total, both keyed
  // by their IP and read from AzuraCast's own listener records via the /listen-time endpoint
  // (the azuracast-listen-time service in azuracast.nix; same origin, so no CORS). The public
  // AzuraCast API only exposes aggregate listener counts, so a tiny host-side endpoint sums the
  // per-IP rows from the `listener` table. Polled once a minute and on tab refocus.
  (function () {
    function fmt(secs) {
      if (secs < 60) return secs + "s";
      var m = Math.floor(secs / 60);
      return m < 60 ? m + "m" : Math.floor(m / 60) + "h " + (m % 60) + "m";
    }
    function getEl() {
      return document.querySelector(".az-listen-time");
    }
    function paint(d) {
      var cur = (d && d.current) || 0,
        tot = (d && d.total) || 0;
      // "now" = current listening session, "total" = all-time; hide the total half until there's
      // a minute of history, and hide everything for a brand-new visitor who isn't listening.
      var txt =
        cur > 0
          ? "⏱ now " + fmt(cur) + (tot >= 60 ? " · total " + fmt(tot) : "")
          : tot >= 60
            ? "⏱ total " + fmt(tot)
            : "";
      var e = getEl();
      if (!txt) {
        if (e) e.remove();
        return;
      }
      if (!e) {
        e = document.createElement("div");
        e.className = "az-listen-time";
        document.body.appendChild(e); // next to .az-stream-btn (fixed top-left), so body-scoped
      }
      e.textContent = txt;
    }
    function poll() {
      if (document.hidden) return;
      fetch("/listen-time", { cache: "no-store" })
        .then(function (r) {
          return r.ok ? r.json() : null;
        })
        .then(paint)
        .catch(function () {});
    }
    poll();
    setInterval(poll, 60000);
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) poll();
    });
  })();

  // --- current listener count (bottom-right chip) ---
  // Aggregate "how many people are on the stream right now", from AzuraCast's own public API
  // (same origin through the proxy, so no CORS). /api/nowplaying without a station returns an
  // array of every station's payload - this deployment serves exactly one, so the first row is
  // ours and nothing here has to know the shortcode (the page is served at "/" via an internal
  // nginx rewrite, so the URL doesn't carry it either). Polled like the listen-time chip: once
  // every 30s and on tab refocus, skipped while hidden.
  (function () {
    function paint(n) {
      var e = document.querySelector(".az-listeners");
      if (n == null) {
        if (e) e.remove();
        return;
      } // API unreachable -> no chip at all, not a wrong number
      if (!e) {
        if (!document.body) return;
        e = document.createElement("div");
        e.className = "az-listeners";
        document.body.appendChild(e);
      }
      e.textContent = n + (n === 1 ? " listener" : " listeners");
    }
    function poll() {
      if (document.hidden) return;
      fetch("/api/nowplaying", { cache: "no-store" })
        .then(function (r) {
          return r.ok ? r.json() : null;
        })
        .then(function (d) {
          var st = d && (d.length ? d[0] : d);
          paint(
            st && st.listeners && typeof st.listeners.current === "number"
              ? st.listeners.current
              : null,
          );
        })
        .catch(function () {});
    }
    poll();
    setInterval(poll, 30000);
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) poll();
    });
  })();

  // --- radio program button (top-center) + full-timetable popover ---
  // Built from the AzuraCast public schedule API. That endpoint returns each playlist's own next
  // upcoming occurrence, not "today's" occurrences - so once some of today's slots have already
  // passed, their entries carry tomorrow's date while others still carry today's. The date part is
  // irrelevant here: only the recurring HH:MM-of-day matters, so each occurrence is reduced to its
  // local start/end time, repeats of the same HH:MM slot on a later day are dropped (otherwise a
  // slot like the news is listed twice) and the gaps between them are filled with "Banging tunes".
  // One fetch on
  // load (the lineup only changes on rebuild, so no polling); hidden entirely if the fetch fails or
  // the schedule is empty (the page already works without it). Same button+popover shape as the
  // stream-info/background-picker widgets below, just parked top-center - the one HUD position
  // with room to spare (top-left/-right and bottom-left/-right are all already taken).
  (function () {
    var FILLER = "Banging tunes";
    function toMinutes(iso) {
      var d = new Date(iso);
      return d.getHours() * 60 + d.getMinutes();
    }
    function fmt(min) {
      var h = Math.floor(min / 60),
        m = min % 60;
      return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    function buildRows(occurrences) {
      var seen = Object.create(null);
      var items = occurrences
        .map(function (o) {
          return { start: toMinutes(o.start), end: toMinutes(o.end), name: o.name };
        })
        .filter(function (it) {
          var key = it.start + "-" + it.end + "-" + it.name;
          if (seen[key]) return false;
          seen[key] = true;
          return true;
        })
        .sort(function (a, b) {
          return a.start - b.start;
        });
      var rows = [],
        prev = 0;
      items.forEach(function (it) {
        if (it.start > prev) rows.push({ start: prev, end: it.start, name: FILLER });
        rows.push(it);
        prev = Math.max(prev, it.end);
      });
      if (prev < 1440) rows.push({ start: prev, end: 1440, name: FILLER });
      // Midnight wrap: the day-bounded grid can split one continuous filler stretch into a
      // leading and a trailing row (e.g. 00:00-08:00 and 17:15-24:00) - merge them into a single
      // row that wraps (17:15-08:00) instead of showing "Banging tunes" twice back to back.
      if (rows.length > 1 && rows[0].name === FILLER && rows[rows.length - 1].name === FILLER) {
        var last = rows.pop();
        var first = rows.shift();
        rows.push({ start: last.start, end: first.end, name: FILLER, wrap: true });
      }
      return rows;
    }
    if (location.search.indexOf("azdebug") !== -1) {
      var selfCheck = buildRows([
        { start: "2026-01-01T08:00:00+02:00", end: "2026-01-01T08:15:00+02:00", name: "news" },
        { start: "2026-01-02T08:00:00+02:00", end: "2026-01-02T08:15:00+02:00", name: "news" },
      ]);
      console.assert(
        selfCheck.length === 2 &&
          selfCheck[0].name === "news" &&
          selfCheck[1].name === FILLER &&
          selfCheck[1].wrap === true &&
          selfCheck[1].start === 495 &&
          selfCheck[1].end === 480,
        "az-program buildRows self-check failed",
        selfCheck,
      );
    }

    function addProgramButton(rows) {
      if (!document.body || document.querySelector(".az-program-btn")) return;

      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "az-program-btn";
      btn.setAttribute("aria-label", "Radio program schedule");
      btn.setAttribute("aria-expanded", "false");
      btn.innerHTML =
        '<span class="az-program-title">RADIO PROGRAM</span>' +
        '<span class="az-program-status"></span>' +
        '<span class="az-program-next"></span>';
      var statusEl = btn.querySelector(".az-program-status");
      var nextEl = btn.querySelector(".az-program-next");

      var pop = document.createElement("div");
      pop.className = "az-program-pop";
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "Radio program schedule");
      pop.innerHTML =
        '<p class="az-program-pop-title">Radio Program</p><div class="az-program-list"></div>' +
        // az-stream-pop-footer is the stream popover's footer style; the rule is not scoped to
        // that popover, so reusing the class here costs no extra CSS.
        '<p class="az-stream-pop-footer">Check the past daily bulletins at ' +
        '<a href="https://bulletins.marcel.cool" target="_blank" rel="noopener">bulletins.marcel.cool</a></p>';
      var listEl = pop.querySelector(".az-program-list");

      var rowEls = rows.map(function (row) {
        var el = document.createElement("div");
        el.className = "az-program-row";
        el.textContent = fmt(row.start) + "–" + fmt(row.end) + "  " + row.name;
        listEl.appendChild(el);
        return el;
      });

      function highlight() {
        var now = new Date(),
          nowMin = now.getHours() * 60 + now.getMinutes();
        var currentIdx = -1;
        rows.forEach(function (row, i) {
          var isNow = row.wrap
            ? nowMin >= row.start || nowMin < row.end
            : nowMin >= row.start && nowMin < row.end;
          rowEls[i].classList.toggle("az-now", isNow);
          if (isNow) currentIdx = i;
        });
        var current = currentIdx === -1 ? null : rows[currentIdx];
        var next = currentIdx === -1 ? null : rows[(currentIdx + 1) % rows.length];
        statusEl.textContent = current ? "now: " + current.name : "";
        nextEl.textContent = next ? "next: " + next.name + " at " + fmt(next.start) : "";
      }
      highlight();
      setInterval(highlight, 30000);

      function setOpen(on) {
        btn.classList.toggle("az-open", on);
        pop.classList.toggle("az-open", on);
        btn.setAttribute("aria-expanded", String(on));
      }
      btn.addEventListener("click", function () {
        setOpen(!btn.classList.contains("az-open"));
      });
      document.addEventListener("click", function (e) {
        if (!btn.classList.contains("az-open")) return;
        if (e.target === btn || btn.contains(e.target) || pop.contains(e.target)) return;
        setOpen(false);
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && btn.classList.contains("az-open")) setOpen(false);
      });

      getHudSlot("center").appendChild(btn);
      document.body.appendChild(pop);
    }

    fetch("/api/station/radio_marcel/schedule", { cache: "no-store" })
      .then(function (r) {
        return r.ok ? r.json() : null;
      })
      .then(function (occurrences) {
        if (occurrences && occurrences.length) addProgramButton(buildRows(occurrences));
      })
      .catch(function () {});
  })();

  // --- stream-link info popover ---
  // A "?" button fixed top-left (mirrors the calm button's top-right) reveals a small popover
  // with the direct stream URL, so listeners can add this station to internet-radio apps
  // (TuneIn / VLC / Sonos / Apple Music radio / etc). Toggle: click "?" again or click anywhere
  // outside to dismiss; Esc also closes. URLs are derived from location.origin so they're
  // correct on any deployment (radio.marcel.cool -> /stream MP3 + /lossless-stream FLAC, both
  // nginx aliases in proxy.nix; the FLAC one 404s until the declarative mount exists).
  (function () {
    function addStreamInfo() {
      if (!document.body || document.querySelector(".az-stream-btn")) return;
      var streamUrl = location.origin + "/stream";
      var losslessUrl = location.origin + "/lossless-stream";

      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "az-stream-btn";
      btn.textContent = "?";
      btn.setAttribute("aria-label", "How to listen in a radio app");
      btn.setAttribute("aria-expanded", "false");

      var pop = document.createElement("div");
      pop.className = "az-stream-pop";
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "Stream link for radio apps");
      pop.innerHTML =
        '<p class="az-stream-pop-title">Listen in any radio app</p>' +
        '<p class="az-stream-pop-text">Add a URL as a station in Sonos, Apple Music radio, VLC, mpv, RadioDroid, Strawberry, or any internet-radio player - click a URL to copy it:</p>' +
        '<p class="az-stream-pop-label">standard - MP3 192kbps</p>' +
        '<a class="az-stream-pop-url" href="' +
        streamUrl +
        '" target="_blank" rel="noopener">' +
        streamUrl +
        "</a>" +
        '<p class="az-stream-pop-label">lossless - FLAC, for FLAC-capable players (~10x the data)</p>' +
        '<a class="az-stream-pop-url" href="' +
        losslessUrl +
        '" target="_blank" rel="noopener">' +
        losslessUrl +
        "</a>" +
        '<p class="az-stream-pop-footer">made by <a href="https://marcel.cool" target="_blank" rel="noopener">marcel.cool</a></p>';

      // Click the link -> copy to clipboard (don't navigate). href stays so right-click / open-in-new-tab
      // and a no-JS fallback still work. navigator.clipboard needs a secure context + gesture (both
      // true on https radio.marcel.cool); the execCommand fallback covers older iOS Safari / http LAN.
      function copyText(text, cb) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            cb(true);
          }, fallback);
        } else {
          fallback();
        }
        function fallback() {
          try {
            var ta = document.createElement("textarea");
            ta.value = text;
            ta.setAttribute("readonly", "");
            ta.style.position = "fixed";
            ta.style.opacity = "0";
            document.body.appendChild(ta);
            ta.select();
            var ok = document.execCommand("copy");
            document.body.removeChild(ta);
            cb(ok);
          } catch (e) {
            cb(false);
          }
        }
      }
      // Each URL row copies itself on click (shown text = copied text, so the loop just reads
      // it back off the element; href stays for right-click / open-in-new-tab / no-JS).
      Array.prototype.forEach.call(pop.querySelectorAll(".az-stream-pop-url"), function (urlEl) {
        urlEl.addEventListener("click", function (e) {
          e.preventDefault();
          var orig = urlEl.textContent;
          copyText(urlEl.textContent, function (ok) {
            urlEl.textContent = ok ? "Copied!" : "Copy failed - select & \u2318C";
            urlEl.classList.toggle("az-copied", ok);
            setTimeout(function () {
              urlEl.textContent = orig;
              urlEl.classList.remove("az-copied");
            }, 1300);
          });
        });
      });

      function setOpen(on) {
        btn.classList.toggle("az-open", on);
        pop.classList.toggle("az-open", on);
        btn.setAttribute("aria-expanded", String(on));
      }
      btn.addEventListener("click", function () {
        setOpen(!btn.classList.contains("az-open"));
      });
      // Dismiss on outside click (not on the button, not inside the popover). Bubble phase so the
      // button's own click toggles first; a click that lands elsewhere closes.
      document.addEventListener("click", function (e) {
        if (!btn.classList.contains("az-open")) return;
        if (e.target === btn || pop.contains(e.target)) return;
        setOpen(false);
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && btn.classList.contains("az-open")) setOpen(false);
      });

      getHudSlot("left").appendChild(btn);
      document.body.appendChild(pop);
    }
    if (document.body) addStreamInfo();
    else document.addEventListener("DOMContentLoaded", addStreamInfo);
  })();

  // --- custom background picker (client-side only, no upload) ---
  // A "pick an image" button (bottom-left) lets a listener replace the page background with
  // their own photo. The image never leaves the browser: it's downscaled on a <canvas> and
  // saved as a data URL in localStorage, then applied via --az-bg-custom (see the
  // background-image rule in public.css), so it's back on the next visit from the
  // same browser/device.
  (function () {
    var BG_KEY = "az_bg_custom";
    var MAX_DIM = 1920; // downscale target - keeps the base64 copy well under localStorage's ~5MB quota

    // Party = the default floating-lights photo (CSS falls back to it whenever --az-bg-custom is
    // unset, so "select Party" is just clearing the key); White/Black are solid colors. Device
    // and Neon are both markers (not real CSS values) resolved at apply-time: Device picks White
    // or Black from the OS color-scheme (and is the only preset that also switches the HUD chrome
    // to a light theme - see html.az-light in the CSS, toggled below); Neon picks a fresh random
    // pair from NEON_COLORS every time it's applied (including every page load), so re-clicking
    // an already-selected Neon reshuffles it and each visit looks a little different.
    var BG_PRESETS = [
      { key: "party", label: "Party", value: null, dot: 'url("/party-bg.jpg")' },
      {
        key: "device",
        label: "Device",
        value: "device",
        dot: "linear-gradient(90deg, #ffffff 50%, #000000 50%)",
      },
      // Keyword values (like 'device'/'neon'), resolved in apply(): the mode markers must be
      // derivable from what was picked - a bare gradient string would look like a photo.
      { key: "white", label: "White", value: "white", dot: "linear-gradient(#ffffff, #ffffff)" },
      { key: "black", label: "Black", value: "black", dot: "linear-gradient(#000000, #000000)" },
      {
        key: "neon",
        label: "Neon",
        value: "neon",
        dot: "conic-gradient(#3d0a66, #00263d, #66083d, #0a3d1f, #1a0a66, #3d0a66)",
      },
      // Waves is no longer a background preset: it is a separate overlay toggle (the "≈" button,
      // see setWavesBg/addWavesToggle above) that rides on top of any background.
    ];
    var DEVICE_WHITE = "linear-gradient(#ffffff, #ffffff)";
    var DEVICE_BLACK = "linear-gradient(#000000, #000000)";
    var deviceLightMQ = window.matchMedia
      ? window.matchMedia("(prefers-color-scheme: light)")
      : null;
    function deviceIsLight() {
      return !!(deviceLightMQ && deviceLightMQ.matches);
    }

    // Deep jewel-tone hues (not the bright #00e5ff-style accents) - stays a moody backdrop
    // rather than a blinding full-screen flash.
    var NEON_COLORS = [
      "#3d0a66",
      "#00263d",
      "#66083d",
      "#0a3d1f",
      "#3d2a00",
      "#1a0a66",
      "#003d33",
      "#4d0033",
    ];
    function randomNeonValue() {
      var a = NEON_COLORS[Math.floor(Math.random() * NEON_COLORS.length)];
      var b;
      do {
        b = NEON_COLORS[Math.floor(Math.random() * NEON_COLORS.length)];
      } while (b === a);
      var angle = Math.floor(Math.random() * 360);
      return "linear-gradient(" + angle + "deg, " + a + ", " + b + ")";
    }

    function stored() {
      try {
        return localStorage.getItem(BG_KEY);
      } catch (e) {
        return null;
      }
    }
    function apply(rawValue) {
      var cssValue = rawValue;
      if (rawValue === "device") cssValue = deviceIsLight() ? DEVICE_WHITE : DEVICE_BLACK;
      else if (rawValue === "white") cssValue = DEVICE_WHITE;
      else if (rawValue === "black") cssValue = DEVICE_BLACK;
      else if (rawValue === "neon") cssValue = randomNeonValue();
      // Wave overlay state is owned by its own toggle (setWavesBg), never by a background pick.
      if (cssValue) document.documentElement.style.setProperty("--az-bg-custom", cssValue);
      else document.documentElement.style.removeProperty("--az-bg-custom");
      document.documentElement.classList.toggle(
        "az-light",
        rawValue === "device" && deviceIsLight(),
      );
      // Marker class per resolved mode (photo = party default or own photo, i.e. any image
      // background): the CSS keys the waves-mode dark veil off .az-bg-photo and the faint
      // hairline frame off white/black.
      var mode =
        rawValue === "neon"
          ? "neon"
          : rawValue === "white" || (rawValue === "device" && deviceIsLight())
            ? "white"
            : rawValue === "black" || (rawValue === "device" && !deviceIsLight())
              ? "black"
              : "photo";
      ["photo", "white", "black", "neon"].forEach(function (m) {
        document.documentElement.classList.toggle("az-bg-" + m, m === mode);
      });
    }
    var initial = stored();
    // Legacy migration: "waves" used to be a background preset; it is now the separate overlay
    // toggle. Drop it so the background falls back to the default instead of an invalid value.
    if (initial === "waves") {
      try {
        localStorage.removeItem(BG_KEY);
      } catch (e) {}
      initial = null;
    }
    // Legacy migration: white/black used to store the raw gradient (indistinguishable from the
    // Device value), which made apply() mark them as photo and eat the waves dark veil - the
    // "gray background" bug. Rewrite to the keyword values above and persist it.
    if (initial === DEVICE_WHITE) {
      try {
        localStorage.setItem(BG_KEY, "white");
      } catch (e) {}
      initial = "white";
    } else if (initial === DEVICE_BLACK) {
      try {
        localStorage.setItem(BG_KEY, "black");
      } catch (e) {}
      initial = "black";
    }
    apply(initial); // always (even null = party default): the az-bg-* marker class must exist on load
    // Live-follow the OS theme while Device is selected, no reload needed.
    if (deviceLightMQ) {
      var onDeviceChange = function () {
        if (stored() === "device") apply("device");
      };
      if (deviceLightMQ.addEventListener) deviceLightMQ.addEventListener("change", onDeviceChange);
      else if (deviceLightMQ.addListener) deviceLightMQ.addListener(onDeviceChange);
    }

    function addBgPicker() {
      if (!document.body || document.querySelector(".az-bg-btn")) return;

      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "az-bg-btn";
      btn.textContent = "🖼";
      btn.setAttribute("aria-label", "Change background");
      btn.setAttribute("aria-expanded", "false");

      var input = document.createElement("input");
      input.type = "file";
      input.accept = "image/*";
      input.style.display = "none";

      var pop = document.createElement("div");
      pop.className = "az-bg-pop";
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "Background picker");
      pop.innerHTML =
        '<p class="az-bg-pop-title">Background</p>' +
        '<div class="az-bg-swatches"></div>' +
        '<button type="button" class="az-bg-pop-choose">Choose your own photo…</button>' +
        '<p class="az-bg-pop-msg">Saved only in this browser, on this device.</p>';
      var swatchRow = pop.querySelector(".az-bg-swatches");
      var chooseBtn = pop.querySelector(".az-bg-pop-choose");
      var msgEl = pop.querySelector(".az-bg-pop-msg");

      var swatchEls = {};
      function markSelected(key) {
        BG_PRESETS.forEach(function (p) {
          swatchEls[p.key].classList.toggle("az-selected", p.key === key);
        });
      }
      function currentKey() {
        var s = stored();
        if (!s) return "party";
        var match = BG_PRESETS.filter(function (p) {
          return p.value === s;
        })[0];
        return match ? match.key : null; // null = a custom uploaded photo, no preset selected
      }
      BG_PRESETS.forEach(function (preset) {
        var b = document.createElement("button");
        b.type = "button";
        b.className = "az-bg-swatch";
        var dot = document.createElement("span");
        dot.className = "az-bg-swatch-dot";
        dot.style.backgroundImage = preset.dot; // NOT the `background` shorthand: it resets
        // background-size/-position to their defaults, wiping the cover/center rules below and
        // leaving the Party photo shown uncropped at native size (a tiny sliver, not a thumbnail).
        var lbl = document.createElement("span");
        lbl.textContent = preset.label;
        b.appendChild(dot);
        b.appendChild(lbl);
        b.addEventListener("click", function () {
          if (preset.value) {
            try {
              localStorage.setItem(BG_KEY, preset.value);
            } catch (e) {}
          } else {
            try {
              localStorage.removeItem(BG_KEY);
            } catch (e) {}
          }
          apply(preset.value);
          markSelected(preset.key);
          msgEl.textContent = preset.label + " background set.";
        });
        swatchRow.appendChild(b);
        swatchEls[preset.key] = b;
      });
      markSelected(currentKey());

      chooseBtn.addEventListener("click", function () {
        input.click();
      });

      input.addEventListener("change", function () {
        var file = input.files && input.files[0];
        input.value = "";
        if (!file) return;
        msgEl.textContent = "Loading…";
        var img = new Image();
        var objectUrl = URL.createObjectURL(file);
        img.onload = function () {
          URL.revokeObjectURL(objectUrl);
          var scale = Math.min(1, MAX_DIM / Math.max(img.naturalWidth, img.naturalHeight));
          var canvas = document.createElement("canvas");
          canvas.width = Math.round(img.naturalWidth * scale);
          canvas.height = Math.round(img.naturalHeight * scale);
          canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
          var dataUrl = canvas.toDataURL("image/jpeg", 0.82);
          var cssValue = 'url("' + dataUrl + '")';
          try {
            localStorage.setItem(BG_KEY, cssValue);
            apply(cssValue);
            markSelected(null);
            msgEl.textContent = "Background updated.";
          } catch (e) {
            msgEl.textContent = "Image too large for this browser - try a smaller one.";
          }
        };
        img.onerror = function () {
          URL.revokeObjectURL(objectUrl);
          msgEl.textContent = "Could not read that image.";
        };
        img.src = objectUrl;
      });

      function setOpen(on) {
        btn.classList.toggle("az-open", on);
        pop.classList.toggle("az-open", on);
        btn.setAttribute("aria-expanded", String(on));
        if (on) markSelected(currentKey());
      }
      btn.addEventListener("click", function () {
        setOpen(!btn.classList.contains("az-open"));
      });
      document.addEventListener("click", function (e) {
        if (!btn.classList.contains("az-open")) return;
        if (e.target === btn || pop.contains(e.target)) return;
        setOpen(false);
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && btn.classList.contains("az-open")) setOpen(false);
      });

      document.body.appendChild(btn);
      document.body.appendChild(pop);
      document.body.appendChild(input);
    }
    if (document.body) addBgPicker();
    else document.addEventListener("DOMContentLoaded", addBgPicker);

    // Exposed to the outer-scope 't' keybind: re-apply the stored custom photo as the theme
    // cycle's final stop (and deselect the preset swatch, matching a photo pick). Returns
    // false when no custom photo is set so the caller wraps to the first preset instead.
    azBgCycleCustom = function () {
      var v = stored();
      if (v && v.indexOf("data:") !== -1) {
        apply(v);
        var sel = document.querySelector(".az-bg-swatch.az-selected");
        if (sel) sel.classList.remove("az-selected");
        return true;
      }
      return false;
    };
  })();

  // --- live chat ---
  // Random per-visitor name assigned server-side (chat.py); see proxy.nix's "/chat/" location.
  // Always open, docked to the right of the player (hidden below that width - see CSS media
  // query, there's no room beside the player on narrow viewports).
  // EventSource reconnects on its own after a drop - no retry logic needed here.
  (function () {
    var panel = document.createElement("div");
    panel.className = "az-chat-panel";
    panel.innerHTML =
      '<div class="az-chat-header"><span class="az-chat-you"></span></div>' +
      '<div class="az-chat-messages"></div>' +
      '<form class="az-chat-form"><input class="az-chat-input" maxlength="300" autocomplete="off" placeholder="Say something…">' +
      '<button type="submit" class="az-chat-send">Send</button></form>';

    var youEl = panel.querySelector(".az-chat-you");
    var messagesEl = panel.querySelector(".az-chat-messages");
    var formEl = panel.querySelector(".az-chat-form");
    var inputEl = panel.querySelector(".az-chat-input");

    function addMessage(msg) {
      var row = document.createElement("p");
      row.className = "az-chat-msg";
      var nameEl = document.createElement("span");
      nameEl.className = "az-chat-msg-name";
      nameEl.textContent = msg.name + ":";
      row.appendChild(nameEl);
      row.appendChild(document.createTextNode(msg.text));
      messagesEl.appendChild(row);
      while (messagesEl.children.length > 100) messagesEl.removeChild(messagesEl.firstChild);
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }

    formEl.addEventListener("submit", function (e) {
      e.preventDefault();
      var text = inputEl.value.trim();
      if (!text) return;
      inputEl.value = "";
      fetch("/chat/send", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      }).catch(function () {});
    });

    var es = new EventSource("/chat/events");
    es.addEventListener("name", function (e) {
      youEl.textContent = "You: " + JSON.parse(e.data).name;
    });
    es.addEventListener("message", function (e) {
      addMessage(JSON.parse(e.data));
    });
    // Owner-only "!t <text>" chat command (chat.py); overrides the on-air title normally read
    // from live.streamer_name - see applyLiveText() above.
    es.addEventListener("livetext", function (e) {
      window.azLiveTextOverride = JSON.parse(e.data).text || "";
    });

    if (document.body) document.body.appendChild(panel);
    else document.addEventListener("DOMContentLoaded", function () {
      document.body.appendChild(panel);
    });
  })();

  // --- mobile live layout ---
  // A fixed sidebar chat + inline webcam don't fit on a phone. When there's a live webcam feed
  // (window.azWebcamLive, set by the live-webcam IIFE above) on a narrow screen, take over the
  // screen instead: webcam on top, track info in the middle, chat filling the rest. Reparents
  // the real webcam <video> and chat panel rather than cloning them, so nothing needs to be
  // kept in sync - and moves them back to their normal homes if the screen widens or the
  // webcam goes offline while this is up.
  //
  // This hero sits ABOVE the real play button (it's a full-screen overlay), so the "tap
  // anywhere to unlock autoplay" hint that button normally gives is now invisible - without a
  // "tap to listen" prompt, muted autoplay just looks like a black screen with no sound. A tap
  // on the prompt is itself the gesture: the page's own global gesture listener (see unmute()
  // near the top of this file) already starts/unmutes playback for ANY tap, so this only needs
  // to show/hide the hint - not trigger playback itself.
  (function () {
    var MOBILE_QUERY = "(max-width: 767px)";
    var hero = document.createElement("div");
    hero.className = "az-live-mobile";
    hero.innerHTML =
      '<div class="az-live-mobile-webcam"></div>' +
      '<div class="az-live-mobile-track"><p class="az-live-mobile-title"></p><p class="az-live-mobile-artist"></p></div>' +
      '<div class="az-live-mobile-chat"></div>' +
      '<div class="az-live-mobile-tap"><div class="az-live-mobile-tap-badge">&#9654; Tap to listen</div></div>';
    var webcamSlot = hero.querySelector(".az-live-mobile-webcam");
    var chatSlot = hero.querySelector(".az-live-mobile-chat");
    var titleEl = hero.querySelector(".az-live-mobile-title");
    var artistEl = hero.querySelector(".az-live-mobile-artist");
    var tapEl = hero.querySelector(".az-live-mobile-tap");
    var tapDismissed = false;
    tapEl.addEventListener("click", function () {
      // Don't just rely on the page's global gesture listener (unmute() near the top of this
      // file) to also catch this tap - it only fires ONCE and this hero hides the real play
      // button, which is otherwise the always-available fallback if that first gesture got
      // consumed early (e.g. by an incidental touch before the stream was ready) with no
      // effect. Calling it here directly, inside this trusted click, works regardless.
      ensurePlaying();
      tapDismissed = true;
      tapEl.classList.remove("az-open");
    });

    function syncTrackText() {
      var t = document.querySelector(".radio-player-widget .now-playing-title");
      var a = document.querySelector(".radio-player-widget .now-playing-artist");
      titleEl.textContent = (t && t.textContent) || "";
      artistEl.textContent = (a && a.textContent) || "";
    }

    function update() {
      var on = window.matchMedia(MOBILE_QUERY).matches && !!window.azWebcamLive;
      hero.classList.toggle("az-open", on);
      var video = document.querySelector(".az-webcam");
      var chat = document.querySelector(".az-chat-panel");
      if (on) {
        if (video && video.parentElement !== webcamSlot) webcamSlot.appendChild(video);
        if (chat && chat.parentElement !== chatSlot) chatSlot.appendChild(chat);
        syncTrackText();
        if (!tapDismissed && isPlaying() && !isMuted()) tapDismissed = true; // started some other way (e.g. muted autoplay succeeded and got unmuted) - no need to prompt
        tapEl.classList.toggle("az-open", !tapDismissed);
      } else {
        var playerHost = document.querySelector(".radio-player-widget");
        if (video && playerHost && video.parentElement !== playerHost) {
          playerHost.insertBefore(video, playerHost.firstChild);
        }
        if (chat && chat.parentElement !== document.body) document.body.appendChild(chat);
      }
    }

    function mount() {
      document.body.appendChild(hero);
      update();
      setInterval(update, 500);
      window.addEventListener("resize", update);
    }
    if (document.body) mount();
    else document.addEventListener("DOMContentLoaded", mount);
  })();
})();

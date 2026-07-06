(function () {
  "use strict";

  const THRESHOLD = 64;
  const MAX_PULL = 88;
  const ABS_MAX = 108;
  const RESISTANCE = 0.5;
  const RUBBER = 0.08;
  const EASTER_RAW = MAX_PULL / RESISTANCE;
  const EASTER_RAW_MIN = EASTER_RAW + 120;
  const EASTER_HOLD_MS = 550;
  const PANEL_IDS = new Set(["history", "photo-gallery", "wishlist-panel", "gifts-panel", "admin-panel"]);

  function isStandalonePwa() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.matchMedia("(display-mode: fullscreen)").matches ||
      window.navigator.standalone === true
    );
  }

  function isTouchDevice() {
    return "ontouchstart" in window || navigator.maxTouchPoints > 0;
  }

  if (!isTouchDevice()) return;

  const isPwa = isStandalonePwa();
  let shell = null;

  if (isPwa) {
    document.documentElement.classList.add("pwa-standalone");
    shell = document.createElement("div");
    shell.id = "ptr-shell";
    [...document.body.childNodes].forEach((node) => shell.appendChild(node));
    document.body.appendChild(shell);

    const bodyLayerIds = [
      "plexi-hub-nav",
      "history",
      "wishlist-panel",
      "gifts-panel",
      "admin-panel",
      "checkin-detail",
      "photo-gallery",
      "edit-dialog",
      "duplicate-dialog",
      "invite-ips-scrim",
      "invite-ips-panel",
      "patchnotes-scrim",
      "patchnotes-panel",
      "toast-scrim",
      "toast",
    ];
    bodyLayerIds.forEach((id) => {
      const el = document.getElementById(id);
      if (el) document.body.appendChild(el);
    });
  }

  const indicator = document.createElement("div");
  indicator.id = "ptr-indicator";
  indicator.setAttribute("aria-hidden", "true");
  indicator.innerHTML =
    '<div class="ptr-inner"><span class="ptr-icon" aria-hidden="true">↓</span><span class="ptr-label">Tire pour actualiser</span></div>';
  document.body.prepend(indicator);

  const label = indicator.querySelector(".ptr-label");
  const icon = indicator.querySelector(".ptr-icon");

  let startY = 0;
  let pulling = false;
  let refreshing = false;
  let pullDist = 0;
  let rawDelta = 0;
  let scrollEl = null;
  let overpullStart = 0;

  function kaomojiHtml() {
    return (
      '<span class="ptr-face">^</span>' +
      '<span class="ptr-face">_</span>' +
      '<span class="ptr-face">^</span>'
    );
  }

  function setIconArrow() {
    if (!icon) return;
    icon.textContent = "↓";
    icon.style.transform = "";
  }

  function setIconKaomoji() {
    if (!icon) return;
    icon.innerHTML = `<span class="ptr-kaomoji" aria-hidden="true">${kaomojiHtml()}</span>`;
    icon.style.transform = "";
  }

  function visiblePanelId() {
    for (const pid of PANEL_IDS) {
      const el = document.getElementById(pid);
      if (el && !el.classList.contains("hidden")) return pid;
    }
    return null;
  }

  function ptrActive() {
    return isPwa || !!visiblePanelId();
  }

  function mainScrollEl() {
    if (isPwa && shell) return shell;
    return document.documentElement;
  }

  function panelShell(panelId) {
    return document.getElementById(panelId);
  }

  function panelScroller(panelId) {
    const panel = panelShell(panelId);
    if (!panel) return null;
    if (panelId === "admin-panel") {
      return panel.querySelector(".admin-panel-body") || panel;
    }
    if (panelId === "history") {
      return panel.querySelector(".history-panel-body") || panel;
    }
    if (panelId === "photo-gallery") {
      return panel.querySelector(".photo-gallery-body") || panel;
    }
    return panel;
  }

  function panelPtrShell(el) {
    if (!el) return null;
    if (el.classList?.contains("admin-panel-body")) {
      return el.closest("#admin-panel");
    }
    if (el.classList?.contains("history-panel-body")) {
      return el.closest("#history");
    }
    if (el.classList?.contains("photo-gallery-body")) {
      return el.closest("#photo-gallery");
    }
    return el.id && PANEL_IDS.has(el.id) ? el : null;
  }

  function activeScrollEl() {
    const blocked = ["checkin-detail"];
    for (const id of blocked) {
      const el = document.getElementById(id);
      if (el && !el.classList.contains("hidden")) return null;
    }
    const id = visiblePanelId();
    if (id) return panelScroller(id);
    return mainScrollEl();
  }

  function isPanelRefresh() {
    return !!panelPtrShell(scrollEl);
  }

  function scrollTop(el) {
    if (!el || el === document.documentElement) {
      return window.scrollY || document.documentElement.scrollTop || 0;
    }
    return el.scrollTop;
  }

  function overlayBlocksPtr() {
    if (document.querySelector("dialog[open]")) return true;
    return !!document.querySelector(
      ".invite-ips-panel:not(.hidden), .patchnotes-panel:not(.hidden)"
    );
  }

  function computeOffset(delta) {
    const linear = delta * RESISTANCE;
    if (linear <= MAX_PULL) return linear;
    const extra = linear - MAX_PULL;
    return Math.min(MAX_PULL + extra * RUBBER, ABS_MAX);
  }

  function pullProgress(dist) {
    return Math.min(1, Math.max(0, dist / THRESHOLD));
  }

  function easterPrimed(dist, delta) {
    return dist >= ABS_MAX - 0.5 && delta >= EASTER_RAW_MIN;
  }

  function isOverpull(dist, delta) {
    if (!easterPrimed(dist, delta)) {
      overpullStart = 0;
      return false;
    }
    if (!overpullStart) overpullStart = performance.now();
    return performance.now() - overpullStart >= EASTER_HOLD_MS;
  }

  function resetPanelPtr(panel) {
    if (!panel) return;
    panel.style.setProperty("--ptr-offset", "0px");
    panel.classList.remove("ptr-dragging", "ptr-pulling");
  }

  function resetAllPanelPtr() {
    for (const id of PANEL_IDS) resetPanelPtr(document.getElementById(id));
  }

  function setPullOffset(px, dragging) {
    const progress = pullProgress(px);
    indicator.style.setProperty("--ptr-progress", String(progress));

    if (isPanelRefresh()) {
      const panel = panelPtrShell(scrollEl);
      if (shell) {
        shell.style.setProperty("--ptr-offset", "0px");
        shell.classList.remove("ptr-dragging", "ptr-pulling");
      }
      if (panel) {
        panel.style.setProperty("--ptr-offset", `${px}px`);
        panel.classList.toggle("ptr-dragging", !!dragging);
        panel.classList.toggle("ptr-pulling", px > 4);
      }
      return;
    }

    resetAllPanelPtr();
    if (!shell) return;
    shell.style.setProperty("--ptr-offset", `${px}px`);
    shell.style.setProperty("--ptr-progress", String(progress));
    shell.classList.toggle("ptr-dragging", !!dragging);
    shell.classList.toggle("ptr-pulling", px > 4);
  }

  function updateLabel(dist, delta) {
    if (!label) return;
    if (isOverpull(dist, delta)) {
      label.innerHTML =
        'pas plus haut que le bord <span class="ptr-kaomoji" aria-hidden="true">' +
        kaomojiHtml() +
        "</span>";
      return;
    }
    if (dist >= THRESHOLD) {
      label.textContent = isPanelRefresh() ? "Relâche pour rafraîchir" : "Relâche pour actualiser";
      return;
    }
    label.textContent = isPanelRefresh() ? "Tire pour rafraîchir" : "Tire pour actualiser";
  }

  function updateIndicator(dist, delta) {
    const progress = pullProgress(dist);
    const over = isOverpull(dist, delta);
    const ready = dist >= THRESHOLD && !over;

    setPullOffset(dist, true);
    indicator.classList.toggle("visible", dist > 4);
    indicator.classList.toggle("ready", ready);
    indicator.classList.toggle("overpull", over);

    if (over) {
      setIconKaomoji();
    } else if (icon) {
      setIconArrow();
      icon.style.transform = `rotate(${Math.min(180, progress * 180)}deg)`;
    }

    updateLabel(dist, delta);
  }

  function resetIndicator() {
    pullDist = 0;
    rawDelta = 0;
    overpullStart = 0;
    setPullOffset(0, false);
    indicator.classList.remove("visible", "ready", "loading", "overpull");
    setIconArrow();
    if (label) label.textContent = "Tire pour actualiser";
    if (shell) shell.classList.remove("ptr-pulling");
    resetAllPanelPtr();
  }

  function finishRefresh() {
    refreshing = false;
    window.setTimeout(resetIndicator, 160);
  }

  function runRefresh(panelId) {
    const resolved = panelId || visiblePanelId();
    if (resolved) {
      const refresh = window.__beerPtrRefresh;
      if (typeof refresh === "function") {
        Promise.resolve(refresh(resolved))
          .catch(() => {})
          .finally(finishRefresh);
      } else {
        finishRefresh();
      }
      return;
    }
    // Accueil seulement (aucun panneau ouvert) — pas de reload si overlay visible
    if (document.querySelector(".beer-overlay:not(.hidden), #checkin-detail:not(.hidden), #photo-gallery:not(.hidden)")) {
      finishRefresh();
      return;
    }
    window.setTimeout(() => window.location.reload(), 180);
  }

  function doRefresh() {
    if (refreshing) return;
    refreshing = true;
    overpullStart = 0;
    if (shell) shell.classList.remove("ptr-dragging");
    setPullOffset(THRESHOLD, false);
    indicator.classList.add("loading", "visible");
    indicator.classList.remove("ready", "overpull");
    if (icon) {
      icon.textContent = "↻";
      icon.style.transform = "";
    }
    if (label) label.textContent = "Actualisation…";

    const panelId = visiblePanelId();
    if (panelId) {
      runRefresh(panelId);
      return;
    }
    if (isPanelRefresh()) {
      runRefresh(visiblePanelId());
      return;
    }
    runRefresh(null);
  }

  function ptrIgnoreTarget(target) {
    if (target?.closest?.(".admin-head button, .history-head button, .wishlist-head button")) {
      return true;
    }
    return !!target?.closest?.("header.top, .top-actions, #plexi-hub-nav");
  }

  function canStartPanelPtr(target) {
    const panelId = visiblePanelId();
    if (!panelId) return isPwa;
    const scroller = panelScroller(panelId);
    if (!scroller || scrollTop(scroller) > 2) return false;
    return !!target?.closest?.(`#${panelId}`);
  }

  window.__beerSealPtrShell = function () {
    if (shell) {
      shell.style.setProperty("--ptr-offset", "0px");
      shell.classList.remove("ptr-dragging", "ptr-pulling");
    }
    resetAllPanelPtr();
  };

  document.addEventListener(
    "touchstart",
    (e) => {
      if (!ptrActive() || refreshing || overlayBlocksPtr() || ptrIgnoreTarget(e.target)) return;
      scrollEl = activeScrollEl();
      if (!scrollEl || !canStartPanelPtr(e.target)) return;
      if (scrollTop(scrollEl) > 2) return;
      startY = e.touches[0].clientY;
      pulling = true;
      pullDist = 0;
      rawDelta = 0;
      overpullStart = 0;
    },
    { passive: true }
  );

  document.addEventListener(
    "touchmove",
    (e) => {
      if (!pulling || refreshing || !scrollEl) return;
      const y = e.touches[0].clientY;
      rawDelta = y - startY;
      if (rawDelta <= 0) {
        resetIndicator();
        return;
      }
      if (scrollTop(scrollEl) > 2) {
        pulling = false;
        resetIndicator();
        return;
      }
      pullDist = computeOffset(rawDelta);
      updateIndicator(pullDist, rawDelta);
      if (pullDist > 6) e.preventDefault();
    },
    { passive: false }
  );

  document.addEventListener(
    "touchend",
    () => {
      if (!pulling) return;
      pulling = false;
      if (pullDist >= THRESHOLD) {
        doRefresh();
        return;
      }
      resetIndicator();
    },
    { passive: true }
  );

  document.addEventListener("touchcancel", () => {
    pulling = false;
    if (!refreshing) resetIndicator();
  });
})();
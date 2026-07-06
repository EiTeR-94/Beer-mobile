(function () {
  "use strict";

  const ROOT = (window.BEER_ROOT || "").replace(/\/$/, "");
  const api = (path) => `${ROOT}${path}`;
  const MAX_FLAVORS = 8;
  const MAX_HOPS = 6;

  function fetchApi(path, options = {}) {
    const creds = window.BEER_MOBILE ? "include" : "same-origin";
    return fetch(api(path), { credentials: creds, ...options });
  }

  function sealOverlay() {
    if (typeof window.__beerSealPtrShell === "function") window.__beerSealPtrShell();
  }

  // --- Offline write queue via IndexedDB ---
  let _queueDB = null;

  function openQueueDB() {
    if (_queueDB) return Promise.resolve(_queueDB);
    return new Promise((resolve, reject) => {
      const req = indexedDB.open("beer-offline-queue", 1);
      req.onupgradeneeded = (ev) => {
        const db = ev.target.result;
        if (!db.objectStoreNames.contains("ops")) {
          const store = db.createObjectStore("ops", { keyPath: "id", autoIncrement: true });
          store.createIndex("ts", "ts", { unique: false });
        }
      };
      req.onsuccess = (ev) => {
        _queueDB = ev.target.result;
        resolve(_queueDB);
      };
      req.onerror = (ev) => reject(ev.target.error);
    });
  }

  async function enqueueOp(type, data) {
    const db = await openQueueDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("ops", "readwrite");
      const store = tx.objectStore("ops");
      const op = { type: type, data: data, ts: Date.now() };
      const req = store.add(op);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async function getQueuedOps() {
    const db = await openQueueDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("ops", "readonly");
      const store = tx.objectStore("ops");
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
  }

  async function deleteQueuedOp(id) {
    const db = await openQueueDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("ops", "readwrite");
      const store = tx.objectStore("ops");
      const req = store.delete(id);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  }

  function pathToOpType(path, method) {
    const m = (method || "POST").toUpperCase();
    if (path.indexOf("/api/checkins") !== -1 && m === "POST") return "create-checkin";
    if (path.indexOf("/api/checkins") !== -1 && m === "PATCH") return "update-checkin";
    if (path.indexOf("/api/wishlist") !== -1 && m === "POST") return "add-wishlist";
    if (path.indexOf("/api/wishlist") !== -1 && m === "DELETE") return "delete-wishlist";
    if (path.indexOf("/api/checkins") !== -1 && m === "DELETE") return "delete-checkin";
    return "write-op";
  }

  async function enqueueFetchOp(path, options) {
    let serBody = null;
    if (options && options.body && typeof options.body === "string") {
      try { serBody = JSON.parse(options.body); } catch (e) { serBody = options.body; }
    }
    const type = pathToOpType(path, options ? options.method : null);
    await enqueueOp(type, {
      path: path,
      method: (options && options.method) || "POST",
      headers: (options && options.headers) || null,
      body: serBody
    });
  }

  async function enqueueCreateCheckin(data) {
    await enqueueOp("create-checkin", data);
  }

  function isNetworkError(e) {
    if (!e) return true;
    const msg = String(e.message || e || e.toString ? e.toString() : "").toLowerCase();
    const name = (e && e.name) || "";
    return name === "TypeError" ||
           name === "NetworkError" ||
           name === "AbortError" ||
           msg.includes("failed to fetch") ||
           msg.includes("load failed") ||
           msg.includes("failed to load") ||
           msg.includes("network") ||
           msg.includes("connexion impossible") ||
           msg.includes("offline") ||
           msg.includes("net::err");
  }

  async function safeFetchApi(path, options = {}) {
    const method = (options.method || "GET").toUpperCase();
    const isWrite = (method === "POST" || method === "PATCH" || method === "PUT" || method === "DELETE");
    const isUserWrite = isWrite && (path.indexOf("/api/checkins") !== -1 || path.indexOf("/api/wishlist") !== -1);
    if (isUserWrite && !navigator.onLine) {
      await enqueueFetchOp(path, options);
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { "Content-Type": "application/json", "X-Queued": "1" }
      });
    }
    try {
      const resp = await fetchApi(path, options);
      return resp;
    } catch (e) {
      if (isUserWrite && isNetworkError(e)) {
        await enqueueFetchOp(path, options);
        return new Response(JSON.stringify({ queued: true }), {
          status: 200,
          headers: { "Content-Type": "application/json", "X-Queued": "1" }
        });
      }
      throw e;
    }
  }

  async function replayOp(op) {
    const type = op.type;
    const data = op.data || {};
    if (type === "create-checkin") {
      const fd = new FormData();
      const fields = ["barcode", "beer_name", "brewery", "style", "abv", "summary", "rating", "comment", "untappd_bid", "force"];
      fields.forEach(function (k) {
        if (data[k] != null && data[k] !== undefined) {
          if (k === "force" && data[k]) {
            fd.append("force", "true");
          } else {
            fd.append(k, data[k]);
          }
        }
      });
      if (data.flavors) {
        fd.append("flavors", JSON.stringify(data.flavors));
      }
      if (data.hops) {
        fd.append("hops", JSON.stringify(data.hops));
      }
      if (data.photo) {
        const p = data.photo;
        fd.append("photo", p, (p && p.name) ? p.name : "photo.jpg");
      }
      const resp = await fetchApi("/api/checkins", { method: "POST", body: fd });
      if (!resp.ok && resp.status !== 409) {
        const err = await resp.json().catch(function () { return {}; });
        throw new Error(err.detail || err.error || "replay create-checkin failed");
      }
      return;
    }
    // json-style writes (update, wishlist, delete-checkin, ...)
    const opts = {
      method: data.method,
      headers: data.headers || (data.body ? { "Content-Type": "application/json" } : undefined),
      body: data.body ? JSON.stringify(data.body) : undefined
    };
    const resp = await fetchApi(data.path, opts);
    if (!resp.ok) {
      const err = await resp.json().catch(function () { return {}; });
      throw new Error(err.detail || err.error || "replay write failed");
    }
  }

  async function flushWriteQueue() {
    if (!navigator.onLine) return;
    let ops = [];
    try {
      ops = await getQueuedOps();
    } catch (e) { return; }
    if (!ops || !ops.length) return;
    ops = ops.slice().sort(function (a, b) { return (a.ts || 0) - (b.ts || 0); });
    let count = 0;
    for (let i = 0; i < ops.length; i++) {
      const op = ops[i];
      try {
        await replayOp(op);
        if (op.id != null) await deleteQueuedOp(op.id);
        count++;
      } catch (e) {
        // stop to preserve ordering; will retry on next online
        break;
      }
    }
    if (count > 0) {
      toast(count + " action(s) synchronisée(s)");
      try { if (els && els.historyList) loadHistory().catch(function(){}); } catch (e) {}
      try { if (els && els.wishlistList) loadWishlist().catch(function(){}); } catch (e) {}
    }
  }

  async function safeFetchApiForFormData(path, options) {
    // used optionally; for checkin we handle directly in postCheckin
    const method = (options.method || "GET").toUpperCase();
    const isWrite = (method === "POST" || method === "PATCH" || method === "PUT" || method === "DELETE");
    if (isWrite && (path.indexOf("/checkins") !== -1 || path.indexOf("/wishlist") !== -1) && !navigator.onLine) {
      // cannot auto enqueue arbitrary FormData here; caller must use enqueueCreateCheckin
      return new Response(JSON.stringify({ queued: true }), { status: 200, headers: { "Content-Type": "application/json", "X-Queued": "1" } });
    }
    try {
      return await fetchApi(path, options);
    } catch (e) {
      if (isWrite && isNetworkError(e)) {
        return new Response(JSON.stringify({ queued: true }), { status: 200, headers: { "Content-Type": "application/json", "X-Queued": "1" } });
      }
      throw e;
    }
  }

  const state = {
    step: 1,
    beer: null,
    photoFile: null,
    rating: 0,
    flavors: new Set(),
    scanning: false,
    scanCameraActive: false,
    linking: false,
    lastUntappdResults: null,
    isAdmin: false,
    isInvite: false,
    currentUser: null,
    historyItems: [],
    galleryItems: [],
    wishlistItems: [],
    giftsItems: [],
    adminUsers: [],
    adminInvites: [],
    editCheckin: null,
    editRating: 0,
    editFlavors: new Set(),
    hops: new Set(),
    editHops: new Set(),
    presetFlavorTags: [],
    editPresetFlavorTags: [],
    presetHops: [],
    editPresetHops: [],
    detailCheckin: null,
    editPhotoFile: null,
    editRemovePhoto: false,
    historySearchTimer: null,
    gallerySearchTimer: null,
    toastTimer: null,

    historyFilters: { style: "", minRating: 0, period: "" },
    historyOffset: 0,
    historyLimit: 10,
    historyHasMore: false,
    isLoadingHistory: false,
    historyObserver: null,
  };

  let els = {};

  const scanProfile = {
    mode: "native",
    reason: "fallback",
    autoScan: false,
    liveFailed: false,
  };

  const scanCamera = {
    stream: null,
    rafId: null,
    detector: null,
    lastDetect: 0,
    starting: false,
    wasGranted: false,
    useServerScan: false,
    serverBusy: false,
  };

  const SCAN_FRAME = { width: 0.82, height: 0.28 };

  let mainSliderApi = null;
  let editSliderApi = null;

  function $(id) {
    return document.getElementById(id);
  }

  function bindElements() {
    els = {
      steps: document.querySelectorAll(".step"),
      panels: document.querySelectorAll(".panel"),
      scanInput: $("scan-input"),
      scanPreview: $("scan-preview"),
      scanPlaceholder: $("scan-placeholder"),
      scanHint: $("scan-hint"),
      scanStatus: $("scan-status"),
      scanViewfinder: $("scan-viewfinder"),
      scanStage: $("scan-stage"),
      scanVideo: $("scan-video"),
      scanCanvas: $("scan-canvas"),
      btnScanStart: $("btn-scan-start"),
      btnScanCapture: $("btn-scan-capture"),
      btnScanNative: $("btn-scan-native"),
      barcodeInput: $("barcode-input"),
      eanManual: $("ean-manual"),
      untappdPanel: $("untappd-panel"),
      untappdQuery: $("untappd-query"),
      untappdBrewery: $("untappd-brewery"),
      untappdName: $("untappd-name"),
      untappdResults: $("untappd-results"),
      btnUntappdSearch: $("btn-untappd-search"),
      localName: $("local-name"),
      localBrewery: $("local-brewery"),
      localStyle: $("local-style"),
      btnLocalSave: $("btn-local-save"),
      beerPreview: $("beer-preview"),
      btnLookup: $("btn-lookup"),
      btnToPhoto: $("btn-to-photo"),
      btnAddWishlist: $("btn-add-wishlist"),
      photoInput: $("photo-input"),
      photoPreview: $("photo-preview"),
      photoPlaceholder: $("photo-placeholder"),
      btnToRating: $("btn-to-rating"),
      btnBack1: $("btn-back-1"),
      btnBack2: $("btn-back-2"),
      ratingBeerName: $("rating-beer-name"),
      noBeerHint: $("no-beer-hint"),
      sliderWrapper: $("rating-slider-wrapper"),
      sliderTrack: $("slider-track"),
      sliderFill: $("slider-fill"),
      sliderThumb: $("slider-thumb"),
      sliderTicks: $("slider-ticks"),
      noteValue: $("note-value"),
      ratingLabel: $("rating-label"),
      flavorTags: $("flavor-tags"),
      customFlavorInput: $("custom-flavor-input"),
      btnAddCustomFlavor: $("btn-add-custom-flavor"),
      customFlavorTags: $("custom-flavor-tags"),
      styleLabel: $("style-label"),
      tagsTitleLabel: $("tags-title-label"),
      editTagsTitle: $("edit-tags-title"),
      wizardPanel3: document.querySelector('.panel[data-panel="3"]'),
      hopTags: $("hop-tags"),
      customHopInput: $("custom-hop-input"),
      btnAddCustomHop: $("btn-add-custom-hop"),
      customHopTags: $("custom-hop-tags"),
      customStyleInput: $("custom-style-input"),
      btnAddCustomStyle: $("btn-add-custom-style"),
      editHopTags: $("edit-hop-tags"),
      editCustomHopInput: $("edit-custom-hop-input"),
      btnEditAddCustomHop: $("btn-edit-add-custom-hop"),
      editCustomHopTags: $("edit-custom-hop-tags"),
      comment: $("comment"),
      commentCount: $("comment-count"),
      btnSave: $("btn-save"),
      history: $("history"),
      historyList: $("history-list"),
      btnHistory: $("btn-history"),
      btnCloseHistory: $("btn-close-history"),
      historyStats: $("history-stats"),
      historyFilterStyle: $("history-filter-style"),
      historyFilterRating: $("history-filter-rating"),
      historyFilterPeriod: $("history-filter-period"),
      historySearch: $("history-search"),
      gallerySearch: $("gallery-search"),
      photoGallery: $("photo-gallery"),
      galleryGrid: $("gallery-grid"),
      btnOpenGallery: $("btn-open-gallery"),
      btnCloseGallery: $("btn-close-gallery"),
      galleryFilterStyle: $("gallery-filter-style"),
      galleryFilterRating: $("gallery-filter-rating"),
      galleryFilterPeriod: $("gallery-filter-period"),
      btnWishlist: $("btn-wishlist"),
      wishlistPanel: $("wishlist-panel"),
      btnCloseWishlist: $("btn-close-wishlist"),
      wishlistList: $("wishlist-list"),
      btnGifts: $("btn-gifts"),
      btnCloseGifts: $("btn-close-gifts"),
      giftsPanel: $("gifts-panel"),
      giftsCoupleStats: $("gifts-couple-stats"),
      giftsList: $("gifts-list"),
      giftsSearch: $("gifts-search"),
      giftsFilterStyle: $("gifts-filter-style"),
      giftsFilterRating: $("gifts-filter-rating"),
      globalSearch: $("global-search"),
      wishName: $("wish-name"),
      wishBrewery: $("wish-brewery"),
      btnWishAdd: $("btn-wish-add"),
      editDialog: $("edit-dialog"),
      editTitle: $("edit-title"),
      editMeta: $("edit-meta"),
      editFlavorTags: $("edit-flavor-tags"),
      editCustomFlavorInput: $("edit-custom-flavor-input"),
      btnEditAddCustomFlavor: $("btn-edit-add-custom-flavor"),
      editCustomFlavorTags: $("edit-custom-flavor-tags"),
      editComment: $("edit-comment"),
      btnEditCancel: $("btn-edit-cancel"),
      btnEditSave: $("btn-edit-save"),
      checkinDetail: $("checkin-detail"),
      btnCloseDetail: $("btn-close-detail"),
      btnDetailEdit: $("btn-detail-edit"),
      btnDetailHide: $("btn-detail-hide"),
      btnDetailRetaste: $("btn-detail-retaste"),
      editHideField: $("edit-hide-field"),
      editHiddenPartner: $("edit-hidden-partner"),
      detailPhoto: $("detail-photo"),
      detailNoPhoto: $("detail-no-photo"),
      detailName: $("detail-name"),
      detailMeta: $("detail-meta"),
      detailStars: $("detail-stars"),
      detailFlavors: $("detail-flavors"),
      detailComment: $("detail-comment"),
      editPhotoInput: $("edit-photo-input"),
      editPhotoPreview: $("edit-photo-preview"),
      editPhotoPlaceholder: $("edit-photo-placeholder"),
      btnEditRemovePhoto: $("btn-edit-remove-photo"),
      editRatingSliderWrapper: $("edit-rating-slider-wrapper"),
      editSliderTrack: $("edit-slider-track"),
      editSliderFill: $("edit-slider-fill"),
      editSliderTicks: $("edit-slider-ticks"),
      editSliderThumb: $("edit-slider-thumb"),
      editNoteValue: $("edit-note-value"),
      btnAdmin: $("btn-admin"),
      adminPanel: $("admin-panel"),
      btnCloseAdmin: $("btn-close-admin"),
      btnAdminRefresh: $("btn-admin-refresh"),
      adminUserList: $("admin-user-list"),
      adminNewUser: $("admin-new-user"),
      adminNewPass: $("admin-new-pass"),
      adminNewIsAdmin: $("admin-new-is-admin"),
      btnAdminCreate: $("btn-admin-create"),
      userPill: $("user-pill"),
      btnLogout: $("btn-logout"),
      btnPatchnotes: $("btn-patchnotes"),
      patchnotesScrim: $("patchnotes-scrim"),
      patchnotesPanel: $("patchnotes-panel"),
      patchContent: $("patch-content"),
      patchnotesVersion: $("patchnotes-version"),
      btnClosePatchnotes: $("btn-close-patchnotes"),
      btnClosePatchnotesFooter: $("btn-close-patchnotes-footer"),
      duplicateDialog: $("duplicate-dialog"),
      duplicateDialogContent: $("duplicate-dialog-content"),
      btnDuplicateCancel: $("btn-duplicate-cancel"),
      btnDuplicateConfirm: $("btn-duplicate-confirm"),
      toast: $("toast"),
      toastScrim: $("toast-scrim"),
      btnCleanupPhotos: $("btn-cleanup-photos"),
      cleanupResult: $("cleanup-result"),
      adminStylesHops: $("admin-styles-hops"),
      inviteLabel: $("invite-label"),
      inviteDays: $("invite-days"),
      btnInviteCreate: $("btn-invite-create"),
      inviteCreateResult: $("invite-create-result"),
      inviteNewUrl: $("invite-new-url"),
      btnInviteCopy: $("btn-invite-copy"),
      adminInviteList: $("admin-invite-list"),
      btnInviteIpsAll: $("btn-invite-ips-all"),
      inviteIpsScrim: $("invite-ips-scrim"),
      inviteIpsPanel: $("invite-ips-panel"),
      inviteIpsBody: $("invite-ips-body"),
      inviteIpsTitle: $("invite-ips-title"),
      btnCloseInviteIps: $("btn-close-invite-ips"),
      btnCloseInviteIpsFooter: $("btn-close-invite-ips-footer"),
      inviteHelpBar: $("invite-help-bar"),
      btnDismissInviteHelp: $("btn-dismiss-invite-help"),
      pwaHintBar: $("pwa-hint-bar"),
      btnDismissPwaHint: $("btn-dismiss-pwa-hint"),
    };
  }

  function formatDateShort(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return formatDate(iso);
    const day = d.toLocaleDateString("fr-FR", { day: "numeric", month: "short" });
    const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
    return `${day} · ${time}`;
  }

  function formatActivityAgo(iso) {
    if (!iso) return "—";
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return formatDateShort(iso);
    const diff = Date.now() - d.getTime();
    if (diff < 60_000) return "à l'instant";
    if (diff < 3_600_000) {
      const min = Math.floor(diff / 60_000);
      return `il y a ${min} min`;
    }
    if (diff < 86_400_000) {
      const h = Math.floor(diff / 3_600_000);
      return `il y a ${h} h`;
    }
    return formatDateShort(iso);
  }

  function inviteActivityLine(inv) {
    if (!inv.redeemed_at) return "";
    const when = inv.last_used_at || inv.redeemed_at;
    const ip = (inv.last_used_at ? inv.last_used_ip : inv.redeem_ip) || "";
    const parts = [`Dernière activité · ${formatActivityAgo(when)}`];
    if (ip) parts.push(`IP ${ip}`);
    const ipBtn = inv.redeemed_at
      ? `<button type="button" class="btn invite-ips-chip" data-invite-ips="${inv.id}" title="Historique IP">IP</button>`
      : "";
    return `<div class="invite-activity-line"><p class="invite-activity-text">${esc(parts.join(" · "))}</p>${ipBtn}</div>`;
  }

  function renderInviteIpRows(ipLog) {
    if (!ipLog?.length) {
      return "<p class='meta'>Aucune adresse enregistrée.</p>";
    }
    return `<ul class="invite-ip-list">${ipLog
      .map((entry) => {
        const first = entry.first_seen ? formatDateShort(entry.first_seen) : "—";
        const last = entry.last_seen ? formatActivityAgo(entry.last_seen) : "—";
        return `<li><code>${esc(entry.ip)}</code><span class="meta"> · 1re ${esc(first)} · dernière ${esc(last)}</span></li>`;
      })
      .join("")}</ul>`;
  }

  function closePatchnotesPanel() {
    els.patchnotesScrim?.classList.add("hidden");
    els.patchnotesPanel?.classList.add("hidden");
  }

  function bindPatchnotesPanel() {
    if (!els.patchnotesPanel) return;
    const close = closePatchnotesPanel;
    els.btnClosePatchnotes?.addEventListener("click", (e) => {
      e.preventDefault();
      close();
    });
    els.btnClosePatchnotesFooter?.addEventListener("click", (e) => {
      e.preventDefault();
      close();
    });
    els.patchnotesScrim?.addEventListener("click", close);
  }

  async function openPatchnotesPanel() {
    if (!els.patchnotesPanel || !els.patchContent) return;
    els.patchContent.textContent = "Chargement…";
    if (els.patchnotesVersion) els.patchnotesVersion.textContent = "";
    sealOverlay();
    els.patchnotesScrim?.classList.remove("hidden");
    els.patchnotesPanel.classList.remove("hidden");
    try {
      const r = await fetchApi("/api/admin/patchnotes");
      const d = await r.json();
      if (els.patchnotesVersion && d.version) {
        els.patchnotesVersion.textContent = `(v${d.version})`;
      }
      els.patchContent.textContent = d.markdown?.trim() || "Aucune note de version.";
    } catch (e) {
      els.patchContent.textContent = "Indisponible.";
      toast("Patch notes indisponibles");
    }
  }

  function closeInviteIpsDialog() {
    els.inviteIpsScrim?.classList.add("hidden");
    els.inviteIpsPanel?.classList.add("hidden");
  }

  function bindInviteIpsDialog() {
    if (!els.inviteIpsPanel) return;
    const close = closeInviteIpsDialog;
    els.btnCloseInviteIps?.addEventListener("click", (e) => {
      e.preventDefault();
      close();
    });
    els.btnCloseInviteIpsFooter?.addEventListener("click", (e) => {
      e.preventDefault();
      close();
    });
    els.inviteIpsScrim?.addEventListener("click", close);
  }

  function openInviteIpsDialog(inviteId = null) {
    if (!els.inviteIpsPanel || !els.inviteIpsBody) return;
    const pool = inviteId
      ? state.adminInvites.filter((i) => i.id === inviteId)
      : state.adminInvites.filter((i) => (i.ip_log || []).length > 0 || i.redeemed_at);
    if (!pool.length) {
      if (els.inviteIpsTitle) els.inviteIpsTitle.textContent = "IP invités";
      els.inviteIpsBody.innerHTML = "<p class='meta'>Aucun invité avec activité IP pour l'instant.</p>";
    } else if (inviteId && pool.length === 1) {
      if (els.inviteIpsTitle) els.inviteIpsTitle.textContent = `IP — ${pool[0].label}`;
      els.inviteIpsBody.innerHTML = renderInviteIpRows(pool[0].ip_log);
    } else {
      if (els.inviteIpsTitle) els.inviteIpsTitle.textContent = "IP invités";
      els.inviteIpsBody.innerHTML = pool
        .map(
          (inv) => `
        <section class="invite-ip-group">
          <h4>${esc(inv.label)} <span class="meta">${esc(inv.username)}</span></h4>
          ${renderInviteIpRows(inv.ip_log)}
        </section>`
        )
        .join("");
    }
    sealOverlay();
    els.inviteIpsScrim?.classList.remove("hidden");
    els.inviteIpsPanel.classList.remove("hidden");
  }

  const TOAST_META = {
    success: { icon: "✓", label: "C'est bon" },
    info: { icon: "🍺", label: "Info" },
    warn: { icon: "!", label: "Attention" },
    error: { icon: "✕", label: "Oups" },
    duplicate: { icon: "↻", label: "Déjà goûtée" },
  };

  function inferToastVariant(message) {
    const m = (message || "").toLowerCase();
    if (
      /✓|enregistrée|mise à jour|ajouté|créé|mémorisée|chargée|retiré|supprimée|mis à jour/.test(
        m
      )
    ) {
      return "success";
    }
    if (
      /erreur|impossible|échec|illisible|introuvable|indisponible|connexion|expirée|invalide/.test(
        m
      )
    ) {
      return "error";
    }
    if (
      /minimum|maximum|choisis|indique|tape|déjà ajouté|caractères|note-la/.test(m)
    ) {
      return "warn";
    }
    return "info";
  }

  function resolveToast(input, durationMs = 2800) {
    if (typeof input === "string") {
      const variant = inferToastVariant(input);
      return {
        variant,
        message: input.replace(/\s*✓\s*$/, "").trim(),
        durationMs,
      };
    }
    const o = { ...(input || {}) };
    if (o.title && !o.label) o.label = o.title;
    if (o.body && !o.message) o.message = o.body;
    o.variant = o.variant || "info";
    o.durationMs = o.durationMs ?? o.duration ?? durationMs;
    return o;
  }

  function toastCardMarkup({ variant, label, message, detail, extraHtml }) {
    const meta = TOAST_META[variant] || TOAST_META.info;
    const lbl = label || meta.label;
    const icon = meta.icon;
    return `<div class="toast-card toast-card--${variant}">
      <span class="toast-card-icon" aria-hidden="true">${icon}</span>
      <p class="toast-card-label">${esc(lbl)}</p>
      ${message ? `<p class="toast-card-message">${esc(message)}</p>` : ""}
      ${detail ? `<p class="toast-card-detail">${esc(detail)}</p>` : ""}
      ${extraHtml || ""}
    </div>`;
  }

  function duplicateCheckinMarkup(pc, beerNameFallback, hint) {
    const rating = normalizeRating(pc?.rating || 0);
    const stars = renderStarVisual(rating);
    const when = formatDateShort(pc?.created_at);
    const beerName = pc?.beer_name || beerNameFallback || "Cette bière";

    return toastCardMarkup({
      variant: "duplicate",
      message: beerName,
      detail: hint,
      extraHtml: `<div class="toast-card-meta">
        <span class="toast-card-stars" aria-label="${formatRatingLabel(rating)}">${stars}</span>
        ${when ? `<span class="toast-card-badge">${esc(when)}</span>` : ""}
      </div>`,
    });
  }

  function toastPreviousCheckin(pc, beerNameFallback) {
    toast({
      variant: "duplicate",
      durationMs: 5200,
      html: duplicateCheckinMarkup(
        pc,
        beerNameFallback,
        "Tu pourras confirmer une nouvelle note à l'enregistrement"
      ),
    });
  }

  function confirmDuplicateCheckin(pc, beerNameFallback) {
    return new Promise((resolve) => {
      if (!els.duplicateDialog || !els.duplicateDialogContent) {
        resolve(false);
        return;
      }

      els.duplicateDialogContent.innerHTML = duplicateCheckinMarkup(
        pc,
        beerNameFallback,
        "Ajouter cette nouvelle note à ton historique ?"
      );

      const finish = (ok) => {
        els.duplicateDialog.close();
        els.btnDuplicateCancel?.removeEventListener("click", onCancel);
        els.btnDuplicateConfirm?.removeEventListener("click", onConfirm);
        els.duplicateDialog.removeEventListener("cancel", onCancel);
        resolve(ok);
      };

      const onCancel = () => finish(false);
      const onConfirm = () => finish(true);

      els.btnDuplicateCancel?.addEventListener("click", onCancel);
      els.btnDuplicateConfirm?.addEventListener("click", onConfirm);
      els.duplicateDialog.addEventListener("cancel", onCancel);
      els.duplicateDialog.showModal();
    });
  }

  function hideToast() {
    if (state.toastTimer) {
      clearTimeout(state.toastTimer);
      state.toastTimer = null;
    }
    if (els.toast) els.toast.classList.add("hidden");
    if (els.toastScrim) els.toastScrim.classList.add("hidden");
  }

  function toast(input, durationMs = 2800) {
    if (!els.toast) return;
    const opts = resolveToast(input, durationMs);
    let html = opts.html;
    if (!html) {
      html = toastCardMarkup(opts);
    }
    if (!html) return;

    els.toast.className = "toast";
    els.toast.innerHTML = html;
    els.toast.classList.remove("hidden");
    els.toastScrim?.classList.remove("hidden");

    if (state.toastTimer) clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(hideToast, opts.durationMs);
  }

  function haptic(pattern) {
    try {
      if (navigator.vibrate) navigator.vibrate(pattern);
    } catch (e) {
      /* ignore */
    }
  }

  function formatDate(iso) {
    return (iso || "").replace("T", " ").slice(0, 16);
  }

  function notifyLookupResult(data) {
    if (!data?.ok) return;
    if (data.previous_checkin) {
      haptic([7, 40, 7]);
      toastPreviousCheckin(data.previous_checkin, data.beer_name);
    }
    if (data.degraded) {
      toast({
        variant: "warn",
        label: "Service indisponible",
        message: "Open Food Facts est hors ligne",
        detail: "Utilise Untappd ou la saisie manuelle",
        durationMs: 4200,
      });
    }
  }

  function normalizeFlavorInput(raw) {
    return (raw || "").trim().replace(/\s+/g, " ");
  }

  function flavorInSet(flavorSet, name) {
    const key = name.toLowerCase();
    for (const f of flavorSet) {
      if (f.toLowerCase() === key) return f;
    }
    return null;
  }

  function syncPresetButtons(container, flavorSet, presetTags) {
    if (!container) return;
    const presetLower = new Set((presetTags || []).map((t) => t.toLowerCase()));
    container.querySelectorAll("button.tag").forEach((btn) => {
      const tag = btn.textContent || "";
      if (!presetLower.has(tag.toLowerCase())) return;
      const on = !!flavorInSet(flavorSet, tag);
      btn.classList.toggle("on", on);
    });
  }

  function renderCustomFlavorChips({
    container,
    flavorSet,
    presetTags,
    onRemove,
  }) {
    if (!container) return;
    const presetLower = new Set((presetTags || []).map((t) => t.toLowerCase()));
    const custom = [...flavorSet].filter((f) => !presetLower.has(f.toLowerCase()));
    container.innerHTML = "";
    custom.forEach((tag) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tag on custom";
      b.textContent = `${tag} ×`;
      b.addEventListener("click", () => onRemove(tag));
      container.appendChild(b);
    });
  }

  function addTagToSet(tagSet, presetTags, raw, containerPreset, maxCount, maxMsg) {
    const name = normalizeFlavorInput(raw);
    if (name.length < 2) {
      toast("2 caractères minimum");
      return false;
    }
    if (tagSet.size >= maxCount) {
      toast(maxMsg || (maxCount + " maximum"));
      return false;
    }
    if (flavorInSet(tagSet, name)) {
      toast("Déjà ajouté");
      return false;
    }
    const presetMatch = (presetTags || []).find((t) => t.toLowerCase() === name.toLowerCase());
    if (presetMatch) {
      tagSet.add(presetMatch);
      syncPresetButtons(containerPreset, tagSet, presetTags);
    } else {
      tagSet.add(name);
    }
    return true;
  }

  // Back-compat wrapper for existing flavor calls (no dup logic)
  function addFlavorToSet(flavorSet, presetTags, raw, containerPreset) {
    return addTagToSet(flavorSet, presetTags, raw, containerPreset, MAX_FLAVORS, "8 goûts maximum");
  }

  function esc(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function normalizeRating(n) {
    const r = Math.round((Number(n) || 0) * 4) / 4;
    return Math.max(0.25, Math.min(5, r));
  }

  function formatRatingLabel(r) {
    const n = Number(r) || 0;
    return n % 1 === 0 ? `${n}/5` : `${n.toFixed(2)}/5`;
  }

  // Normalisation accents (NFKD) pour recherche floue : "mogwai" match "Mogwaï", "bière" etc.
  function normalizeSearch(str) {
    if (!str) return "";
    try {
      return String(str).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    } catch (e) {
      // fallback très vieux browser
      return String(str).toLowerCase();
    }
  }

  function ensureStarStructure(btn) {
    if (!btn || btn.querySelector('svg')) return;
    const n = Number(btn.dataset.star) || 1;
    btn.innerHTML = createStarSVG(0, n);
  }

  function createStarSVG(fillPercent, id) {
    const path = "M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z";
    const w = (fillPercent / 100) * 24;
    return `<svg width="24" height="24" viewBox="0 0 24 24" class="star-svg"><defs><clipPath id="clip${id}"><path d="${path}"/></clipPath></defs><path d="${path}" class="star-base"/><rect x="0" y="0" width="${w}" height="24" class="star-filled" clip-path="url(#clip${id})"/></svg>`;
  }

  function renderStarVisual(r) {
    const val = Math.max(0.25, Math.min(5, Math.round((Number(r) || 0) * 4) / 4));
    let html = '';
    for (let i = 1; i <= 5; i++) {
      let fill = 0;
      if (val >= i) fill = 100;
      else if (val > i - 1) fill = (val - (i - 1)) * 100;
      html += createStarSVG(fill, i);
    }
    return html;
  }

  function clearBeerSession() {
    // Clear with both possible paths to ensure logout works regardless of how cookie was set
    // (Path=/ or Path=/beer) through direct or hub proxy.
    // Include Expires for better delete on all browsers/PWA/mobile.
    const paths = ["/", "/beer"];
    const expire = "Expires=Thu, 01 Jan 1970 00:00:00 GMT";
    paths.forEach(p => {
      let c = `beer_session=; Path=${p}; Max-Age=0; ${expire}; SameSite=Lax`;
      if (location.protocol === "https:") c += "; secure";
      document.cookie = c;
    });
  }





  function canGoToStep(n) {
    return n >= 1 && n <= 3;
  }

  function updateStepButtons() {
    els.steps.forEach((s) => {
      const n = Number(s.dataset.step);
      s.disabled = false;
      s.classList.toggle("active", n === state.step);
      s.setAttribute("aria-current", n === state.step ? "step" : "false");
    });
  }

  function setStep(n) {
    if (!canGoToStep(n)) return;
    state.step = n;
    els.panels.forEach((p) => p.classList.toggle("active", Number(p.dataset.panel) === n));
    if (n === 1) {
      if (state.beer) {
        showUntappdPanel(false);
      } else {
        showUntappdPanel(true);
      }
      applyScanModeUI();
    } else {
      stopScanCamera();
    }
    if (n === 3) {
      updateRatingPanel();
      renderNotationStep().catch(() => {});
    }
    updateStepButtons();
  }

  function updateRatingPanel() {
    const beer = state.beer;
    if (els.ratingBeerName) {
      els.ratingBeerName.textContent = beer ? beer.beer_name : "Bière non identifiée";
    }
    if (els.noBeerHint) {
      els.noBeerHint.classList.toggle("hidden", !!beer);
    }
    if (window.__updateSliderVisual) {
      let v = state.rating;
      if (!v || v < 0.25) v = 3.0;
      // Update the internal lastVal so vibration logic works on next drag
      // (the __ function now handles lastVal)
      window.__updateSliderVisual(v);
      if (state.rating < 0.25) state.rating = v;
    } else if (els.noteValue) {
      els.noteValue.textContent = state.rating ? formatRatingLabel(state.rating) : "—";
    }
    if (els.btnSave) {
      els.btnSave.disabled = state.rating < 0.25 || !beer;
    }
  }

  function isRetriableFetchError(err) {
    const msg = String((err && err.message) || err || "");
    return (
      err?.name === "AbortError" ||
      msg.includes("Délai") ||
      msg.includes("Connexion") ||
      msg.includes("réseau") ||
      msg.includes("Failed to fetch") ||
      msg.includes("fetch")
    );
  }

  async function fetchJsonWithRetry(path, options = {}, cfg = {}) {
    const timeoutMs = cfg.timeoutMs ?? 45000;
    const retries = cfg.retries ?? 2;
    const retryDelayMs = cfg.retryDelayMs ?? 1400;
    const onRetry = cfg.onRetry;
    let lastErr;
    for (let attempt = 0; attempt <= retries; attempt += 1) {
      try {
        return await fetchJson(path, options, timeoutMs);
      } catch (e) {
        lastErr = e;
        if (!isRetriableFetchError(e) || attempt >= retries) throw e;
        if (onRetry) onRetry(attempt + 1, retries);
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs * (attempt + 1)));
      }
    }
    throw lastErr;
  }

  async function fetchJson(path, options = {}, timeoutMs = 45000) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const r = await safeFetchApi(path, { ...options, signal: ctrl.signal });
      // if queued via safe, the body will be {queued:true} and r.ok
      if (r && r.headers && r.headers.get && r.headers.get("X-Queued")) {
        // still parse below to return the data
      }
      if (r.status === 401) {
        // Client-side fix: clear session cookie then redirect (helps PWA re-login loops from stale/bad auth state)
        clearBeerSession();
        window.location.replace(window.BEER_MOBILE ? "./login.html" : api("/"));
        throw new Error("Session expirée — reconnecte-toi");
      }
      const text = await r.text();
      let data = {};
      try {
        data = text ? JSON.parse(text) : {};
      } catch (e) {
        throw new Error(r.ok ? "Réponse invalide" : `Erreur serveur (${r.status})`);
      }
      if (!r.ok) {
        const msg = data.detail || data.error || `Erreur serveur (${r.status})`;
        throw new Error(typeof msg === "string" ? msg : "Erreur serveur");
      }
      return data;
    } catch (e) {
      if (e.name === "AbortError") throw new Error("Délai dépassé — réessaie");
      if (e.message === "Failed to fetch") throw new Error("Connexion impossible");
      throw e;
    } finally {
      clearTimeout(timer);
    }
  }

  function setScanStatus(msg, busy) {
    if (!els.scanStatus) return;
    els.scanStatus.textContent = msg || "";
    els.scanStatus.classList.toggle("hidden", !msg);
    els.scanStatus.classList.toggle("busy", !!busy);
    if (els.scanViewfinder) {
      els.scanViewfinder.classList.toggle("disabled", !!busy);
      els.scanViewfinder.classList.toggle("busy", !!busy);
    }
    applyScanModeUI();
  }

  function isStandalonePwa() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    );
  }

  function isIOSDevice() {
    const ua = navigator.userAgent || "";
    return (
      /iPad|iPhone|iPod/i.test(ua) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    );
  }

  function isAndroidDevice() {
    return /Android/i.test(navigator.userAgent || "");
  }

  function isCapacitorApp() {
    return !!(window.BEER_MOBILE || (window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()));
  }

  function detectScanProfile() {
    const isIOS = isIOSDevice();
    const isAndroid = isAndroidDevice();
    const isPwa = isStandalonePwa();
    const hasGum = !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
    const hasDetector = typeof BarcodeDetector !== "undefined";

    if (isIOS && isCapacitorApp()) {
      return { mode: "live", reason: "ios-capacitor", autoScan: true, liveFailed: false };
    }
    if (isIOS && isPwa) {
      /* iOS PWA : pas de caméra in-app fiable (invisible dans Réglages) → photo native */
      return { mode: "native", reason: "ios-pwa", autoScan: false, liveFailed: false };
    }
    if (isIOS) {
      if (hasGum) {
        return { mode: "live", reason: "ios-safari", autoScan: true, liveFailed: false };
      }
      return { mode: "native", reason: "ios-browser", autoScan: false, liveFailed: false };
    }
    if (isAndroid && hasGum) {
      return {
        mode: "live",
        reason: isPwa ? "android-pwa" : "android-browser",
        autoScan: hasDetector,
        liveFailed: false,
      };
    }
    if (hasGum) {
      return { mode: "live", reason: "desktop", autoScan: hasDetector, liveFailed: false };
    }
    return { mode: "native", reason: "fallback", autoScan: false, liveFailed: false };
  }

  function initScanMode() {
    const detected = detectScanProfile();
    scanProfile.mode = detected.mode;
    scanProfile.reason = detected.reason;
    scanProfile.autoScan = detected.autoScan;
    scanProfile.liveFailed = false;
    applyScanModeUI();
  }

  function fallbackToNativeScan(message) {
    stopScanCamera();
    scanProfile.mode = "native";
    scanProfile.autoScan = false;
    scanProfile.liveFailed = true;
    applyScanModeUI();
    if (message) toast(message, 4200);
  }

  function applyScanModeUI() {
    const vf = els.scanViewfinder;
    if (!vf) return;
    const live = scanProfile.mode === "live";
    vf.classList.toggle("mode-live", live);
    vf.classList.toggle("mode-native", !live);
    vf.classList.toggle("camera-active", !!state.scanCameraActive);

    if (els.btnScanStart) {
      els.btnScanStart.classList.toggle("hidden", !live || state.scanCameraActive);
    }
    if (els.scanPlaceholder) {
      els.scanPlaceholder.classList.toggle("hidden", live);
    }
    if (els.btnScanCapture) {
      const showCapture = live && state.scanCameraActive;
      els.btnScanCapture.classList.toggle("hidden", !showCapture);
      els.btnScanCapture.disabled = !showCapture || state.scanning;
    }
    if (els.btnScanNative) {
      const showNativeBtn = live && !state.scanCameraActive;
      els.btnScanNative.classList.toggle("hidden", !showNativeBtn);
    }
    if (els.scanHint) {
      if (!live) {
        els.scanHint.textContent =
          scanProfile.reason === "ios-pwa"
            ? "Prendre photo — cadre le code-barres (scan auto : ouvre dans Safari)"
            : "Cadre le code-barres dans le rectangle";
      } else if (!state.scanCameraActive) {
        els.scanHint.textContent = "Touche le cadre pour activer la caméra";
      } else if (scanProfile.autoScan) {
        els.scanHint.textContent = "Place le code-barres dans le cadre — lecture automatique";
      } else {
        els.scanHint.textContent = "Place le code-barres dans le cadre, puis Capturer";
      }
    }
  }

  function pauseScanDetect() {
    if (scanCamera.rafId) {
      cancelAnimationFrame(scanCamera.rafId);
      scanCamera.rafId = null;
    }
  }

  function resumeScanDetect() {
    if (scanProfile.autoScan && scanCamera.stream && canUseScanCamera()) {
      startScanDetectLoop();
    }
  }

  function startScanDetectLoop() {
    if (!canUseScanCamera() || scanCamera.rafId || !scanCamera.stream) return;
    if (!scanCamera.detector && !scanCamera.useServerScan) return;
    scanCamera.rafId = requestAnimationFrame(scanDetectLoop);
  }

  function stopScanCamera() {
    pauseScanDetect();
    if (scanCamera.stream) {
      scanCamera.stream.getTracks().forEach((t) => t.stop());
      scanCamera.stream = null;
    }
    scanCamera.detector = null;
    scanCamera.useServerScan = false;
    scanCamera.serverBusy = false;
    scanCamera.lastDetect = 0;
    scanCamera.starting = false;
    state.scanCameraActive = false;
    if (els.scanVideo) els.scanVideo.srcObject = null;
    applyScanModeUI();
  }

  function canUseScanCamera() {
    return (
      scanProfile.mode === "live" &&
      state.step === 1 &&
      !state.scanning &&
      !state.beer &&
      document.visibilityState === "visible"
    );
  }

  async function captureViewfinderBlob() {
    const video = els.scanVideo;
    const canvas = els.scanCanvas;
    if (!video || !canvas || video.readyState < 2 || !video.videoWidth) return null;
    const vw = video.videoWidth;
    const vh = video.videoHeight;
    const fw = vw * SCAN_FRAME.width;
    const fh = vh * SCAN_FRAME.height;
    const fx = (vw - fw) / 2;
    const fy = (vh - fh) / 2;
    canvas.width = Math.max(1, Math.round(fw));
    canvas.height = Math.max(1, Math.round(fh));
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(video, fx, fy, fw, fh, 0, 0, canvas.width, canvas.height);
    return canvasToBlob(canvas, 0.88);
  }

  async function tryServerScanFromVideo() {
    if (scanCamera.serverBusy || state.scanning) return false;
    const blob = await captureViewfinderBlob();
    if (!blob) return false;
    scanCamera.serverBusy = true;
    try {
      const decoded = await serverDecodeBarcode(blob, "Analyse caméra");
      if (!decoded.ok || !decoded.barcode) return false;
      pauseScanDetect();
      if (els.eanManual) els.eanManual.value = decoded.barcode;
      await lookupBarcode(decoded.barcode, { resumeCameraOnMiss: true });
      return true;
    } catch (_) {
      return false;
    } finally {
      scanCamera.serverBusy = false;
    }
  }

  async function scanDetectLoop() {
    if (!canUseScanCamera() || !scanCamera.stream || !els.scanVideo) {
      scanCamera.rafId = null;
      return;
    }
    const now = performance.now();
    const interval = scanCamera.detector ? 280 : 1400;
    if (now - scanCamera.lastDetect >= interval && els.scanVideo.readyState >= 2) {
      scanCamera.lastDetect = now;
      if (scanCamera.detector) {
        try {
          const codes = await scanCamera.detector.detect(els.scanVideo);
          for (const c of codes) {
            const ean = normalizeEan(c.rawValue);
            if (ean.length >= 8) {
              pauseScanDetect();
              await lookupBarcode(ean);
              return;
            }
          }
        } catch (_) {
          /* frame illisible */
        }
      } else if (scanCamera.useServerScan) {
        const hit = await tryServerScanFromVideo();
        if (hit) return;
      }
    }
    scanCamera.rafId = requestAnimationFrame(scanDetectLoop);
  }

  async function waitForScanVideoReady(timeoutMs = 3000) {
    const video = els.scanVideo;
    if (!video) return false;
    if (video.readyState >= 2 && video.videoWidth > 0) return true;
    return new Promise((resolve) => {
      const deadline = performance.now() + timeoutMs;
      const done = (ok) => {
        video.removeEventListener("loadeddata", onReady);
        resolve(ok);
      };
      const onReady = () => {
        if (video.videoWidth > 0) done(true);
      };
      video.addEventListener("loadeddata", onReady);
      const tick = () => {
        if (video.readyState >= 2 && video.videoWidth > 0) {
          done(true);
          return;
        }
        if (performance.now() >= deadline) {
          done(false);
          return;
        }
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
  }

  async function startScanCamera() {
    if (!canUseScanCamera() || scanCamera.stream || scanCamera.starting || !els.scanVideo) return false;
    if (!navigator.mediaDevices?.getUserMedia) {
      fallbackToNativeScan("Caméra indisponible — mode photo activé");
      return false;
    }
    scanCamera.starting = true;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: {
          facingMode: { ideal: "environment" },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      });
      if (!canUseScanCamera()) {
        stream.getTracks().forEach((t) => t.stop());
        return false;
      }
      scanCamera.stream = stream;
      scanCamera.wasGranted = true;
      els.scanVideo.srcObject = stream;
      await els.scanVideo.play();
      state.scanCameraActive = true;
      if (scanProfile.autoScan) {
        if (typeof BarcodeDetector !== "undefined") {
          try {
            const supported = await BarcodeDetector.getSupportedFormats();
            const wanted = ["ean_13", "ean_8", "upc_a", "upc_e"];
            const formats = wanted.filter((f) => supported.includes(f));
            if (formats.length) {
              scanCamera.detector = new BarcodeDetector({ formats });
            }
          } catch (_) {
            /* BarcodeDetector indisponible */
          }
        }
        if (!scanCamera.detector) {
          scanCamera.useServerScan = true;
        }
        startScanDetectLoop();
      }
      applyScanModeUI();
      return true;
    } catch (err) {
      const denied = err?.name === "NotAllowedError" || err?.name === "PermissionDeniedError";
      const msg = denied
        ? isStandalonePwa() && isIOSDevice()
          ? "Caméra refusée — mode Prendre photo activé (Réglages > Beer Log > Caméra pour réessayer)"
          : "Caméra refusée — mode photo activé"
        : "Caméra indisponible — mode photo activé";
      fallbackToNativeScan(msg);
      return false;
    } finally {
      scanCamera.starting = false;
    }
  }

  function maybeResumeScanCamera() {
    if (scanProfile.mode === "live" && scanCamera.wasGranted && canUseScanCamera()) {
      startScanCamera();
    }
  }

  function triggerNativeScan() {
    if (state.scanning || !els.scanInput) return;
    els.scanInput.click();
  }

  async function captureFromViewfinder() {
    if (state.scanning || scanProfile.mode !== "live") return;

    if (!state.scanCameraActive) {
      const ok = await startScanCamera();
      if (!ok) return;
    }

    const video = els.scanVideo;
    const canvas = els.scanCanvas;
    if (!video || !canvas) return;

    const ready = await waitForScanVideoReady();
    if (!ready) {
      toast("Caméra en cours de démarrage — réessaie");
      return;
    }

    pauseScanDetect();
    const blob = await captureViewfinderBlob();
    if (!blob) {
      resumeScanDetect();
      toast("Capture impossible — réessaie");
      return;
    }
    const file = new File([blob], "scan.jpg", { type: "image/jpeg", lastModified: Date.now() });
    await scanBarcodePhoto(file, { keepCamera: true });
  }

  function clearScanPreview() {
    if (els.scanPreview) {
      els.scanPreview.classList.add("hidden");
      els.scanPreview.removeAttribute("src");
    }
    if (els.scanViewfinder) els.scanViewfinder.classList.remove("has-preview");
  }

  function styleLabel(beer) {
    if (!beer) return "Inconnu";
    return beer.style_fr || beer.style || "Inconnu";
  }

  function renderBeerPreview(beer) {
    const abv = beer.abv != null ? `${beer.abv}%` : "—";
    const src =
      beer.source === "untappd_web" || beer.source === "untappd"
        ? '<span class="meta-badge">Untappd</span>'
        : "";
    const eanBadge = beer.barcode ? `<span class="meta-badge">EAN associé : ${esc(beer.barcode)}</span>` : "";
    els.beerPreview.innerHTML = `
      <h2>${esc(beer.beer_name)} ${src}</h2>
      <div class="meta">${esc(beer.brewery)} · ${esc(styleLabel(beer))} · ${abv} ${eanBadge}</div>
      <div class="summary">${esc(beer.summary)}</div>
      <button type="button" class="btn ghost block change-beer" id="btn-change-beer">Changer de bière</button>
    `;
    els.beerPreview.classList.remove("hidden");
    els.btnToPhoto.classList.remove("hidden");
    if (els.btnAddWishlist && !state.isInvite) els.btnAddWishlist.classList.remove("hidden");
    const btn = $("btn-change-beer");
    if (btn) btn.addEventListener("click", clearBeerSelection);
  }

  function currentBarcode() {
    return ((els.eanManual?.value || "") || (els.barcodeInput?.value || "")).replace(/\D/g, "");
  }

  function showUntappdPanel(show) {
    if (!els.untappdPanel) return;
    els.untappdPanel.classList.toggle("hidden", !show);
    if (!show && els.untappdResults) {
      els.untappdResults.classList.add("hidden");
    }
  }

  function clearBeerSelection() {
    state.beer = null;
    state.flavors.clear();
    state.hops.clear();
    state.editHops.clear();
    if (els.eanManual) els.eanManual.value = "";
    if (els.customStyleInput) els.customStyleInput.value = "";
    if (els.localStyle) els.localStyle.value = "";
    if (els.untappdBrewery) els.untappdBrewery.value = "";
    if (els.untappdName) els.untappdName.value = "";
    if (els.untappdQuery) els.untappdQuery.value = "";
    if (els.hopTags) els.hopTags.innerHTML = "";
    if (els.customHopTags) els.customHopTags.innerHTML = "";
    if (els.beerPreview) els.beerPreview.classList.add("hidden");
    if (els.btnToPhoto) els.btnToPhoto.classList.add("hidden");
    if (els.btnAddWishlist) els.btnAddWishlist.classList.add("hidden");
    showUntappdPanel(true);
    if (state.lastUntappdResults?.length) {
      renderUntappdResults(state.lastUntappdResults);
    }
    setScanStatus("", false);
    maybeResumeScanCamera();
    updateRatingPanel();
    updateStepButtons();
  }

  function onLookupMiss(data) {
    if (data?.barcode && els.barcodeInput) {
      els.barcodeInput.value = data.barcode;
    }
    if (data?.barcode && els.eanManual) {
      els.eanManual.value = data.barcode;
    }
    if (data?.not_beer) {
      showUntappdPanel(false);
      return;
    }
    if (!state.beer) showUntappdPanel(true);
    if (els.untappdQuery) els.untappdQuery.focus();
  }

  async function linkUntappdBeer(bid, beerName, brewery) {
    if (state.linking) return;
    state.linking = true;
    setScanStatus("Récupération fiche Untappd…", true);
    const barcode = currentBarcode();
    const hasEan = barcode.length >= 8;
    const endpoint = hasEan ? "/api/products/link" : "/api/untappd/fetch";
    try {
      const body = { untappd_bid: bid, beer_name: beerName, brewery };
      if (hasEan) body.barcode = barcode;
      const data = await fetchJson(
        endpoint,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        },
        60000
      );
      if (!data.ok) {
        toast(data.error || "Récupération impossible");
        return;
      }
      if (hasEan) data.barcode = barcode;
      applyBeerResult(data);
      showUntappdPanel(false);
      const eanMsg = hasEan ? `EAN ${barcode} — ` : "";
      setScanStatus(`${eanMsg}${data.beer_name} (Untappd)`, false);
      notifyLookupResult(data);
      if (!data.previous_checkin) {
        toast(hasEan ? "Fiche mémorisée pour cet EAN ✓" : "Fiche Untappd chargée ✓");
      }
    } catch (e) {
      toast(e.message || "Erreur réseau");
      setScanStatus("", false);
    } finally {
      state.linking = false;
    }
  }

  function renderUntappdResults(results) {
    if (!els.untappdResults) return;
    els.untappdResults.innerHTML = "";
    els.untappdResults.classList.remove("hidden");
    results.forEach((r) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "untappd-hit";
      const styleBit = r.style_fr ? ` · ${r.style_fr}` : "";
      const purl = r.photo_url || r.label_url || "";
      const img = purl ? `<img src="${esc(purl)}" class="untappd-thumb" alt="" loading="lazy" />` : "";
      btn.innerHTML = `
        ${img}
        <div class="untappd-hit-content">
          <h3>${esc(r.beer_name)}</h3>
          <div class="meta">${esc(r.brewery)}${esc(styleBit)}</div>
        </div>
      `;
      btn.addEventListener("click", () => linkUntappdBeer(r.bid, r.beer_name, r.brewery));
      els.untappdResults.appendChild(btn);
    });
  }

  async function searchUntappd() {
    const brewery = (els.untappdBrewery?.value || "").trim();
    const name = (els.untappdName?.value || "").trim();
    const q = [brewery, name].filter(Boolean).join(" ").trim();

    if (q.length < 2) {
      toast("Indique au moins un nom ou une brasserie");
      return;
    }
    if (els.btnUntappdSearch) {
      els.btnUntappdSearch.disabled = true;
      els.btnUntappdSearch.textContent = "Recherche…";
    }
    if (els.untappdResults) {
      els.untappdResults.classList.remove("hidden");
      els.untappdResults.innerHTML = "<p class='meta'>Recherche Untappd…</p>";
    }
    try {
      const data = await fetchJson(
        `/api/untappd/search?q=${encodeURIComponent(q)}&limit=5`,
        {},
        60000
      );
      if (!data.ok || !data.results?.length) {
        state.lastUntappdResults = null;
        if (els.untappdResults) {
          els.untappdResults.innerHTML = `<p class="meta">${esc(data.error || "Aucun résultat")}</p>`;
        }
        return;
      }
      state.lastUntappdResults = data.results;
      renderUntappdResults(data.results);
    } catch (e) {
      if (els.untappdResults) {
        els.untappdResults.innerHTML = `<p class="meta">${esc(e.message)}</p>`;
      }
    } finally {
      if (els.btnUntappdSearch) {
        els.btnUntappdSearch.disabled = false;
        els.btnUntappdSearch.textContent = "Chercher sur Untappd";
      }
    }
  }

  async function saveLocalProduct() {
    const barcode = currentBarcode();
    const name = (els.localName?.value || "").trim();
    const brewery = (els.localBrewery?.value || "").trim();
    let style = els.localStyle?.value || "Unknown";
    if (style === "Autre") {
      const custom = (els.customStyleInput?.value || "").trim();
      style = custom || "Inconnu";
    }
    if (name.length < 2) {
      toast("Indique le nom de la bière");
      return;
    }
    if (els.btnLocalSave) {
      els.btnLocalSave.disabled = true;
      els.btnLocalSave.textContent = "Enregistrement…";
    }
    try {
      const payload = { beer_name: name, brewery: brewery || "—", style };
      if (barcode.length >= 8) payload.barcode = barcode;
      const data = await fetchJson("/api/products/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!data.ok) {
        toast(data.error || "Enregistrement impossible");
        return;
      }
      if (barcode.length >= 8) data.barcode = barcode;
      applyBeerResult(data);
      showUntappdPanel(false);
      notifyLookupResult(data);
      if (!data.previous_checkin) toast("Bière enregistrée ✓");
    } catch (e) {
      toast(e.message || "Erreur réseau");
    } finally {
      if (els.btnLocalSave) {
        els.btnLocalSave.disabled = false;
        els.btnLocalSave.textContent = "Continuer";
      }
    }
  }

  function applyBeerResult(data) {
    if (!data || !data.ok) {
      toast(data?.error || "Bière introuvable");
      return false;
    }
    state.beer = data;
    stopScanCamera();
    state.flavors.clear();
    state.hops.clear();
    if (Array.isArray(data.hops)) {
      data.hops.forEach((h) => { if (h) state.hops.add(h); });
    }
    if (els.barcodeInput && data.barcode) {
      els.barcodeInput.value = data.barcode;
    }
    if (els.eanManual && data.barcode) {
      els.eanManual.value = data.barcode;
    }
    renderBeerPreview(data);
    updateRatingPanel();
    if (state.step === 3) {
      renderNotationStep().catch(() => {});
    }
    updateStepButtons();
    return true;
  }

  function normalizeEan(raw) {
    const d = String(raw || "").replace(/\D/g, "");
    if (d.length === 13) return d;
    if (d.length === 12) return `0${d}`;
    if (d.length >= 8) return d;
    return "";
  }

  function loadImageFromFile(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        URL.revokeObjectURL(url);
        resolve(img);
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error("Image illisible"));
      };
      img.src = url;
    });
  }

  function canvasToBlob(canvas, quality = 0.93) {
    return new Promise((resolve) => {
      canvas.toBlob((b) => resolve(b), "image/jpeg", quality);
    });
  }

  async function compressForScanUpload(blobOrFile) {
    const file =
      blobOrFile instanceof File
        ? blobOrFile
        : new File([blobOrFile], "scan.jpg", { type: "image/jpeg", lastModified: Date.now() });
    return compressImageForUpload(file, { maxDim: 1050, quality: 0.76 });
  }

  async function serverDecodeBarcode(blobOrFile, statusPrefix) {
    const compressed = await compressForScanUpload(blobOrFile);
    const fd = new FormData();
    fd.append("image", compressed, compressed.name || "scan.jpg");
    return fetchJsonWithRetry(
      "/api/decode-barcode",
      { method: "POST", body: fd },
      {
        timeoutMs: 90000,
        retries: 2,
        retryDelayMs: 2000,
        onRetry: (n, max) => {
          setScanStatus(
            `${statusPrefix || "Envoi photo"} — tentative ${n + 1}/${max + 2} (réseau lent OK)…`,
            true,
          );
        },
      },
    );
  }

  async function compressImageForUpload(file, { maxDim = 1200, quality = 0.82 } = {}) {
    if (!file || !file.type || !file.type.startsWith("image/")) return file;
    // skip if already small
    if (file.size && file.size < 1200000) {
      try {
        const img = await loadImageFromFile(file);
        const nw = img.naturalWidth || img.width;
        if (Math.max(nw, img.naturalHeight || img.height) <= maxDim * 1.1) return file;
      } catch (e) { /* fallback compress */ }
    }
    try {
      const img = await loadImageFromFile(file);
      const nw = img.naturalWidth || img.width;
      const nh = img.naturalHeight || img.height;
      const scale = Math.min(1, maxDim / Math.max(nw, nh, 1));
      if (scale >= 0.99 && (!file.size || file.size < 900 * 1024)) return file;
      const outW = Math.max(1, Math.round(nw * scale));
      const outH = Math.max(1, Math.round(nh * scale));
      const canvas = document.createElement("canvas");
      canvas.width = outW;
      canvas.height = outH;
      const ctx = canvas.getContext("2d");
      if (!ctx) return file;
      ctx.drawImage(img, 0, 0, outW, outH);
      const blob = await canvasToBlob(canvas, quality);
      const name = (file.name || "photo").replace(/\.[^.]+$/, "") + ".jpg";
      return new File([blob], name, { type: "image/jpeg", lastModified: Date.now() });
    } catch (e) {
      return file; // fallback raw
    }
  }

  async function buildScanVariants(file) {
    const img = await loadImageFromFile(file);
    const nw = img.naturalWidth || img.width;
    const nh = img.naturalHeight || img.height;
    const maxSide = 1800;
    const fit = Math.min(1, maxSide / Math.max(nw, nh, 1));

    async function renderCanvas(outW, outH, filter, draw) {
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, outW);
      canvas.height = Math.max(1, outH);
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      if (!ctx) return null;
      ctx.filter = filter;
      draw(ctx, canvas.width, canvas.height);
      return canvasToBlob(canvas, 0.88);
    }

    const jobs = [
      {
        filter: "grayscale(1) contrast(2.4) brightness(1.05)",
        up: 2.0,
        crop: null,
      },
      {
        filter: "contrast(1.35) brightness(1.04)",
        up: 1.5,
        crop: null,
      },
      {
        filter: "grayscale(1) contrast(2.8)",
        up: 2.4,
        crop: 0.62,
      },
    ];

    const blobs = await Promise.all(
      jobs.map(async (job) => {
        let sx = 0;
        let sy = 0;
        let sw = nw;
        let sh = nh;
        if (job.crop) {
          sw = nw * job.crop;
          sh = nh * job.crop;
          sx = (nw - sw) / 2;
          sy = (nh - sh) / 2;
        }
        const ow = Math.round(sw * fit * job.up);
        const oh = Math.round(sh * fit * job.up);
        return renderCanvas(ow, oh, job.filter, (ctx, w, h) => {
          ctx.drawImage(img, sx, sy, sw, sh, 0, 0, w, h);
        });
      }),
    );

    return blobs.filter(Boolean).length ? blobs.filter(Boolean) : [file];
  }

  async function detectBarcodeFromBlob(blob) {
    if (typeof BarcodeDetector === "undefined") return "";
    try {
      const detector = new BarcodeDetector({
        formats: ["ean_13", "ean_8", "upc_a", "upc_e"],
      });
      const bitmap = await createImageBitmap(blob);
      const codes = await detector.detect(bitmap);
      if (bitmap.close) bitmap.close();
      for (const c of codes) {
        const ean = normalizeEan(c.rawValue);
        if (ean.length >= 8) return ean;
      }
    } catch (_) {
      /* BarcodeDetector indisponible ou refusé */
    }
    return "";
  }

  async function decodeBarcodeLocal(file) {
    const variants = await buildScanVariants(file);
    const hits = await Promise.all(variants.map((blob) => detectBarcodeFromBlob(blob)));
    for (let i = 0; i < hits.length; i += 1) {
      if (hits[i]) return { ean: hits[i], blob: variants[i] };
    }
    return { ean: "", blob: variants[0] || file };
  }

  async function lookupBarcode(code, opts = {}) {
    const barcode = (code || "").replace(/\D/g, "");
    if (barcode.length < 8) {
      toast("Code-barres trop court");
      return;
    }
    if (els.btnLookup) {
      els.btnLookup.disabled = true;
      els.btnLookup.textContent = "Recherche…";
    }
    setScanStatus("Recherche de la bière…", true);
    try {
      const data = await fetchJsonWithRetry(
        "/api/lookup",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ barcode }),
        },
        {
          timeoutMs: 30000,
          retries: 3,
          retryDelayMs: 1500,
          onRetry: (n, max) => {
            setScanStatus(`Recherche — tentative ${n + 1}/${max + 2}…`, true);
          },
        },
      );
      if (!data.ok) {
        if (data.degraded) toast(data.error || "Open Food Facts indisponible", 4000);
        else toast(data.error || "Bière introuvable");
        onLookupMiss(data);
        if (opts.keepScanStatus) {
          setScanStatus(`EAN ${barcode} — pas dans le catalogue local, Untappd ci-dessous`, false);
        }
        if (opts.resumeCameraOnMiss) resumeScanDetect();
      } else {
        applyBeerResult(data);
        showUntappdPanel(false);
        notifyLookupResult(data);
        if (opts.keepScanStatus) {
          const src =
            data.source === "historique"
              ? " (historique)"
              : data.source === "untappd_web" || data.source === "untappd"
                ? " (Untappd)"
                : "";
          setScanStatus(`EAN ${barcode} — bière identifiée${src}`, false);
        }
      }
    } catch (e) {
      const msg = e.message || "Erreur réseau";
      toast(msg);
      if (msg.includes("Délai")) {
        setScanStatus("Connexion lente — réessaie ou saisis l'EAN manuellement", false);
      }
      if (opts.resumeCameraOnMiss) resumeScanDetect();
    } finally {
      if (els.btnLookup) {
        els.btnLookup.disabled = false;
        els.btnLookup.textContent = "Identifier par EAN";
      }
      if (!opts.keepScanStatus) setScanStatus("", false);
      if (!state.beer && !opts.resumeCameraOnMiss) maybeResumeScanCamera();
    }
  }

  async function scanBarcodePhoto(file, opts = {}) {
    const keepCamera = !!opts.keepCamera;
    if (!file || state.scanning) return;
    if (keepCamera) pauseScanDetect();
    else stopScanCamera();
    state.scanning = true;
    setScanStatus("Lecture du code-barres…", true);

    if (els.scanPreview) {
      els.scanPreview.src = URL.createObjectURL(file);
      els.scanPreview.classList.remove("hidden");
      if (els.scanViewfinder) els.scanViewfinder.classList.add("has-preview");
    }

    try {
      const local = await decodeBarcodeLocal(file);
      if (local.ean) {
        setScanStatus(`EAN ${local.ean} détecté — recherche…`, true);
        await lookupBarcode(local.ean);
        return;
      }

      setScanStatus("Envoi photo (réseau lent OK)…", true);
      const decoded = await serverDecodeBarcode(local.blob || file, "Envoi photo");
      if (!decoded.ok || !decoded.barcode) {
        toast(decoded.error || "Code-barres illisible");
        setScanStatus("Recadre le code EAN et réessaie", false);
        clearScanPreview();
        return;
      }
      if (els.eanManual) els.eanManual.value = decoded.barcode;
      setScanStatus(`EAN ${decoded.barcode} — recherche…`, true);
      await lookupBarcode(decoded.barcode, { keepScanStatus: true });
      return;
    } catch (e) {
      const msg = e.message || "Erreur réseau";
      toast(msg);
      if (msg.includes("Délai")) {
        setScanStatus("Trop long — saisie EAN manuelle ci-dessous", false);
      } else {
        setScanStatus("", false);
      }
    } finally {
      state.scanning = false;
      if (!state.beer) {
        if (keepCamera) resumeScanDetect();
        else maybeResumeScanCamera();
      }
      applyScanModeUI();
    }
  }

  function isNotationModes(data) {
    return !!(data && data.notation_family);
  }

  function notationTagsTitle(family) {
    if (family === "hops") return "Houblons";
    if (family === "fruity") return "Saveurs";
    return "Goûts";
  }

  function mergeNotationFields(target, data) {
    if (!target || !data) return target;
    [
      "notation_family",
      "show_hops_block",
      "show_flavors_block",
      "hops_presets",
      "suggested_hops",
      "flavors",
      "suggested_flavors",
      "style_fr",
    ].forEach((k) => {
      if (data[k] !== undefined) target[k] = data[k];
    });
    return target;
  }

  function notationShowBlocks(data) {
    if (isNotationModes(data)) {
      let showFlavors = data.show_flavors_block;
      let showHops = data.show_hops_block;
      if (showFlavors === undefined) {
        showFlavors = data.notation_family !== "hops";
      }
      if (showHops === undefined) {
        showHops = data.notation_family === "hops";
      }
      return { showFlavors: !!showFlavors, showHops: !!showHops };
    }
    return { showFlavors: true, showHops: true };
  }

  function applyNotationBlockVisibility(root, data) {
    if (!root) return;
    const { showFlavors, showHops } = notationShowBlocks(data || {});
    root.querySelectorAll(".tags-block").forEach((el) => {
      el.classList.toggle("hidden", !showFlavors);
    });
    root.querySelectorAll(".hops-block").forEach((el) => {
      el.classList.toggle("hidden", !showHops);
    });
  }

  function updateWizardTagsTitle(family, beer) {
    if (!els.tagsTitleLabel) return;
    els.tagsTitleLabel.textContent = notationTagsTitle(family || "classic");
    if (els.styleLabel && family !== "hops") {
      const style = beer?.style || "Unknown";
      els.styleLabel.textContent = `(${styleLabel(beer || { style })})`;
    }
  }

  function updateEditTagsTitle(family) {
    if (!els.editTagsTitle) return;
    els.editTagsTitle.textContent = notationTagsTitle(family || "classic");
  }

  function resetNotationBlocksVisible() {
    const legacy = { show_flavors_block: true, show_hops_block: true };
    applyNotationBlockVisibility(els.wizardPanel3, legacy);
    applyNotationBlockVisibility(els.editDialog, legacy);
    if (els.tagsTitleLabel) els.tagsTitleLabel.textContent = "Goûts";
    if (els.editTagsTitle) els.editTagsTitle.textContent = "Goûts";
  }

  async function fetchNotationForBeer(beer) {
    const style = beer?.style || "Unknown";
    const desc = beer?.description || beer?.summary || "";
    try {
      return await fetchJson(
        `/api/flavors?style=${encodeURIComponent(style)}&description=${encodeURIComponent(desc)}`
      );
    } catch (e) {
      return null;
    }
  }

  async function renderNotationStep() {
    const beer = state.beer;
    const panel = els.wizardPanel3;

    if (!beer) {
      applyNotationBlockVisibility(panel, {});
      return;
    }

    if (!isNotationModes(beer)) {
      const d = await fetchNotationForBeer(beer);
      if (d) mergeNotationFields(beer, d);
    }

    const family = beer.notation_family || "classic";
    applyNotationBlockVisibility(panel, beer);
    updateWizardTagsTitle(family, beer);

    const { showFlavors, showHops } = notationShowBlocks(beer);

    if (showHops && state.hops.size === 0 && Array.isArray(beer.suggested_hops)) {
      beer.suggested_hops.forEach((h) => {
        if (h) state.hops.add(h);
      });
    }

    const tasks = [];
    if (showFlavors) tasks.push(renderFlavorTags());
    if (showHops) tasks.push(renderHopTags());
    await Promise.all(tasks);
  }

  async function renderEditNotationStep(checkin) {
    const style = checkin?.style || "Unknown";
    let notationData = null;
    try {
      notationData = await fetchJson(`/api/flavors?style=${encodeURIComponent(style)}`);
    } catch (e) {
      notationData = null;
    }

    const data = notationData || {};
    applyNotationBlockVisibility(els.editDialog, isNotationModes(data) ? data : {});
    updateEditTagsTitle(isNotationModes(data) ? data.notation_family : "classic");

    const { showFlavors, showHops } = notationShowBlocks(isNotationModes(data) ? data : {});

    const tasks = [];
    if (showFlavors) tasks.push(renderEditFlavorTags(checkin, data));
    if (showHops) tasks.push(renderEditHopTags(checkin, data));
    await Promise.all(tasks);
  }

  async function renderFlavorTags() {
    if (!els.flavorTags) return;
    const beer = state.beer;
    const style = beer?.style || "Unknown";
    const desc = beer?.description || beer?.summary || "";
    let tags = [];
    let suggested = new Set(beer?.suggested_flavors || []);
    try {
      const d = await fetchJson(
        `/api/flavors?style=${encodeURIComponent(style)}&description=${encodeURIComponent(desc)}`
      );
      tags = d.flavors || [];
      if (!suggested.size) {
        suggested = new Set(d.suggested_flavors || []);
      }
      if (beer && d.style_fr) beer.style_fr = d.style_fr;
    } catch (e) {
      tags = [];
    }
    els.styleLabel.textContent = `(${styleLabel(beer || { style })})`;
    state.presetFlavorTags = tags;
    els.flavorTags.innerHTML = "";
    const preselect = state.flavors.size === 0;
    tags.forEach((tag) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tag";
      b.textContent = tag;
      const active = state.flavors.has(tag) || flavorInSet(state.flavors, tag);
      if (active) {
        b.classList.add("on");
        if (!state.flavors.has(tag)) {
          const existing = flavorInSet(state.flavors, tag);
          if (existing) state.flavors.delete(existing);
          state.flavors.add(tag);
        }
      }
      b.addEventListener("click", () => {
        if (b.classList.contains("on")) {
          b.classList.remove("on");
          state.flavors.delete(tag);
          const alt = flavorInSet(state.flavors, tag);
          if (alt) state.flavors.delete(alt);
        } else if (state.flavors.size >= MAX_FLAVORS) {
          toast("8 goûts maximum");
          return;
        } else {
          b.classList.add("on");
          state.flavors.add(tag);
        }
        renderCustomFlavorChips({
          container: els.customFlavorTags,
          flavorSet: state.flavors,
          presetTags: state.presetFlavorTags,
          onRemove: removeWizardCustomFlavor,
        });
      });
      if (preselect && suggested.has(tag) && !active) {
        b.classList.add("on");
        state.flavors.add(tag);
      }
      els.flavorTags.appendChild(b);
    });
    renderCustomFlavorChips({
      container: els.customFlavorTags,
      flavorSet: state.flavors,
      presetTags: state.presetFlavorTags,
      onRemove: removeWizardCustomFlavor,
    });
  }

  function removeWizardCustomFlavor(tag) {
    state.flavors.delete(tag);
    syncPresetButtons(els.flavorTags, state.flavors, state.presetFlavorTags);
    renderCustomFlavorChips({
      container: els.customFlavorTags,
      flavorSet: state.flavors,
      presetTags: state.presetFlavorTags,
      onRemove: removeWizardCustomFlavor,
    });
  }

  function addWizardCustomFlavor() {
    const raw = els.customFlavorInput?.value || "";
    if (
      addFlavorToSet(state.flavors, state.presetFlavorTags, raw, els.flavorTags)
    ) {
      if (els.customFlavorInput) els.customFlavorInput.value = "";
      renderCustomFlavorChips({
        container: els.customFlavorTags,
        flavorSet: state.flavors,
        presetTags: state.presetFlavorTags,
        onRemove: removeWizardCustomFlavor,
      });
    }
  }

  async function renderHopTags() {
    if (!els.hopTags) return;
    let tags = [];
    const presets = state.beer?.hops_presets;
    if (Array.isArray(presets) && presets.length > 0) {
      tags = presets;
    } else {
      try {
        tags = await fetchJson("/api/hops");
      } catch (e) {
        tags = [];
      }
    }
    state.presetHops = tags;
    els.hopTags.innerHTML = "";
    const preselect = state.hops.size === 0;
    const suggested = new Set(
      preselect && Array.isArray(state.beer?.suggested_hops) ? state.beer.suggested_hops : []
    );
    tags.forEach((tag) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tag";
      b.textContent = tag;
      const active = state.hops.has(tag) || flavorInSet(state.hops, tag);
      if (active) {
        b.classList.add("on");
        if (!state.hops.has(tag)) {
          const existing = flavorInSet(state.hops, tag);
          if (existing) state.hops.delete(existing);
          state.hops.add(tag);
        }
      }
      b.addEventListener("click", () => {
        if (b.classList.contains("on")) {
          b.classList.remove("on");
          state.hops.delete(tag);
          const alt = flavorInSet(state.hops, tag);
          if (alt) state.hops.delete(alt);
        } else if (state.hops.size >= MAX_HOPS) {
          toast("6 houblons maximum");
          return;
        } else {
          b.classList.add("on");
          state.hops.add(tag);
        }
        renderCustomFlavorChips({
          container: els.customHopTags,
          flavorSet: state.hops,
          presetTags: state.presetHops,
          onRemove: removeWizardCustomHop,
        });
      });
      if (preselect && suggested.has(tag) && !active) {
        b.classList.add("on");
        state.hops.add(tag);
      }
      els.hopTags.appendChild(b);
    });
    renderCustomFlavorChips({
      container: els.customHopTags,
      flavorSet: state.hops,
      presetTags: state.presetHops,
      onRemove: removeWizardCustomHop,
    });
  }

  function removeWizardCustomHop(tag) {
    state.hops.delete(tag);
    syncPresetButtons(els.hopTags, state.hops, state.presetHops);
    renderCustomFlavorChips({
      container: els.customHopTags,
      flavorSet: state.hops,
      presetTags: state.presetHops,
      onRemove: removeWizardCustomHop,
    });
  }

  async function addWizardCustomHop() {
    const raw = els.customHopInput?.value || "";
    const name = normalizeFlavorInput(raw);
    if (name.length < 2) {
      toast("2 caractères minimum");
      return;
    }
    // register new hop via POST so it becomes preset for future
    const lower = name.toLowerCase();
    const alreadyPreset = (state.presetHops || []).some((t) => t.toLowerCase() === lower);
    if (!alreadyPreset) {
      try {
        await fetchJson("/api/hops", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name }),
        });
        const fresh = await fetchJson("/api/hops");
        state.presetHops = fresh || state.presetHops;
      } catch (e) {
        // still allow adding locally (offline / error)
      }
    }
    if (addFlavorToSet(state.hops, state.presetHops, raw, els.hopTags)) {
      // reuse flavor adder logic (size check done inside)
      if (state.hops.size > MAX_HOPS) {
        // trim if over (defensive)
        const arr = [...state.hops]; while (arr.length > MAX_HOPS) { const last=arr.pop(); state.hops.delete(last); }
      }
      if (els.customHopInput) els.customHopInput.value = "";
      renderCustomFlavorChips({
        container: els.customHopTags,
        flavorSet: state.hops,
        presetTags: state.presetHops,
        onRemove: removeWizardCustomHop,
      });
    }
  }

  function updateStars() {
    // Main picker is now custom slider. This keeps compatibility for calls.
    // Edit dialog still uses its own stars.
    const r = (state.rating >= 0.25 ? state.rating : 3);
    if (window.__updateSliderVisual) {
      window.__updateSliderVisual(r);
    } else if (els.noteValue) {
      els.noteValue.textContent = formatRatingLabel(r);
    }
    updateRatingPanel();
  }

  function setRating(n) {
    state.rating = normalizeRating(n);
    updateStars();
    updateRatingPanel();
  }

  async function postCheckin(forceDuplicate = false) {
    // prepare serializable data (photo File kept for IDB if needed)
    const photo = state.photoFile || null;
    const payload = {
      barcode: state.beer.barcode || "",
      beer_name: state.beer.beer_name,
      brewery: state.beer.brewery || "",
      style: state.beer.style || "Unknown",
      abv: state.beer.abv != null ? String(state.beer.abv) : "",
      summary: state.beer.summary || "",
      rating: String(state.rating),
      flavors: [...state.flavors],
      hops: [...state.hops],
      comment: els.comment.value.trim(),
      untappd_bid: state.beer.untappd_bid ? String(state.beer.untappd_bid) : undefined,
      force: forceDuplicate ? true : undefined,
      photo: photo
    };

    if (!navigator.onLine) {
      await enqueueCreateCheckin(payload);
      toast("enregistré localement, sera synchronisé");
      return { queued: true };
    }

    const fd = new FormData();
    fd.append("barcode", payload.barcode);
    fd.append("beer_name", payload.beer_name);
    fd.append("brewery", payload.brewery);
    fd.append("style", payload.style);
    fd.append("abv", payload.abv);
    fd.append("summary", payload.summary);
    fd.append("rating", payload.rating);
    fd.append("flavors", JSON.stringify(payload.flavors));
    fd.append("hops", JSON.stringify(payload.hops));
    fd.append("comment", payload.comment);
    if (payload.untappd_bid) {
      fd.append("untappd_bid", payload.untappd_bid);
    }
    if (payload.force) fd.append("force", "true");
    if (payload.photo) fd.append("photo", payload.photo);

    try {
      const r = await fetchApi("/api/checkins", { method: "POST", body: fd });
      if (r.status === 401) {
        clearBeerSession();
        window.location.replace(window.BEER_MOBILE ? "./login.html" : api("/"));
        throw new Error("Session expirée");
      }
      if (r.status === 409) {
        const err = await r.json().catch(() => ({}));
        const pc = err.previous_checkin;
        haptic([8, 45, 8]);
        const ok = await confirmDuplicateCheckin(pc, state.beer.beer_name);
        if (!ok) return false;
        return postCheckin(true);
      }
      if (!r.ok) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.detail || err.error || "Échec enregistrement");
      }
      return true;
    } catch (e) {
      if (isNetworkError(e)) {
        await enqueueCreateCheckin(payload);
        toast("enregistré localement, sera synchronisé");
        return { queued: true };
      }
      throw e;
    }
  }

  async function saveCheckin() {
    if (!state.beer) {
      toast("Choisis une bière d'abord (étape 1)");
      return;
    }
    if (state.rating < 0.25) return;
    els.btnSave.disabled = true;
    els.btnSave.textContent = "Enregistrement…";

    try {
      const res = await postCheckin(false);
      if (!res) return;
      if (res && res.queued) {
        // already toasted locally; reset UI, list will update on sync
        resetWizard();
        setStep(1);
        return;
      }
      haptic([12, 50, 12]);
      toast("Bière enregistrée ✓");
      maybeShowPwaHint();
      resetWizard();
      setStep(1);
    } catch (e) {
      // même en cas d'erreur réseau inattendue, on tente la queue si c'est un write
      if (isNetworkError(e)) {
        const photo = state.photoFile || null;
        const payload = {
          barcode: state.beer.barcode || "",
          beer_name: state.beer.beer_name,
          brewery: state.beer.brewery || "",
          style: state.beer.style || "Unknown",
          abv: state.beer.abv != null ? String(state.beer.abv) : "",
          summary: state.beer.summary || "",
          rating: String(state.rating),
          flavors: [...state.flavors],
          hops: [...state.hops],
          comment: els.comment.value.trim(),
          untappd_bid: state.beer.untappd_bid ? String(state.beer.untappd_bid) : undefined,
          force: false,
          photo: photo
        };
        await enqueueCreateCheckin(payload);
        toast("enregistré localement, sera synchronisé");
        resetWizard();
        setStep(1);
        return;
      }
      toast(e.message || "Échec enregistrement");
    } finally {
      els.btnSave.disabled = state.rating < 0.25 || !state.beer;
      els.btnSave.textContent = "Enregistrer";
    }
  }

  function resetWizard() {
    state.beer = null;
    state.photoFile = null;
    state.rating = 0;
    state.flavors.clear();
    state.scanning = false;
    state.linking = false;
    state.lastUntappdResults = null;

    if (els.barcodeInput) els.barcodeInput.value = "";
    if (els.beerPreview) els.beerPreview.classList.add("hidden");
    if (els.btnToPhoto) els.btnToPhoto.classList.add("hidden");
    if (els.btnAddWishlist) els.btnAddWishlist.classList.add("hidden");

    if (els.scanInput) els.scanInput.value = "";
    clearScanPreview();
    stopScanCamera();
    if (!scanProfile.liveFailed) initScanMode();
    else applyScanModeUI();
    setScanStatus("", false);
    showUntappdPanel(true);
    if (els.untappdQuery) els.untappdQuery.value = "";
    if (els.untappdResults) {
      els.untappdResults.classList.add("hidden");
      els.untappdResults.innerHTML = "";
    }
    if (els.localName) els.localName.value = "";
    if (els.localBrewery) els.localBrewery.value = "";
    if (els.eanManual) els.eanManual.value = "";
    if (els.localStyle) els.localStyle.value = "";
    if (els.customStyleInput) els.customStyleInput.value = "";

    if (els.photoInput) els.photoInput.value = "";
    if (els.photoPreview) els.photoPreview.classList.add("hidden");
    if (els.photoPlaceholder) els.photoPlaceholder.classList.remove("hidden");

    if (els.comment) els.comment.value = "";
    if (els.commentCount) els.commentCount.textContent = "0";
    if (els.customFlavorInput) els.customFlavorInput.value = "";
    if (els.customFlavorTags) els.customFlavorTags.innerHTML = "";
    if (els.hopTags) els.hopTags.innerHTML = "";
    if (els.customHopInput) els.customHopInput.value = "";
    if (els.customHopTags) els.customHopTags.innerHTML = "";
    state.presetFlavorTags = [];
    state.presetHops = [];
    state.editPresetHops = [];
    state.hops.clear();
    state.editHops.clear();
    resetNotationBlocksVisible();
    updateStars();
    if (window.__updateSliderVisual) window.__updateSliderVisual(3);
    else if (els.noteValue) els.noteValue.textContent = "—";
    updateStepButtons();
  }

  function historyApiPath({ limit = null, offset = null, q = null } = {}) {
    const params = new URLSearchParams();
    const qval = q !== null ? (q || "").trim() : (els.historySearch?.value || "").trim();
    if (qval) params.set("q", qval);
    if (state.historyFilters.style) params.set("style", state.historyFilters.style);
    if (state.historyFilters.minRating > 0) {
      params.set("min_rating", String(state.historyFilters.minRating));
    }
    if (state.historyFilters.period) params.set("period", state.historyFilters.period);
    const l = limit !== null ? limit : state.historyLimit;
    const o = offset !== null ? offset : state.historyOffset;
    params.set("limit", String(l));
    if (o > 0) params.set("offset", String(o));
    const qs = params.toString();
    return `/api/checkins?${qs}`;
  }



  function formatRatingsMap(ratings, currentUser) {
    return Object.entries(ratings || {})
      .map(([u, r]) => {
        const mark = u === currentUser ? " (toi)" : "";
        return `${u}${mark} : ${formatRatingLabel(normalizeRating(r))}`;
      })
      .join(" · ");
  }



  async function loadHistoryStyleFilter() {
    if (!els.historyFilterStyle || els.historyFilterStyle.options.length > 1) return;
    try {
      const styles = await fetchJson("/api/styles");
      els.historyFilterStyle.innerHTML = styles
        .map((s) => `<option value="${esc(s.value)}">${esc(s.label)}</option>`)
        .join("");
    } catch (e) {
      els.historyFilterStyle.innerHTML = '<option value="">Tous styles</option>';
    }
  }

  async function loadLocalStyleOptions() {
    const sel = els.localStyle;
    if (!sel) return;
    try {
      const styles = await fetchJson("/api/styles");
      const prev = sel.value;
      sel.innerHTML = "";
      styles.forEach((s) => {
        if (!s.value) return; // skip "Tous styles"
        const o = document.createElement("option");
        o.value = s.value;
        o.textContent = s.label || s.value;
        sel.appendChild(o);
      });
      // Toujours ajouter "Autre" en dernier pour style libre (ne s'ajoute PAS à la liste prédéfinie)
      const autre = document.createElement("option");
      autre.value = "Autre";
      autre.textContent = "Autre (saisir manuellement)";
      sel.appendChild(autre);

      if (prev && sel.querySelector(`option[value="${prev}"]`)) {
        sel.value = prev;
      } else if (sel.options.length > 0) {
        const unk = Array.from(sel.options).find((o) => o.value === "Unknown");
        if (unk) sel.value = "Unknown";
      }
    } catch (e) {
      // fallback minimal sans Unknown/test
      if (!sel.options.length) {
        const autre = document.createElement("option");
        autre.value = "Autre";
        autre.textContent = "Autre (saisir manuellement)";
        sel.appendChild(autre);
      }
    }
    // toggle + listener
    updateCustomStyleVisibility();
    if (sel) {
      sel.removeEventListener("change", updateCustomStyleVisibility); // avoid dup
      sel.addEventListener("change", updateCustomStyleVisibility);
    }
  }

  function updateCustomStyleVisibility() {
    const sel = els.localStyle;
    const row = document.querySelector(".custom-flavor-row");
    if (!sel || !row) return;
    const show = sel.value === "Autre";
    row.style.display = show ? "flex" : "none";
    if (show && els.customStyleInput) {
      // clear or focus if needed
    }
  }

  function loadHistoryRatingFilter() {
    const select = els.historyFilterRating;
    if (!select || select.options.length > 3) return; // déjà rempli

    select.innerHTML = '';
    const optAll = document.createElement('option');
    optAll.value = '0';
    optAll.textContent = 'Toutes';
    select.appendChild(optAll);

    // Moins de choix : seulement les essentiels 0.25/0.5 + entiers, pas énorme
    const options = [0.25, 0.5, 1, 2, 3, 4, 5];
    options.forEach((val) => {
      const opt = document.createElement('option');
      opt.value = String(val);
      let label = val.toFixed(2).replace(/\.?0+$/, '') + ' ★+';
      opt.textContent = label;
      select.appendChild(opt);
    });
  }

  function renderHistoryStats(stats) {
    if (!els.historyStats) return;
    if (!stats?.total) {
      els.historyStats.classList.add("hidden");
      els.historyStats.innerHTML = "";
      return;
    }
    const avg = stats.avg_rating != null ? formatRatingLabel(stats.avg_rating) : "—";
    const topStyle = stats.top_styles?.[0]?.style || "—";
    const last = stats.last ? stats.last.beer_name : "—";
    els.historyStats.innerHTML = `
      <div class="stat-card"><strong>${stats.total}</strong><span>dégustations</span></div>
      <div class="stat-card"><strong>${esc(avg)}</strong><span>moyenne</span></div>
      <div class="stat-card"><strong>${esc(topStyle)}</strong><span>style favori</span></div>
      <div class="stat-card"><strong style="font-size:0.78rem;line-height:1.2">${esc(last)}</strong><span>dernière</span></div>
    `;
    els.historyStats.classList.remove("hidden");
  }

  function renderHistoryList(items) {
    if (!items.length) {
      els.historyList.innerHTML = "<p class='meta'>Aucun résultat.</p>";
      return;
    }
    els.historyList.innerHTML = items
      .map((it) => {
        const r = normalizeRating(it.rating || 0);
        const stars = renderStarVisual(r);
        const ratingLabel = formatRatingLabel(r);
        const thumbInner = it.photo_url
          ? `<img src="${esc(it.photo_url)}" alt="" />`
          : `<span class="history-card__photo-empty" aria-hidden="true">📷</span>`;
        const tags = (it.flavors || []).join(", ");
        const hops = (it.hops || []).join(", ");
        const dt = formatDate(it.created_at);
        const privateBadge = state.isAdmin && it.hidden_from_partner
          ? '<span class="checkin-private-badge" title="Masquée pour les autres">Privée</span>'
          : "";
        return `<article class="history-card history-item" data-id="${it.id}">
          <div class="history-card__top" data-action="detail" data-id="${it.id}">
            <button type="button" class="history-card__photo-btn" data-action="detail" data-id="${it.id}" aria-label="Voir ${esc(it.beer_name)}">${thumbInner}</button>
            <div class="history-card__info history-item-body" data-action="detail" data-id="${it.id}">
              <div class="history-card__head">
                <h3 title="${esc(it.beer_name)}">${esc(it.beer_name)}${privateBadge}</h3>
                <div class="history-card__rate">
                  <span class="stars-sm">${stars}</span>
                  <span class="history-card__rate-val">${esc(ratingLabel)}</span>
                </div>
              </div>
              <div class="history-card__line">${esc(it.brewery)} · ${esc(it.style || "Inconnu")} · ${dt}</div>
              ${tags ? `<div class="history-card__line">${esc(tags)}</div>` : ""}
              ${hops ? `<div class="history-card__line">Houblons : ${esc(hops)}</div>` : ""}
              ${it.comment ? `<div class="history-card__comment">« ${esc(it.comment)} »</div>` : ""}
            </div>
          </div>
          <div class="history-card__actions history-item-actions">
            <button type="button" class="btn primary" data-action="retaste" data-id="${it.id}">Noter à nouveau</button>
            <button type="button" class="btn" data-action="quick" data-id="${it.id}">Rapide</button>
            <button type="button" class="btn" data-action="edit" data-id="${it.id}">Modifier</button>
            <button type="button" class="btn" data-action="delete" data-id="${it.id}">Supprimer</button>
          </div>
        </article>`;
      })
      .join("");

    // Use onclick delegation to avoid multiple listeners on re-render
    els.historyList.onclick = function(ev) {
      var target = ev.target;
      var el = target && target.closest ? target.closest('[data-action]') : null;
      if (!el) return;
      var action = el.dataset.action;
      if (action === 'detail') {
        if (target && target.closest && target.closest("button[data-action='edit'], button[data-action='delete'], button[data-action='retaste']")) return;
        var id = Number(el.dataset.id || (el.closest('[data-id]') || {}).dataset.id);
        var item = state.historyItems.find(function(it) { return it.id === id; });
        if (item) openCheckinDetail(item);
        return;
      }
      if (el.tagName === 'BUTTON') handleHistoryAction(el);
    };

    // Gérer le bouton "Charger +" après chaque render
    updateLoadMoreButton();

    // Setup / refresh light IO infinite scroll (in addition to load more button)
    setupHistoryInfiniteScroll();
  }

  function openCheckinDetail(checkin) {
    state.detailCheckin = checkin;
    if (!els.checkinDetail) return;

    if (els.detailName) els.detailName.textContent = checkin.beer_name || "—";
    if (els.detailMeta) {
      els.detailMeta.textContent = `${checkin.brewery || "—"} · ${checkin.style || "Inconnu"} · ${formatDate(checkin.created_at)}`;
    }
    if (els.detailStars) {
      const r = normalizeRating(checkin.rating || 0);
      els.detailStars.innerHTML = renderStarVisual(r) + `  ${formatRatingLabel(r)}`;
    }
    if (els.detailFlavors) {
      const tags = (checkin.flavors || []).join(", ");
      const hops = (checkin.hops || []).join(", ");
      let txt = "";
      if (tags) txt += `Goûts : ${tags}`;
      if (hops) txt += (txt ? " · " : "") + `Houblons : ${hops}`;
      if (txt) {
        els.detailFlavors.textContent = txt;
        els.detailFlavors.classList.remove("hidden");
      } else {
        els.detailFlavors.classList.add("hidden");
      }
    }
    if (els.detailComment) {
      if (checkin.comment) {
        els.detailComment.textContent = `« ${checkin.comment} »`;
        els.detailComment.classList.remove("hidden");
      } else {
        els.detailComment.classList.add("hidden");
      }
    }

    const hasPhoto = !!checkin.photo_url;
    if (els.detailPhoto) {
      if (hasPhoto) {
        els.detailPhoto.src = checkin.photo_url;
        els.detailPhoto.classList.remove("hidden");
      } else {
        els.detailPhoto.removeAttribute("src");
        els.detailPhoto.classList.add("hidden");
      }
    }
    if (els.detailNoPhoto) {
      els.detailNoPhoto.classList.toggle("hidden", hasPhoto);
    }

    if (els.btnDetailHide) {
      if (state.isAdmin) {
        const hidden = !!checkin.hidden_from_partner;
        els.btnDetailHide.classList.remove("hidden");
        els.btnDetailHide.textContent = hidden ? "Rendre visible" : "Masquer";
        els.btnDetailHide.setAttribute(
          "aria-label",
          hidden ? "Rendre cette dégustation visible pour les autres" : "Masquer cette dégustation pour les autres"
        );
      } else {
        els.btnDetailHide.classList.add("hidden");
      }
    }

    els.checkinDetail.classList.remove("hidden");
  }

  async function toggleCheckinHidden(checkin) {
    if (!state.isAdmin || !checkin?.id) return;
    const next = !checkin.hidden_from_partner;
    try {
      const res = await fetchJson(`/api/checkins/${checkin.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ hidden_from_partner: next }),
      });
      const updated = res?.checkin;
      if (!updated) return;
      const idx = state.historyItems.findIndex((it) => it.id === checkin.id);
      if (idx >= 0) state.historyItems[idx] = updated;
      state.detailCheckin = updated;
      openCheckinDetail(updated);
      toast(next ? "Masquée pour les autres" : "Visible pour les autres");
    } catch (e) {
      toast(e.message || "Échec");
    }
  }

  function closeCheckinDetail() {
    state.detailCheckin = null;
    els.checkinDetail?.classList.add("hidden");
    if (els.detailPhoto) els.detailPhoto.removeAttribute("src");
  }

  function openPhotoGallery() {
    if (!els.photoGallery) return;
    els.history?.classList.add("hidden");
    els.photoGallery.classList.remove("hidden");

    // Réutilise chargeurs + populate des filtres de l'historique (réutilisation stricte logique)
    loadHistoryStyleFilter().then(() => {
      if (els.galleryFilterStyle && els.historyFilterStyle) {
        els.galleryFilterStyle.innerHTML = els.historyFilterStyle.innerHTML;
      }
      // Sync après populate (pour que value prenne)
      if (els.galleryFilterStyle) els.galleryFilterStyle.value = state.historyFilters.style || "";
    }).catch(() => {
      if (els.galleryFilterStyle) els.galleryFilterStyle.value = state.historyFilters.style || "";
    });
    loadHistoryRatingFilter();
    if (els.galleryFilterRating && els.historyFilterRating) {
      els.galleryFilterRating.innerHTML = els.historyFilterRating.innerHTML;
    }

    // Sync rating + period (rating filter populé synchrone)
    if (els.galleryFilterRating) els.galleryFilterRating.value = String(state.historyFilters.minRating || 0);
    if (els.galleryFilterPeriod) els.galleryFilterPeriod.value = state.historyFilters.period || "";

    clearTimeout(state.gallerySearchTimer);
    // Reset search galerie à l'ouverture (indépendant de l'historique)
    if (els.gallerySearch) els.gallerySearch.value = "";

    const galleryScroller = els.photoGallery.querySelector(".photo-gallery-body");
    if (galleryScroller) galleryScroller.scrollTop = 0;

    loadGallery();
  }

  function closePhotoGallery() {
    if (els.photoGallery) els.photoGallery.classList.add("hidden");
    clearTimeout(state.gallerySearchTimer);
  }

  function startNewTastingFromCheckin(checkin) {
    if (!checkin) return;

    closeCheckinDetail();
    els.history?.classList.add("hidden");

    state.photoFile = null;
    state.rating = 0;
    state.flavors.clear();
    state.hops.clear();
    state.scanning = false;
    state.linking = false;
    state.lastUntappdResults = null;

    state.beer = {
      ok: true,
      barcode: checkin.barcode || "",
      beer_name: checkin.beer_name || "",
      brewery: checkin.brewery || "",
      style: checkin.style || "Unknown",
      abv: checkin.abv != null ? checkin.abv : null,
      summary: checkin.summary || "",
      untappd_bid: checkin.untappd_bid || null,
      source: checkin.untappd_bid ? "untappd" : "history",
    };

    state.hops = new Set(checkin.hops || []);
    if (els.barcodeInput) els.barcodeInput.value = state.beer.barcode || "";
    if (els.eanManual) els.eanManual.value = state.beer.barcode || "";
    if (els.localStyle && checkin.style) els.localStyle.value = checkin.style;
    if (els.eanManual) els.eanManual.value = state.beer.barcode || "";
    if (els.photoInput) els.photoInput.value = "";
    if (els.photoPreview) {
      els.photoPreview.classList.add("hidden");
      els.photoPreview.removeAttribute("src");
    }
    if (els.photoPlaceholder) els.photoPlaceholder.classList.remove("hidden");
    if (els.comment) els.comment.value = "";
    if (els.commentCount) els.commentCount.textContent = "0";
    if (els.customFlavorInput) els.customFlavorInput.value = "";
    if (els.customFlavorTags) els.customFlavorTags.innerHTML = "";
    if (els.hopTags) els.hopTags.innerHTML = "";
    if (els.customHopInput) els.customHopInput.value = "";
    if (els.customHopTags) els.customHopTags.innerHTML = "";
    if (els.editHopTags) els.editHopTags.innerHTML = "";
    if (els.editCustomHopTags) els.editCustomHopTags.innerHTML = "";
    if (els.customStyleInput) els.customStyleInput.value = "";
    if (els.localStyle) els.localStyle.value = "";
    state.presetFlavorTags = [];
    state.presetHops = [];
    state.editPresetHops = [];

    renderBeerPreview(state.beer);
    showUntappdPanel(false);
    setScanStatus("", false);
    updateStars();
    setStep(2);
    haptic(10);
    toast({
      variant: "info",
      label: "Nouvelle dégustation",
      message: checkin.beer_name || "Bière chargée",
      durationMs: 3200,
    });
  }

  function resetEditPhotoState(checkin) {
    state.editPhotoFile = null;
    state.editRemovePhoto = false;
    if (els.editPhotoInput) els.editPhotoInput.value = "";
    const showPhoto = checkin?.photo_url && !state.editRemovePhoto;
    if (els.editPhotoPreview) {
      if (showPhoto) {
        els.editPhotoPreview.src = checkin.photo_url;
        els.editPhotoPreview.classList.remove("hidden");
        if (els.editPhotoPlaceholder) els.editPhotoPlaceholder.classList.add("hidden");
      } else {
        els.editPhotoPreview.classList.add("hidden");
        els.editPhotoPreview.removeAttribute("src");
        if (els.editPhotoPlaceholder) els.editPhotoPlaceholder.classList.remove("hidden");
      }
    }
    if (els.btnEditRemovePhoto) {
      els.btnEditRemovePhoto.classList.toggle("hidden", !checkin?.photo_url);
    }
  }

  async function loadHistoryStats() {
    try {
      const stats = await fetchJson("/api/stats");
      renderHistoryStats(stats);
    } catch (e) {
      if (els.historyStats) els.historyStats.classList.add("hidden");
    }
  }

  async function loadHistory(append = false) {
    if (append && (state.isLoadingHistory || !state.historyHasMore)) return;

    state.isLoadingHistory = true;

    if (!append) {
      // Cleanup observer/sentinel before full reload (innerHTML will clear anyway but be explicit)
      if (state.historyObserver) {
        state.historyObserver.disconnect();
        state.historyObserver = null;
      }
      const sent = document.getElementById("history-sentinel");
      if (sent && sent.parentNode) sent.parentNode.removeChild(sent);
      state.historyOffset = 0;
      els.historyList.innerHTML = "<p class='meta'>Chargement…</p>";
    }

    const path = historyApiPath({ limit: state.historyLimit, offset: state.historyOffset });
    const hasFilters =
      (els.historySearch?.value || "").trim() ||
      state.historyFilters.style ||
      state.historyFilters.minRating > 0 ||
      state.historyFilters.period;

    try {
      const newItems = await fetchJson(path);

      if (!append) {
        if (els.historyStats) {
          els.historyStats.classList.remove("hidden");
          await loadHistoryStats();
        }
        state.historyItems = newItems;
      } else {
        state.historyItems = state.historyItems.concat(newItems);
      }

      state.historyHasMore = newItems.length === state.historyLimit;
      state.historyOffset += newItems.length;

      if (!state.historyItems.length) {
        els.historyList.innerHTML = hasFilters
          ? "<p class='meta'>Aucun résultat avec ces filtres.</p>"
          : "<p class='meta'>Aucune bière encore.</p>";
      } else {
        renderHistoryList(state.historyItems);
        updateLoadMoreButton();
      }
    } catch (e) {
      if (!append) {
        els.historyList.innerHTML = "<p class='meta'>Erreur chargement</p>";
      }
    }
    state.isLoadingHistory = false;
  }

  function updateLoadMoreButton() {
    let btn = $("btn-history-loadmore");
    if (!els.history) return;

    if (!state.historyHasMore || !state.historyItems.length) {
      if (btn) btn.remove();
      return;
    }

    if (!btn) {
      btn = document.createElement("button");
      btn.id = "btn-history-loadmore";
      btn.className = "btn ghost block";
      btn.textContent = "Charger 10 de plus";
      btn.onclick = () => loadHistory(true);
      // Insert after the list
      const list = els.historyList;
      if (list && list.parentNode) list.parentNode.insertBefore(btn, list.nextSibling);
    }
  }

  function setupHistoryInfiniteScroll() {
    // Light infinite scroll via IntersectionObserver. Uses server pagination (limit/offset).
    // Re-setup after every render (filters reset full list; append keeps growing).
    // Root = the .history scroller (fixed full-screen overlay).
    const container = els.history?.querySelector(".history-panel-body") || els.history;
    const list = els.historyList;
    if (!list || !container) return;

    // Cleanup previous observer
    if (state.historyObserver) {
      state.historyObserver.disconnect();
      state.historyObserver = null;
    }

    // Remove stray sentinel if any
    let sentinel = document.getElementById("history-sentinel");
    if (sentinel && sentinel.parentNode !== list) {
      sentinel.parentNode.removeChild(sentinel);
      sentinel = null;
    }
    if (!sentinel) {
      sentinel = document.createElement("div");
      sentinel.id = "history-sentinel";
      // zero-height but with top margin to trigger a bit earlier; invisible
      sentinel.style.cssText = "height:1px;width:100%;margin:0;padding:0;";
    }
    // Ensure sentinel is always last child of list (re-render via innerHTML removes previous)
    if (sentinel.parentNode) sentinel.parentNode.removeChild(sentinel);
    list.appendChild(sentinel);

    try {
      state.historyObserver = new IntersectionObserver(
        (entries) => {
          const entry = entries[0];
          if (entry && entry.isIntersecting && state.historyHasMore && !state.isLoadingHistory) {
            loadHistory(true);
          }
        },
        {
          root: container,
          rootMargin: "120px 0px", // trigger a bit before actual bottom for smooth UX
          threshold: 0.01,
        }
      );
      state.historyObserver.observe(sentinel);
    } catch (e) {
      // IntersectionObserver not available (very old browser): fall back to load more button only
    }
  }

  async function loadGallery() {
    if (!els.galleryGrid) return;
    els.galleryGrid.innerHTML = "<p class='meta'>Chargement…</p>";

    // Réutilise exactement historyApiPath (filtres + logique) + q dédié à la galerie.
    // Pagination légère client (max ~150 items) pour couvrir plus de photos sans UI dédiée.
    const gq = els.gallerySearch ? (els.gallerySearch.value || "").trim() : "";
    let collected = [];
    let off = 0;
    const MAX_PAGES = 3;
    try {
      for (let p = 0; p < MAX_PAGES; p++) {
        const path = historyApiPath({ limit: 50, offset: off, q: gq });
        const page = await fetchJson(path);
        if (!page || !page.length) break;
        collected = collected.concat(page);
        off += page.length;
        if (page.length < 50) break;
      }
      const withPhotos = collected.filter((it) => it && it.photo_url);
      state.galleryItems = withPhotos;
      renderGalleryGrid(withPhotos);
    } catch (e) {
      els.galleryGrid.innerHTML = `<p class="meta">${esc(e.message || "Erreur chargement")}</p>`;
    }
  }

  function renderGalleryGrid(items) {
    if (!els.galleryGrid) return;
    if (!items || !items.length) {
      els.galleryGrid.innerHTML = "<p class='meta'>Aucune photo avec ces filtres.</p>";
      return;
    }
    els.galleryGrid.innerHTML = items
      .map((it) => {
        const r = normalizeRating(it.rating || 0);
        const stars = renderStarVisual(r);
        const dateShort = formatDateShort(it.created_at);
        return `<button type="button" class="gallery-item" data-id="${it.id}" title="${esc(it.beer_name)}">
          <img src="${esc(it.photo_url)}" alt="${esc(it.beer_name)}" loading="lazy" />
          <div class="gallery-item-overlay">
            <div class="gallery-item-name">${esc(it.beer_name)}</div>
            <div class="gallery-item-date">${esc(dateShort)}</div>
            <div class="gallery-item-stars">${stars}</div>
          </div>
        </button>`;
      })
      .join("");

    // Délégation click (propre, comme historique)
    els.galleryGrid.onclick = function (ev) {
      const el = ev.target && ev.target.closest ? ev.target.closest(".gallery-item") : null;
      if (!el) return;
      const id = Number(el.dataset.id);
      const item = state.galleryItems.find((it) => it.id === id);
      if (item) {
        els.photoGallery?.classList.add("hidden");
        if (confirm("Ouvrir le détail ou dégustation rapide avec cette photo ? (Annuler = détail)")) {
          applyBeerResult({
            ok: true,
            beer_name: item.beer_name,
            brewery: item.brewery,
            style: item.style,
            summary: item.summary || "",
            abv: item.abv,
            untappd_bid: item.untappd_bid,
            barcode: item.barcode || "",
            source: "gallery-quick"
          });
          if (els.photoPreview) {
            els.photoPreview.src = item.photo_url;
            els.photoPreview.classList.remove("hidden");
            if (els.photoPlaceholder) els.photoPlaceholder.classList.add("hidden");
          }
          setStep(3);
          return;
        }
        openCheckinDetail(item);
      }
    };
  }

  async function handleHistoryAction(btn) {
    const id = Number(btn.dataset.id);
    const action = btn.dataset.action;
    if (!id || !action) return;
    const item = state.historyItems.find((it) => it.id === id);
    if (!item) return;

    if (action === "edit") {
      openEditDialog(item);
      return;
    }

    if (action === "retaste") {
      startNewTastingFromCheckin(item);
      return;
    }
    if (action === "quick") {
      els.history?.classList.add("hidden");
      applyBeerResult({
        ok: true,
        beer_name: item.beer_name,
        brewery: item.brewery || "—",
        style: item.style || "Unknown",
        summary: item.summary || "",
        abv: item.abv,
        untappd_bid: item.untappd_bid,
        barcode: item.barcode || "",
        source: "history-quick"
      });
      setStep(3);
      toast("Dégustation rapide — note directement");
      return;
    }

    if (action === "delete") {
      if (!confirm(`Supprimer « ${item.beer_name} » ?`)) return;
      try {
        const res = await fetchJson(`/api/checkins/${id}`, { method: "DELETE" });
        if (res && res.queued) {
          toast("enregistré localement, sera synchronisé");
          return { queued: true };
        }
        toast("Dégustation supprimée");
        loadHistory();
      } catch (e) {
        toast(e.message || "Suppression impossible");
      }
    }
  }

  // edit now uses the exact same slider as main - no more stars for edit rating


  async function renderEditFlavorTags(checkin, notationData) {
    if (!els.editFlavorTags) return;
    const style = checkin.style || "Unknown";
    let tags = [];
    let d = notationData;
    if (!d) {
      try {
        d = await fetchJson(`/api/flavors?style=${encodeURIComponent(style)}`);
      } catch (e) {
        d = null;
      }
    }
    tags = (d && d.flavors) || [];
    state.editPresetFlavorTags = tags;
    state.editFlavors = new Set(checkin.flavors || []);
    els.editFlavorTags.innerHTML = "";
    tags.forEach((tag) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tag";
      b.textContent = tag;
      if (state.editFlavors.has(tag) || flavorInSet(state.editFlavors, tag)) {
        b.classList.add("on");
      }
      b.addEventListener("click", () => {
        if (b.classList.contains("on")) {
          b.classList.remove("on");
          state.editFlavors.delete(tag);
          const alt = flavorInSet(state.editFlavors, tag);
          if (alt) state.editFlavors.delete(alt);
        } else if (state.editFlavors.size >= MAX_FLAVORS) {
          toast("8 goûts maximum");
          return;
        } else {
          b.classList.add("on");
          state.editFlavors.add(tag);
        }
        renderCustomFlavorChips({
          container: els.editCustomFlavorTags,
          flavorSet: state.editFlavors,
          presetTags: state.editPresetFlavorTags,
          onRemove: removeEditCustomFlavor,
        });
      });
      els.editFlavorTags.appendChild(b);
    });
    renderCustomFlavorChips({
      container: els.editCustomFlavorTags,
      flavorSet: state.editFlavors,
      presetTags: state.editPresetFlavorTags,
      onRemove: removeEditCustomFlavor,
    });
  }

  function removeEditCustomFlavor(tag) {
    state.editFlavors.delete(tag);
    syncPresetButtons(els.editFlavorTags, state.editFlavors, state.editPresetFlavorTags);
    renderCustomFlavorChips({
      container: els.editCustomFlavorTags,
      flavorSet: state.editFlavors,
      presetTags: state.editPresetFlavorTags,
      onRemove: removeEditCustomFlavor,
    });
  }

  function addEditCustomFlavor() {
    const raw = els.editCustomFlavorInput?.value || "";
    if (
      addFlavorToSet(
        state.editFlavors,
        state.editPresetFlavorTags,
        raw,
        els.editFlavorTags
      )
    ) {
      if (els.editCustomFlavorInput) els.editCustomFlavorInput.value = "";
      renderCustomFlavorChips({
        container: els.editCustomFlavorTags,
        flavorSet: state.editFlavors,
        presetTags: state.editPresetFlavorTags,
        onRemove: removeEditCustomFlavor,
      });
    }
  }

  async function renderEditHopTags(checkin, notationData) {
    if (!els.editHopTags) return;
    let tags = [];
    const presets = notationData?.hops_presets;
    if (Array.isArray(presets) && presets.length > 0) {
      tags = presets;
    } else {
      try {
        tags = await fetchJson("/api/hops");
      } catch (e) {
        tags = [];
      }
    }
    state.editPresetHops = tags;
    state.editHops = new Set((checkin && checkin.hops) || []);
    els.editHopTags.innerHTML = "";
    tags.forEach((tag) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tag";
      b.textContent = tag;
      if (state.editHops.has(tag) || flavorInSet(state.editHops, tag)) {
        b.classList.add("on");
      }
      b.addEventListener("click", () => {
        if (b.classList.contains("on")) {
          b.classList.remove("on");
          state.editHops.delete(tag);
          const alt = flavorInSet(state.editHops, tag);
          if (alt) state.editHops.delete(alt);
        } else if (state.editHops.size >= MAX_HOPS) {
          toast("6 houblons maximum");
          return;
        } else {
          b.classList.add("on");
          state.editHops.add(tag);
        }
        renderCustomFlavorChips({
          container: els.editCustomHopTags,
          flavorSet: state.editHops,
          presetTags: state.editPresetHops,
          onRemove: removeEditCustomHop,
        });
      });
      els.editHopTags.appendChild(b);
    });
    renderCustomFlavorChips({
      container: els.editCustomHopTags,
      flavorSet: state.editHops,
      presetTags: state.editPresetHops,
      onRemove: removeEditCustomHop,
    });
  }

  function removeEditCustomHop(tag) {
    state.editHops.delete(tag);
    syncPresetButtons(els.editHopTags, state.editHops, state.editPresetHops);
    renderCustomFlavorChips({
      container: els.editCustomHopTags,
      flavorSet: state.editHops,
      presetTags: state.editPresetHops,
      onRemove: removeEditCustomHop,
    });
  }

  async function addEditCustomHop() {
    const raw = els.editCustomHopInput?.value || "";
    const name = normalizeFlavorInput(raw);
    if (name.length < 2) {
      toast("2 caractères minimum");
      return;
    }
    const lower = name.toLowerCase();
    const alreadyPreset = (state.editPresetHops || []).some((t) => t.toLowerCase() === lower);
    if (!alreadyPreset) {
      try {
        await fetchJson("/api/hops", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name }),
        });
        const fresh = await fetchJson("/api/hops");
        state.editPresetHops = fresh || state.editPresetHops;
      } catch (e) {
        /* continue local */
      }
    }
    if (
      addTagToSet(
        state.editHops,
        state.editPresetHops,
        raw,
        els.editHopTags,
        MAX_HOPS,
        "6 houblons maximum"
      )
    ) {
      if (els.editCustomHopInput) els.editCustomHopInput.value = "";
      renderCustomFlavorChips({
        container: els.editCustomHopTags,
        flavorSet: state.editHops,
        presetTags: state.editPresetHops,
        onRemove: removeEditCustomHop,
      });
    }
  }

  function openEditDialog(checkin) {
    closeCheckinDetail();
    sealOverlay();
    state.editCheckin = checkin;
    const initialEditRating = normalizeRating(checkin.rating || 3);
    state.editRating = initialEditRating;
    if (els.editTitle) els.editTitle.textContent = checkin.beer_name || "Modifier";
    if (els.editMeta) {
      els.editMeta.textContent = `${checkin.brewery || "—"} · ${checkin.style || "Inconnu"} · ${formatDate(checkin.created_at)}`;
    }
    if (els.editComment) els.editComment.value = checkin.comment || "";
    if (els.editHideField) {
      els.editHideField.classList.toggle("hidden", !state.isAdmin);
    }
    if (els.editHiddenPartner) {
      els.editHiddenPartner.checked = !!checkin.hidden_from_partner;
    }
    resetEditPhotoState(checkin);
    if (editSliderApi) {
      editSliderApi.updateVisual(initialEditRating);
    } else if (els.editNoteValue) {
      els.editNoteValue.textContent = formatRatingLabel(initialEditRating);
    }
    renderEditNotationStep(checkin).catch(() => {});
    els.editDialog?.showModal();
  }

  async function uploadCheckinPhoto(checkinId, file) {
    const fd = new FormData();
    fd.append("photo", file, file.name || "photo.jpg");
    const r = await fetchApi(`/api/checkins/${checkinId}/photo`, {
      method: "POST",
      body: fd,
    });
    if (r.status === 401) {
      clearBeerSession();
      window.location.replace(window.BEER_MOBILE ? "./login.html" : api("/"));
      throw new Error("Session expirée");
    }
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      throw new Error(data.detail || data.error || "Photo non enregistrée");
    }
    return data;
  }

  async function saveEditCheckin() {
    const checkin = state.editCheckin;
    if (!checkin || state.editRating < 0.25) {
      toast("Choisis une note");
      return;
    }
    if (els.btnEditSave) {
      els.btnEditSave.disabled = true;
      els.btnEditSave.textContent = "Enregistrement…";
    }
    try {
      const patchPayload = {
        rating: state.editRating,
        flavors: [...state.editFlavors],
        hops: [...state.editHops],
        comment: els.editComment?.value?.trim() || "",
      };
      if (state.isAdmin && els.editHiddenPartner) {
        patchPayload.hidden_from_partner = !!els.editHiddenPartner.checked;
      }
      const res = await fetchJson(`/api/checkins/${checkin.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(patchPayload),
      });
      if (res && res.queued) {
        toast("enregistré localement, sera synchronisé");
        els.editDialog?.close();
        return { queued: true };
      }
      // photo ops only reached if patch was not queued (i.e. was online)
      if (state.editPhotoFile) {
        await uploadCheckinPhoto(checkin.id, state.editPhotoFile);
      } else if (state.editRemovePhoto && checkin.photo_url) {
        await fetchJson(`/api/checkins/${checkin.id}/photo`, { method: "DELETE" });
      }
      haptic([10, 40, 10]);
      toast("Dégustation mise à jour ✓");
      els.editDialog?.close();
      loadHistory();
    } catch (e) {
      toast(e.message || "Échec");
    } finally {
      if (els.btnEditSave) {
        els.btnEditSave.disabled = false;
        els.btnEditSave.textContent = "Enregistrer";
      }
    }
  }

  async function addCurrentBeerToWishlist() {
    if (state.isInvite) return;
    const beer = state.beer;
    if (!beer?.beer_name) {
      toast("Choisis une bière d'abord");
      return;
    }
    try {
      const res = await fetchJson("/api/wishlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          beer_name: beer.beer_name,
          brewery: beer.brewery,
          style: beer.style,
          barcode: beer.barcode,
        }),
      });
      if (res && res.queued) {
        toast("enregistré localement, sera synchronisé");
        return { queued: true };
      }
      toast("Ajouté à « À boire » ✓");
    } catch (e) {
      toast(e.message || "Ajout impossible");
    }
  }

  async function loadWishlist() {
    if (state.isInvite) return;
    if (!els.wishlistList) return;
    els.wishlistList.innerHTML = "<p class='meta'>Chargement…</p>";
    try {
      const items = await fetchJson("/api/wishlist");
      state.wishlistItems = items || [];
      if (!state.wishlistItems.length) {
        els.wishlistList.innerHTML = "<p class='meta'>Liste vide — ajoute une bière à goûter.</p>";
        return;
      }
      els.wishlistList.innerHTML = state.wishlistItems.map((it) => {
        const dt = formatDate(it.created_at);
        return `
          <article class="wish-item">
            <h3>${esc(it.beer_name)}</h3>
            <div class="meta">${esc(it.brewery || "—")} · ${esc(it.style || "Inconnu")} · par ${esc(it.added_by)} · ${dt}</div>
            ${it.note ? `<div class="meta">${esc(it.note)}</div>` : ""}
            <div class="wish-item-actions">
              <button type="button" class="btn" data-action="taste" data-id="${it.id}">Goûter</button>
              <button type="button" class="btn" data-action="remove" data-id="${it.id}">Retirer</button>
            </div>
          </article>`;
      }).join("");

      // Delegation (comme history) pour éviter accumulation listeners
      els.wishlistList.onclick = function(ev) {
        var target = ev.target;
        var el = target && target.closest ? target.closest('button[data-action]') : null;
        if (!el) return;
        var id = Number(el.dataset.id);
        var item = state.wishlistItems.find(function(it) { return it.id === id; });
        if (item) handleWishlistAction(el, item);
      };
    } catch (e) {
      els.wishlistList.innerHTML = `<p class="meta">${esc(e.message)}</p>`;
    }
  }

  async function openGiftsPanel() {
    if (state.isInvite) return;
    if (!els.giftsPanel) return;
    // Close other panels so it acts as a separate "page"
    if (els.history) els.history.classList.add("hidden");
    if (els.coupleStats) els.coupleStats.classList.add("hidden");
    if (els.wishlistPanel) els.wishlistPanel.classList.add("hidden");
    sealOverlay();
    els.giftsPanel.classList.remove("hidden");
    await loadGiftsPanel();
  }

  let giftsFilterTimer = null;

  function renderGiftsCoupleStats(users, me) {
    if (!els.giftsCoupleStats) return;
    const list = users || [];
    const mine = list.find((u) => u.username === me);
    const other = list.find((u) => u.username && u.username !== me);
    if (!mine || !other) {
      els.giftsCoupleStats.innerHTML = "";
      return;
    }
    const fmt = (n) => `${n} dégustation${n > 1 ? "s" : ""}`;
    els.giftsCoupleStats.innerHTML = `
      <div class="gifts-couple-stats-grid">
        <div class="gifts-couple-stat"><strong>Toi</strong><span>${fmt(mine.total)}</span></div>
        <div class="gifts-couple-stat"><strong>${esc(other.username)}</strong><span>${fmt(other.total)}</span></div>
      </div>`;
  }

  async function loadGiftsPanel() {
    if (!els.giftsList) return;
    els.giftsList.innerHTML = "<p class='meta'>Chargement des idées cadeaux…</p>";
    try {
      const data = await fetchJson("/api/stats/couple");
      const me = state.currentUser;
      renderGiftsCoupleStats(data.users, me);
      state.giftsItems = (data.gift_ideas || []).filter(g => g.for === me);

      const partnerUser = (data.users || []).find((u) => u.username && u.username !== me);
      const partnerName = partnerUser?.username || "l'autre";
      const h2 = els.giftsPanel ? els.giftsPanel.querySelector("h2") : null;
      if (h2) h2.textContent = `Idées cadeaux — ${partnerName}`;

      if (!state.giftsItems.length) {
        els.giftsList.innerHTML = `<p class='meta'>Aucune bière de ${esc(partnerName)} que tu n'as pas encore goûtée.</p>`;
        return;
      }

      // Populate style filter if empty
      if (els.giftsFilterStyle && els.giftsFilterStyle.options.length <= 1) {
        const styles = [...new Set(state.giftsItems.map(g => g.style).filter(Boolean))];
        styles.forEach(s => {
          const opt = document.createElement('option');
          opt.value = s;
          opt.textContent = s;
          els.giftsFilterStyle.appendChild(opt);
        });
      }

      filterAndRenderGifts();
    } catch (e) {
      els.giftsList.innerHTML = `<p class="meta">${esc(e.message)}</p>`;
    }
  }

  function filterAndRenderGifts() {
    if (!els.giftsList || !state.giftsItems) return;
    const q = els.giftsSearch ? (els.giftsSearch.value || '').toLowerCase().trim() : '';
    const style = els.giftsFilterStyle ? els.giftsFilterStyle.value : '';
    const minR = els.giftsFilterRating ? parseFloat(els.giftsFilterRating.value) || 0 : 0;

    let filtered = state.giftsItems.filter(g => {
      if (minR > 0 && (g.rating || 0) < minR) return false;
      if (style && g.style !== style) return false;
      if (q) {
        const normQ = normalizeSearch(q);
        const hay = `${g.beer_name || ""} ${g.brewery || ""} ${g.style || ""} ${g.comment || ""}`;
        if (!normalizeSearch(hay).includes(normQ)) return false;
      }
      return true;
    });

    const shown = filtered;
    const ROOT = (window.BEER_ROOT || "").replace(/\/$/, "");

    els.giftsList.innerHTML = shown.map((g) => {
      const r = formatRatingLabel(g.rating || 0);
      const stars = renderStarVisual(g.rating || 0);
      const from = g.liked_by || "l'autre";
      const cmt = g.comment
        ? `<div class="gift-comment"><strong>Ce qu'elle en a dit :</strong> « ${esc(g.comment)} »</div>`
        : "";
      const photo = g.photo_path
        ? `<img src="${ROOT}/photos/${esc(g.photo_path)}" class="gift-photo" alt="Photo prise par ${esc(from)} pour ${esc(g.beer_name)}" loading="lazy" />`
        : `<div class="gift-photo-placeholder">📷 Pas de photo</div>`;
      const date = g.created_at
        ? `<div class="gift-date">Dégustée le ${formatDateShort(g.created_at)}</div>`
        : "";
      const heart = (g.rating || 0) >= 5 ? `<span class="heart-badge">❤️ 5/5</span>` : '';

      return `
        <article class="gift-card">
          <div class="gift-photo-wrap">
            ${photo}
          </div>
          <div class="gift-info">
            <div class="gift-head">
              <h3>${esc(g.beer_name)} ${heart}</h3>
              <div class="gift-rating-stars">
                ${stars}
                <span class="gift-rating-num">${r}</span>
              </div>
            </div>
            <div class="gift-meta">
              <strong>${esc(g.brewery || "—")}</strong> · ${esc(g.style || "Style inconnu")}
              ${date}
            </div>
            <div class="gift-why">
              <span class="gift-badge">Notée ${r} par ${esc(from)}</span>
            </div>
            ${cmt}
          </div>
        </article>`;
    }).join("");
  }

  // Plus de bouton "ajouter à boire" sur les idées cadeaux :
  // la page est uniquement pour trouver des idées de cadeaux à offrir à l'autre.

  async function handleWishlistAction(btn, item) {
    const action = btn.dataset.action;
    if (action === "taste") {
      els.wishlistPanel?.classList.add("hidden");
      applyBeerResult({
        ok: true,
        beer_name: item.beer_name,
        brewery: item.brewery || "—",
        style: item.style || "Unknown",
        summary: `${item.beer_name} — depuis la liste À boire.`,
        barcode: item.barcode || "",
        source: "wishlist",
      });
      showUntappdPanel(false);
      setStep(1);
      toast("Bière chargée — note-la quand tu l'as goûtée");
      return;
    }
    if (action === "remove") {
      try {
        const res = await fetchJson(`/api/wishlist/${item.id}`, { method: "DELETE" });
        if (res && res.queued) {
          toast("enregistré localement, sera synchronisé");
          return { queued: true };
        }
        toast("Retiré de la liste");
        loadWishlist();
      } catch (e) {
        toast(e.message || "Erreur");
      }
    }
  }

  async function addWishlistManual() {
    const name = (els.wishName?.value || "").trim();
    const brewery = (els.wishBrewery?.value || "").trim();
    if (name.length < 2) {
      toast("Indique le nom de la bière");
      return;
    }
    if (els.btnWishAdd) {
      els.btnWishAdd.disabled = true;
      els.btnWishAdd.textContent = "Ajout…";
    }
    try {
      const res = await fetchJson("/api/wishlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ beer_name: name, brewery: brewery || "—" }),
      });
      if (res && res.queued) {
        toast("enregistré localement, sera synchronisé");
        if (els.wishName) els.wishName.value = "";
        if (els.wishBrewery) els.wishBrewery.value = "";
        return { queued: true };
      }
      if (els.wishName) els.wishName.value = "";
      if (els.wishBrewery) els.wishBrewery.value = "";
      toast("Ajouté à « À boire » ✓");
      loadWishlist();
    } catch (e) {
      toast(e.message || "Ajout impossible");
    } finally {
      if (els.btnWishAdd) {
        els.btnWishAdd.disabled = false;
        els.btnWishAdd.textContent = "Ajouter";
      }
    }
  }

  function bindEvents() {
    if (els.btnDismissInviteHelp) {
      els.btnDismissInviteHelp.addEventListener("click", () => {
        localStorage.setItem("beer_invite_tip_dismissed", "1");
        els.inviteHelpBar?.classList.add("hidden");
      });
    }
    if (els.btnDismissPwaHint) {
      els.btnDismissPwaHint.addEventListener("click", () => {
        localStorage.setItem("beer_pwa_hint_dismissed", "1");
        els.pwaHintBar?.classList.add("hidden");
      });
    }

    if (els.scanInput) {
      els.scanInput.addEventListener("change", () => {
        const f = els.scanInput.files && els.scanInput.files[0];
        if (f) scanBarcodePhoto(f);
        els.scanInput.value = "";
      });
    }

    if (els.scanStage) {
      els.scanStage.addEventListener("click", () => {
        if (state.scanning) return;
        if (scanProfile.mode === "native") triggerNativeScan();
        else if (!state.scanCameraActive) startScanCamera();
      });
    }

    if (els.btnScanStart) {
      els.btnScanStart.addEventListener("click", (ev) => {
        ev.stopPropagation();
        if (!state.scanCameraActive) startScanCamera();
      });
    }

    if (els.btnScanCapture) {
      els.btnScanCapture.addEventListener("click", (ev) => {
        ev.stopPropagation();
        captureFromViewfinder();
      });
    }

    if (els.btnScanNative) {
      els.btnScanNative.addEventListener("click", () => triggerNativeScan());
    }

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") stopScanCamera();
      else maybeResumeScanCamera();
    });

    if (els.btnLookup) {
      els.btnLookup.addEventListener("click", () => lookupBarcode(currentBarcode()));
    }

    if (els.btnUntappdSearch) {
      els.btnUntappdSearch.addEventListener("click", () => searchUntappd());
    }

    // Enter sur le champ nom pour lancer la recherche
    if (els.untappdName) {
      els.untappdName.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          searchUntappd();
        }
      });
    }

    if (els.btnLocalSave) {
      els.btnLocalSave.addEventListener("click", () => saveLocalProduct());
    }

    if (els.btnToPhoto) {
      els.btnToPhoto.addEventListener("click", () => setStep(2));
    }

    if (els.btnBack1) {
      els.btnBack1.addEventListener("click", () => setStep(1));
    }

    if (els.btnBack2) {
      els.btnBack2.addEventListener("click", () => setStep(2));
    }

    if (els.btnToRating) {
      els.btnToRating.addEventListener("click", () => setStep(3));
    }

    els.steps.forEach((btn) => {
      btn.addEventListener("click", () => setStep(Number(btn.dataset.step)));
    });

    if (els.photoInput) {
      els.photoInput.addEventListener("change", async () => {
        const f = els.photoInput.files && els.photoInput.files[0];
        if (!f) return;
        state.photoFile = await compressImageForUpload(f);
        els.photoPreview.src = URL.createObjectURL(state.photoFile);
        els.photoPreview.classList.remove("hidden");
        els.photoPlaceholder.classList.add("hidden");
      });
    }

    function initUntappdSlider(cfg) {
      // cfg = { wrapper, track, fill, thumb, ticks, valueEl, onChange, initial }
      const wrapper = cfg.wrapper;
      const track = cfg.track;
      const fill = cfg.fill;
      const thumb = cfg.thumb;
      const ticksEl = cfg.ticks;
      const valueEl = cfg.valueEl;
      const onChange = cfg.onChange || (() => {});
      let isDragging = false;
      let lastVal = cfg.initial || 3;
      let rafId = null;
      let pendingX = null;

      function setVisualPosition(pct) {
        if (fill) fill.style.width = pct;
        if (thumb) thumb.style.left = pct;
      }

      function applySnappedValue(val) {
        if (val === lastVal) return;
        const step = Math.round(val * 4);
        const lastStep = Math.round(lastVal * 4);
        if (step !== lastStep) {
          navigator.vibrate && navigator.vibrate(10);
          if (thumb) {
            const orig = thumb.style.transform || 'translate(-50%, -50%)';
            thumb.style.transition = 'transform 40ms ease-out';
            thumb.style.transform = 'translate(-50%, -50%) scale(1.1)';
            setTimeout(() => {
              if (thumb) {
                thumb.style.transform = orig;
                thumb.style.transition = '';
              }
            }, 40);
          }
        }
        lastVal = val;
        if (valueEl) valueEl.textContent = formatRatingLabel(val);
        onChange(val);
      }

      function rafLoop() {
        if (pendingX !== null) {
          const rect = track.getBoundingClientRect();
          let p = (pendingX - rect.left) / rect.width;
          p = Math.max(0, Math.min(1, p));
          const raw = p * 5;
          const val = Math.max(0.25, Math.min(5, Math.round(raw * 4) / 4));
          const snapP = val / 5;
          setVisualPosition((snapP * 100) + '%');
          if (val !== lastVal) {
            applySnappedValue(val);
          }
          pendingX = null;
        }
        rafId = null;
      }

      function onMove(clientX) {
        pendingX = clientX;
        if (!rafId) {
          rafId = requestAnimationFrame(rafLoop);
        }
      }

      // ticks
      if (ticksEl) {
        ticksEl.innerHTML = '';
        for (let i = 0; i <= 20; i++) {
          const t = document.createElement('div');
          t.className = 'tick';
          t.style.left = (i * 5) + '%';
          if (i % 2 === 1) { t.style.height = '3px'; }
          ticksEl.appendChild(t);
        }
      }

      // initial
      const pInit = ((cfg.initial || 3) / 5) * 100 + '%';
      setVisualPosition(pInit);
      if (valueEl) valueEl.textContent = formatRatingLabel(cfg.initial || 3);
      lastVal = cfg.initial || 3;
      applySnappedValue(lastVal); // ensure onChange

      // mousedown
      wrapper.addEventListener('mousedown', (e) => {
        isDragging = true;
        const rect = track.getBoundingClientRect();
        let p = (e.clientX - rect.left) / rect.width;
        p = Math.max(0, Math.min(1, p));
        const raw = p * 5;
        const val = Math.max(0.25, Math.min(5, Math.round(raw * 4) / 4));
        const snapP = val / 5;
        setVisualPosition((snapP * 100) + '%');
        applySnappedValue(val);
      });

      window.addEventListener('mousemove', (e) => {
        if (isDragging) onMove(e.clientX);
      });

      window.addEventListener('mouseup', () => {
        if (isDragging) {
          isDragging = false;
          if (rafId) {
            cancelAnimationFrame(rafId);
            rafId = null;
          }
          const snapP = lastVal / 5;
          setVisualPosition((snapP * 100) + '%');
        }
      });

      wrapper.addEventListener('touchstart', (e) => {
        e.preventDefault();
        e.stopPropagation();
        isDragging = true;
        const rect = track.getBoundingClientRect();
        let p = (e.touches[0].clientX - rect.left) / rect.width;
        p = Math.max(0, Math.min(1, p));
        const raw = p * 5;
        const val = Math.max(0.25, Math.min(5, Math.round(raw * 4) / 4));
        const snapP = val / 5;
        setVisualPosition((snapP * 100) + '%');
        applySnappedValue(val);
      }, { passive: false });

      wrapper.addEventListener('touchmove', (e) => {
        if (isDragging) {
          e.preventDefault();
          e.stopPropagation();
          onMove(e.touches[0].clientX);
        }
      }, { passive: false });

      wrapper.addEventListener('touchend', (e) => {
        e.preventDefault();
        if (isDragging) {
          isDragging = false;
          if (rafId) {
            cancelAnimationFrame(rafId);
            rafId = null;
          }
          const snapP = lastVal / 5;
          setVisualPosition((snapP * 100) + '%');
        }
      }, { passive: false });

      // keyboard
      wrapper.setAttribute('tabindex', '0');
      wrapper.setAttribute('role', 'slider');
      wrapper.setAttribute('aria-valuemin', '0.25');
      wrapper.setAttribute('aria-valuemax', '5');
      wrapper.setAttribute('aria-valuestep', '0.25');
      wrapper.addEventListener('keydown', function(e) {
        if (isDragging) return;
        let delta = 0;
        const k = e.key;
        if (k === 'ArrowRight' || k === 'ArrowUp') delta = 0.25;
        else if (k === 'ArrowLeft' || k === 'ArrowDown') delta = -0.25;
        else if (k === 'Home') {
          e.preventDefault();
          setVisualPosition((0.25 / 5 * 100) + '%');
          applySnappedValue(0.25);
          return;
        } else if (k === 'End') {
          e.preventDefault();
          setVisualPosition((5 / 5 * 100) + '%');
          applySnappedValue(5);
          return;
        } else if (k === 'PageUp') delta = 1.0;
        else if (k === 'PageDown') delta = -1.0;
        else return;
        e.preventDefault();
        const cur = lastVal;
        let nv = Math.round((cur + delta) * 4) / 4;
        nv = Math.max(0.25, Math.min(5, nv));
        const sp = nv / 5;
        setVisualPosition((sp * 100) + '%');
        applySnappedValue(nv);
      });

      return {
        updateVisual: (r) => {
          lastVal = r;
          if (!isDragging) {
            const p = Math.max(0, Math.min(1, r / 5));
            setVisualPosition((p * 100) + '%');
            if (valueEl) valueEl.textContent = formatRatingLabel(r);
          }
        }
      };
    }

    // Custom slider EXACTLY like the Untappd photo: clean yellow bar + ticks + round thumb + vibration every 0.25
    if (els.sliderTrack && els.sliderFill && els.sliderThumb && els.sliderWrapper) {
      mainSliderApi = initUntappdSlider({
        wrapper: els.sliderWrapper,
        track: els.sliderTrack,
        fill: els.sliderFill,
        thumb: els.sliderThumb,
        ticks: els.sliderTicks,
        valueEl: els.noteValue,
        initial: 3,
        onChange: (val) => {
          state.rating = val;
          if (els.btnSave) els.btnSave.disabled = val < 0.25 || !state.beer;
        }
      });
      window.__updateSliderVisual = (r) => { if (mainSliderApi) mainSliderApi.updateVisual(r); };
    }

    // Edit slider - EXACT SAME as main wizard (slider, ticks, lock 0.25, yellow etc)
    editSliderApi = null;
    if (els.editRatingSliderWrapper && els.editSliderTrack && els.editSliderFill && els.editSliderThumb) {
      editSliderApi = initUntappdSlider({
        wrapper: els.editRatingSliderWrapper,
        track: els.editSliderTrack,
        fill: els.editSliderFill,
        thumb: els.editSliderThumb,
        ticks: els.editSliderTicks,
        valueEl: els.editNoteValue,
        initial: 3,
        onChange: (val) => {
          state.editRating = val;
        }
      });
    }

    if (els.comment) {
      els.comment.addEventListener("input", () => {
        els.commentCount.textContent = String(els.comment.value.length);
      });
    }

    if (els.btnSave) {
      els.btnSave.addEventListener("click", saveCheckin);
    }

    if (els.btnHistory) {
      els.btnHistory.addEventListener("click", () => {
        sealOverlay();
        els.history.classList.remove("hidden");
        loadHistoryStyleFilter().then(() => loadHistory());
        loadHistoryRatingFilter();
        if (els.historyFilterRating) {
          els.historyFilterRating.value = String(state.historyFilters.minRating || 0);
        }
        if (els.historyStats) {
          els.historyStats.classList.remove("hidden");
          loadHistoryStats();
        }
      });
    }

    if (els.btnCloseHistory) {
      els.btnCloseHistory.addEventListener("click", () => {
        els.history.classList.add("hidden");
        if (state.historyObserver) {
          state.historyObserver.disconnect();
          state.historyObserver = null;
        }
        // Sentinel will be cleaned on next open via setup (if needed)
        const sent = document.getElementById("history-sentinel");
        if (sent) sent.remove();
      });
    }

    if (els.historySearch) {
      els.historySearch.addEventListener("input", () => {
        clearTimeout(state.historySearchTimer);
        state.historySearchTimer = setTimeout(() => {
          state.historyOffset = 0;
          loadHistory();
        }, 280);
      });
    }



    const onFilterChange = () => {
      state.historyFilters.style = els.historyFilterStyle?.value || "";
      const ratingEl = els.historyFilterRating;
      state.historyFilters.minRating = ratingEl ? Number(ratingEl.value || 0) : 0;
      state.historyFilters.period = els.historyFilterPeriod?.value || "";
      state.historyOffset = 0; // reset pagination
      // Sync vers els galerie (réutilisation filtres)
      if (els.galleryFilterStyle) els.galleryFilterStyle.value = state.historyFilters.style;
      if (els.galleryFilterRating) els.galleryFilterRating.value = String(state.historyFilters.minRating);
      if (els.galleryFilterPeriod) els.galleryFilterPeriod.value = state.historyFilters.period;
      loadHistory();
    };
    if (els.historyFilterStyle) els.historyFilterStyle.addEventListener("change", onFilterChange);
    if (els.historyFilterRating) {
      els.historyFilterRating.addEventListener("change", onFilterChange);
    }
    if (els.historyFilterPeriod) els.historyFilterPeriod.addEventListener("change", onFilterChange);

    // Galerie : bouton dans historique + bindings filtres (réutilisent state.historyFilters)
    if (els.btnOpenGallery) {
      els.btnOpenGallery.addEventListener("click", () => openPhotoGallery());
    }
    if (els.btnCloseGallery) {
      els.btnCloseGallery.addEventListener("click", () => closePhotoGallery());
    }

    const onGalleryFilterChange = () => {
      state.historyFilters.style = els.galleryFilterStyle?.value || "";
      const rEl = els.galleryFilterRating;
      state.historyFilters.minRating = rEl ? Number(rEl.value || 0) : 0;
      state.historyFilters.period = els.galleryFilterPeriod?.value || "";
      // Sync vers els history pour cohérence (réutilisation state/filters)
      if (els.historyFilterStyle) els.historyFilterStyle.value = state.historyFilters.style;
      if (els.historyFilterRating) els.historyFilterRating.value = String(state.historyFilters.minRating);
      if (els.historyFilterPeriod) els.historyFilterPeriod.value = state.historyFilters.period;
      loadGallery();
    };
    if (els.galleryFilterStyle) els.galleryFilterStyle.addEventListener("change", onGalleryFilterChange);
    if (els.galleryFilterRating) els.galleryFilterRating.addEventListener("change", onGalleryFilterChange);
    if (els.galleryFilterPeriod) els.galleryFilterPeriod.addEventListener("change", onGalleryFilterChange);

    // Recherche dédiée galerie (debounce, n'affecte pas l'historique ni state.historyFilters.search)
    if (els.gallerySearch) {
      els.gallerySearch.addEventListener("input", () => {
        clearTimeout(state.gallerySearchTimer);
        state.gallerySearchTimer = setTimeout(() => {
          loadGallery();
        }, 280);
      });
    }

    if (els.btnWishlist) {
      els.btnWishlist.addEventListener("click", () => {
        sealOverlay();
        els.wishlistPanel?.classList.remove("hidden");
        loadWishlist();
      });
    }

    if (els.btnCloseWishlist) {
      els.btnCloseWishlist.addEventListener("click", () => els.wishlistPanel?.classList.add("hidden"));
    }

    if (els.btnGifts) {
      els.btnGifts.addEventListener("click", openGiftsPanel);
    }
    if (els.btnCloseGifts) {
      els.btnCloseGifts.addEventListener("click", () => els.giftsPanel?.classList.add("hidden"));
    }

    if (els.giftsSearch) {
      els.giftsSearch.addEventListener("input", () => {
        clearTimeout(giftsFilterTimer);
        giftsFilterTimer = setTimeout(filterAndRenderGifts, 200);
      });
    }
    if (els.giftsFilterStyle) {
      els.giftsFilterStyle.addEventListener("change", filterAndRenderGifts);
    }
    if (els.giftsFilterRating) {
      els.giftsFilterRating.addEventListener("change", filterAndRenderGifts);
    }

    if (els.globalSearch) {
      // Live filter if history already open (debounced like native history search)
      els.globalSearch.addEventListener("input", () => {
        const q = (els.globalSearch.value || '').trim();
        if (els.history && !els.history.classList.contains('hidden') && els.historySearch) {
          els.historySearch.value = q;  // on garde la casse telle que tapée (normalize côté serveur)
          clearTimeout(state.historySearchTimer);
          state.historySearchTimer = setTimeout(() => {
            state.historyOffset = 0;
            loadHistory();
          }, 200);
        }
      });

      // On Enter: always launch search in history (opens if needed)
      els.globalSearch.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          const q = (els.globalSearch.value || '').trim();
          if (!q) return;
          if (els.historySearch) els.historySearch.value = q;
          els.history?.classList.remove('hidden');
          state.historyOffset = 0;
          loadHistory();
          // optional: keep value or clear after
          // els.globalSearch.value = '';
        }
      });
    }

    if (els.btnWishAdd) {
      els.btnWishAdd.addEventListener("click", () => addWishlistManual());
    }

    if (els.btnAddWishlist) {
      els.btnAddWishlist.addEventListener("click", () => addCurrentBeerToWishlist());
    }

    if (els.btnAddCustomFlavor) {
      els.btnAddCustomFlavor.addEventListener("click", () => addWizardCustomFlavor());
    }

    if (els.customFlavorInput) {
      els.customFlavorInput.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          addWizardCustomFlavor();
        }
      });
    }

    if (els.btnAddCustomHop) {
      els.btnAddCustomHop.addEventListener("click", () => addWizardCustomHop());
    }
    if (els.customHopInput) {
      els.customHopInput.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          addWizardCustomHop();
        }
      });
    }

    // Le champ style custom apparaît uniquement quand "Autre" est sélectionné.
    // Il n'est PAS enregistré dans la liste prédéfinie des styles.

    if (els.btnEditAddCustomFlavor) {
      els.btnEditAddCustomFlavor.addEventListener("click", () => addEditCustomFlavor());
    }

    if (els.editCustomFlavorInput) {
      els.editCustomFlavorInput.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          addEditCustomFlavor();
        }
      });
    }

    if (els.btnEditAddCustomHop) {
      els.btnEditAddCustomHop.addEventListener("click", () => addEditCustomHop());
    }
    if (els.editCustomHopInput) {
      els.editCustomHopInput.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          addEditCustomHop();
        }
      });
    }

    // edit stars removed - using slider now


    if (els.btnEditCancel) {
      els.btnEditCancel.addEventListener("click", () => els.editDialog?.close());
    }

    if (els.btnEditSave) {
      els.btnEditSave.addEventListener("click", () => saveEditCheckin());
    }

    if (els.btnCloseDetail) {
      els.btnCloseDetail.addEventListener("click", () => closeCheckinDetail());
    }

    if (els.btnDetailEdit) {
      els.btnDetailEdit.addEventListener("click", () => {
        if (state.detailCheckin) openEditDialog(state.detailCheckin);
      });
    }

    if (els.btnDetailHide) {
      els.btnDetailHide.addEventListener("click", () => {
        if (state.detailCheckin) toggleCheckinHidden(state.detailCheckin);
      });
    }

    if (els.btnDetailRetaste) {
      els.btnDetailRetaste.addEventListener("click", () => {
        if (state.detailCheckin) startNewTastingFromCheckin(state.detailCheckin);
      });
    }

    window.__beerPtrRefresh = async (panelId) => {
      if (panelId === "history") {
        await loadHistoryStyleFilter();
        loadHistoryRatingFilter();
        if (els.historyFilterRating) {
          els.historyFilterRating.value = String(state.historyFilters.minRating || 0);
        }
        await loadHistory();
        const scroller = els.history?.querySelector(".history-panel-body");
        if (scroller) scroller.scrollTop = 0;
        return;
      }
      if (panelId === "photo-gallery") {
        await loadGallery();
        const scroller = els.photoGallery?.querySelector(".photo-gallery-body");
        if (scroller) scroller.scrollTop = 0;
        return;
      }
      if (panelId === "wishlist-panel") {
        await loadWishlist();
        return;
      }
      if (panelId === "gifts-panel") {
        await loadGiftsPanel();
        return;
      }
      if (panelId === "admin-panel") {
        await refreshAdminPanel();
      }
    };

    if (els.editPhotoInput) {
      els.editPhotoInput.addEventListener("change", async () => {
        const f = els.editPhotoInput.files && els.editPhotoInput.files[0];
        if (!f) return;
        state.editPhotoFile = await compressImageForUpload(f);
        state.editRemovePhoto = false;
        if (els.editPhotoPreview) {
          els.editPhotoPreview.src = URL.createObjectURL(state.editPhotoFile);
          els.editPhotoPreview.classList.remove("hidden");
        }
        if (els.editPhotoPlaceholder) els.editPhotoPlaceholder.classList.add("hidden");
        if (els.btnEditRemovePhoto) els.btnEditRemovePhoto.classList.remove("hidden");
      });
    }

    if (els.btnEditRemovePhoto) {
      els.btnEditRemovePhoto.addEventListener("click", () => {
        state.editPhotoFile = null;
        state.editRemovePhoto = true;
        if (els.editPhotoInput) els.editPhotoInput.value = "";
        if (els.editPhotoPreview) {
          els.editPhotoPreview.classList.add("hidden");
          els.editPhotoPreview.removeAttribute("src");
        }
        if (els.editPhotoPlaceholder) {
          els.editPhotoPlaceholder.textContent = "📷 Prendre ou choisir une photo";
          els.editPhotoPlaceholder.classList.remove("hidden");
        }
      });
    }

    if (els.btnPatchnotes) {
      els.btnPatchnotes.addEventListener("click", () => {
        openPatchnotesPanel().catch(console.error);
      });
    }
    bindPatchnotesPanel();

    if (els.btnAdmin) {
      els.btnAdmin.addEventListener("click", () => {
        sealOverlay();
        els.adminPanel.classList.remove("hidden");
        if (els.cleanupResult) els.cleanupResult.textContent = "";
        loadAdminUsers();
        loadAdminInvites();
        if (els.adminStylesHops) loadAdminStylesHops();
      });
    }

    if (els.btnAdminRefresh) {
      els.btnAdminRefresh.addEventListener("click", async () => {
        els.btnAdminRefresh.disabled = true;
        try {
          await refreshAdminPanel();
          toast("Admin actualisé");
        } catch (e) {
          toast(e.message || "Erreur actualisation");
        } finally {
          els.btnAdminRefresh.disabled = false;
        }
      });
    }

    if (els.btnInviteCreate) {
      els.btnInviteCreate.addEventListener("click", createAdminInvite);
    }

    if (els.btnInviteCopy) {
      els.btnInviteCopy.addEventListener("click", copyInviteUrl);
    }

    if (els.btnInviteIpsAll) {
      els.btnInviteIpsAll.addEventListener("click", () => openInviteIpsDialog());
    }
    bindInviteIpsDialog();

    if (els.btnCloseAdmin) {
      els.btnCloseAdmin.addEventListener("click", () => els.adminPanel.classList.add("hidden"));
    }

    if (els.btnAdminCreate) {
      els.btnAdminCreate.addEventListener("click", createAdminUser);
    }

    if (els.btnCleanupPhotos) {
      els.btnCleanupPhotos.addEventListener("click", async () => {
        if (!confirm("Supprimer les photos orphelines (non associées à une dégustation) ?")) return;
        try {
          if (els.cleanupResult) els.cleanupResult.textContent = "Nettoyage en cours…";
          const res = await fetchJson("/api/admin/photos/cleanup", { method: "POST" });
          const n = res.removed || 0;
          if (els.cleanupResult) els.cleanupResult.textContent = n + " photo(s) orpheline(s) supprimée(s).";
          toast(n ? (n + " photo(s) nettoyée(s)") : "Aucune orpheline.");
        } catch (e) {
          if (els.cleanupResult) els.cleanupResult.textContent = "Erreur: " + (e.message || e);
        }
      });
    }

    // Toast scrim: empêche les taps sur l'arrière-plan quand un message (ex: "indique au moins une brasserie") est affiché.
    // Tap sur le scrim (ou le toast) = ferme le toast immédiatement.
    if (els.toastScrim) {
      els.toastScrim.addEventListener("click", hideToast);
    }
    if (els.toast) {
      els.toast.addEventListener("click", hideToast);
    }
  }

  async function refreshAdminPanel() {
    await Promise.all([
      loadAdminUsers(),
      loadAdminInvites(),
      els.adminStylesHops ? loadAdminStylesHops() : Promise.resolve(),
    ]);
  }

  let _inviteCreating = false;

  async function createAdminInvite() {
    if (_inviteCreating) return;
    const label = (els.inviteLabel?.value || "").trim();
    const validity = els.inviteDays?.value ?? "7d";
    if (!label || label.length < 2) {
      toast("Nom trop court (2 car. min.)");
      return;
    }
    _inviteCreating = true;
    if (els.btnInviteCreate) els.btnInviteCreate.disabled = true;
    toast({
      variant: "info",
      label: "Invitation",
      message: "Lien en cours de génération…",
      durationMs: 120000,
    });
    try {
      const res = await fetchJson("/api/invites", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ label, validity }),
      });
      if (!res.ok) throw new Error(res.error || "Erreur");
      if (els.inviteNewUrl) els.inviteNewUrl.value = res.url || "";
      if (els.inviteCreateResult) els.inviteCreateResult.classList.remove("hidden");
      hideToast();
      toast("Lien créé — copie-le maintenant");
      loadAdminInvites();
    } catch (e) {
      hideToast();
      toast(e.message || "Erreur création invitation");
    } finally {
      _inviteCreating = false;
      if (els.btnInviteCreate) els.btnInviteCreate.disabled = false;
    }
  }

  function clearInviteCreateResult() {
    if (els.inviteNewUrl) els.inviteNewUrl.value = "";
    if (els.inviteCreateResult) els.inviteCreateResult.classList.add("hidden");
    if (els.inviteLabel) els.inviteLabel.value = "";
  }

  async function copyInviteUrl() {
    const url = els.inviteNewUrl?.value || "";
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
    } catch (_e) {
      els.inviteNewUrl?.select();
      document.execCommand("copy");
    }
    clearInviteCreateResult();
    toast("Lien copié");
  }

  function inviteStatusLabel(inv) {
    if (inv.revoked_at) return "Révoquée";
    if (inv.reactivation_pending) return "Réactivation";
    if (!inv.active) return "Expirée";
    if (inv.redeemed_at) return "Utilisée";
    return "En attente";
  }

  async function loadAdminInvites() {
    if (!els.adminInviteList) return;
    els.adminInviteList.innerHTML = "<p class='meta'>Chargement…</p>";
    try {
      const invites = await fetchJson("/api/invites");
      state.adminInvites = invites || [];
      if (!invites?.length) {
        els.adminInviteList.innerHTML = "<p class='meta'>Aucune invitation.</p>";
        return;
      }
      els.adminInviteList.innerHTML = invites.map((inv) => {
        const status = inviteStatusLabel(inv);
        const rc = inv.redeem_client || {};
        const lc = inv.last_client || rc || {};
        const detailLines = [];
        if (inv.redeemed_at) {
          detailLines.push(`<li><strong>1er accès</strong> ${esc(formatDateShort(inv.redeemed_at))}${inv.redeem_ip ? ` · IP ${esc(inv.redeem_ip)}` : ""}</li>`);
          if (rc.browser && rc.browser !== "—") {
            detailLines.push(`<li><strong>Navigateur</strong> ${esc(rc.browser)} · ${esc(rc.os || "—")} · ${esc(rc.device || "—")}</li>`);
          }
          if (inv.device_short) {
            detailLines.push(`<li><strong>Appareil lié</strong> <code>${esc(inv.device_short)}</code></li>`);
          }
        }
        if (
          inv.last_used_at &&
          inv.last_used_at !== inv.redeemed_at &&
          lc.browser &&
          lc.browser !== "—" &&
          lc.browser !== rc.browser
        ) {
          detailLines.push(`<li><strong>Nav. récent</strong> ${esc(lc.browser)} · ${esc(lc.os || "—")}</li>`);
        }
        if (inv.reactivation_pending && inv.link_expires_at) {
          detailLines.push(`<li><strong>Lien réactivation</strong> expire ${esc(formatDateShort(inv.link_expires_at))} (10 min)</li>`);
        }
        if (inv.validity_label && inv.validity_label !== "—") {
          detailLines.push(`<li><strong>Type</strong> ${esc(inv.validity_label)}</li>`);
        }
        if (inv.permanent) {
          detailLines.push(`<li><strong>Validité compte</strong> permanente</li>`);
        } else if (inv.expires_at && !inv.reactivation_pending) {
          detailLines.push(`<li><strong>Validité compte</strong> jusqu'au ${esc(formatDateShort(inv.expires_at))}</li>`);
        }
        const details = detailLines.length
          ? `<ul class="invite-detail-lines">${detailLines.join("")}</ul>`
          : `<p class="admin-user-meta">En attente du 1er clic</p>`;
        const actions = [];
        if (!inv.revoked_at && inv.url && (!inv.redeemed_at || inv.reactivation_pending)) {
          actions.push(`<button type="button" class="btn" data-invite-copy="${inv.id}">Copier le lien</button>`);
        }
        if (!inv.revoked_at && inv.can_extend) {
          actions.push(`<button type="button" class="btn" data-invite-extend="${inv.id}" data-validity="24h">+24 h</button>`);
          actions.push(`<button type="button" class="btn" data-invite-extend="${inv.id}" data-validity="48h">+48 h</button>`);
          actions.push(`<button type="button" class="btn" data-invite-extend="${inv.id}" data-validity="7d">+7 j</button>`);
          actions.push(`<button type="button" class="btn" data-invite-extend="${inv.id}" data-validity="30d">+30 j</button>`);
          actions.push(`<button type="button" class="btn" data-invite-extend="${inv.id}" data-validity="permanent">Perm.</button>`);
        }
        if (!inv.revoked_at && inv.can_reissue) {
          actions.push(`<button type="button" class="btn" data-invite-reissue="${inv.id}">Renvoyer l'accès</button>`);
        }
        if (!inv.revoked_at && inv.reactivation_pending) {
          actions.push(`<button type="button" class="btn" data-invite-reissue="${inv.id}">Nouveau lien (10 min)</button>`);
        }
        if (!inv.revoked_at) {
          actions.push(`<button type="button" class="btn" data-invite-revoke="${inv.id}">Révoquer</button>`);
        }
        const checkins = Number(inv.checkins) || 0;
        return `
          <article class="admin-user-card">
            <div class="admin-user-top">
              <h3>${esc(inv.label)}</h3>
              <span class="admin-badge">${esc(status)}</span>
            </div>
            <div class="admin-user-meta">${esc(inv.username)} · ${checkins} dégustation(s)</div>
            ${inviteActivityLine(inv)}
            ${details}
            <div class="admin-user-actions">${actions.join("")}</div>
          </article>`;
      }).join("");

      els.adminInviteList.onclick = function (ev) {
        const ipsBtn = ev.target?.closest?.("button[data-invite-ips]");
        if (ipsBtn?.dataset.inviteIps) {
          openInviteIpsDialog(parseInt(ipsBtn.dataset.inviteIps, 10));
          return;
        }
        const copyBtn = ev.target?.closest?.("button[data-invite-copy]");
        if (copyBtn?.dataset.inviteCopy) {
          const inv = state.adminInvites.find((i) => i.id === parseInt(copyBtn.dataset.inviteCopy, 10));
          if (inv?.url) copyInviteUrlToClipboard(inv.url);
          return;
        }
        const extendBtn = ev.target?.closest?.("button[data-invite-extend]");
        if (extendBtn?.dataset.inviteExtend) {
          extendAdminInvite(
            parseInt(extendBtn.dataset.inviteExtend, 10),
            extendBtn.dataset.validity || "7d"
          );
          return;
        }
        const reissueBtn = ev.target?.closest?.("button[data-invite-reissue]");
        if (reissueBtn?.dataset.inviteReissue) {
          reissueAdminInvite(parseInt(reissueBtn.dataset.inviteReissue, 10));
          return;
        }
        const btn = ev.target?.closest?.("button[data-invite-revoke]");
        if (!btn) return;
        revokeAdminInvite(parseInt(btn.dataset.inviteRevoke, 10));
      };
    } catch (e) {
      els.adminInviteList.innerHTML = `<p class="meta">${esc(e.message)}</p>`;
    }
  }

  async function copyInviteUrlToClipboard(url) {
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
    } catch (_e) {
      const tmp = document.createElement("textarea");
      tmp.value = url;
      document.body.appendChild(tmp);
      tmp.select();
      document.execCommand("copy");
      document.body.removeChild(tmp);
    }
    toast("Lien copié");
  }

  async function extendAdminInvite(id, validity) {
    if (!id || !validity) return;
    const isPermanent = validity === "permanent";
    const msg = isPermanent
      ? "Rendre cet invité permanent ? Son accès n'expirera plus."
      : `Prolonger cette invitation de ${validity} ?`;
    if (!confirm(msg)) return;
    try {
      await fetchJson(`/api/invites/${id}/extend`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ validity }),
      });
      toast(isPermanent ? "Accès rendu permanent" : "Invitation prolongée");
      loadAdminInvites();
    } catch (e) {
      toast(e.message || "Erreur prolongation");
    }
  }

  async function reissueAdminInvite(id) {
    if (!id) return;
    const msg = "Générer un lien de réactivation (10 min) ?\n\nLe prochain appareil qui l'ouvre sera autorisé. L'ancien lien ne marchera plus.";
    if (!confirm(msg)) return;
    try {
      const res = await fetchJson(`/api/invites/${id}/reissue`, { method: "POST" });
      if (!res.ok) throw new Error(res.error || "Erreur");
      if (res.url) await copyInviteUrlToClipboard(res.url);
      toast("Lien de réactivation copié (10 min)");
      loadAdminInvites();
    } catch (e) {
      toast(e.message || "Erreur réactivation");
    }
  }

  async function revokeAdminInvite(id) {
    if (!id || !confirm("Révoquer cette invitation ? Le compte invité et ses dégustations seront supprimés.")) return;
    try {
      await fetchJson(`/api/invites/${id}`, { method: "DELETE" });
      toast("Invitation révoquée");
      loadAdminInvites();
    } catch (e) {
      toast(e.message || "Erreur révocation");
    }
  }

  function renderAdminUserCard(u) {
    const isSelf = u.username === state.currentUser;
    const badge = u.is_admin ? '<span class="admin-badge">admin</span>' : "";
    const passInput = `<input type="password" placeholder="Nouveau mot de passe" data-pass-for="${esc(u.username)}" autocomplete="new-password" />`;
    const promoteBtn = u.is_admin
      ? `<button type="button" class="btn" data-action="demote" data-user="${esc(u.username)}" ${isSelf ? "disabled" : ""}>Retirer admin</button>`
      : `<button type="button" class="btn" data-action="promote" data-user="${esc(u.username)}">Promouvoir admin</button>`;
    return `
      <article class="admin-user-card">
        <div class="admin-user-top">
          <h3>${esc(u.username)}</h3>
          ${badge}
        </div>
        <div class="admin-user-meta">${u.checkins} dégustation(s)</div>
        <div class="admin-pass-row">
          ${passInput}
          <button type="button" class="btn" data-action="pass" data-user="${esc(u.username)}">MDP</button>
        </div>
        <div class="admin-user-actions">
          ${promoteBtn}
          <button type="button" class="btn" data-action="delete" data-user="${esc(u.username)}" ${isSelf ? "disabled" : ""}>Supprimer</button>
        </div>
      </article>`;
  }

  async function loadAdminUsers() {
    if (els.adminUserList) els.adminUserList.innerHTML = "<p class='meta'>Chargement…</p>";
    try {
      const users = await fetchJson("/api/admin/users");
      state.adminUsers = users || [];

      if (els.adminUserList) {
        if (!state.adminUsers.length) {
          els.adminUserList.innerHTML = "<p class='meta'>Aucun compte local.</p>";
        } else {
          els.adminUserList.innerHTML = state.adminUsers.map(renderAdminUserCard).join("");
          els.adminUserList.onclick = function (ev) {
            const btn = ev.target?.closest?.("button[data-action]");
            if (btn) handleAdminAction(btn);
          };
        }
      }
    } catch (e) {
      if (els.adminUserList) els.adminUserList.innerHTML = `<p class="meta">${esc(e.message)}</p>`;
    }
  }

  async function handleAdminAction(btn) {
    const user = btn.dataset.user;
    const action = btn.dataset.action;
    if (!user || !action) return;

    if (action === "pass") {
      const input = els.adminUserList.querySelector(`input[data-pass-for="${user}"]`);
      const password = (input?.value || "").trim();
      if (password.length < 6) {
        toast("Mot de passe : 6 caractères min.");
        return;
      }
      try {
        const data = await fetchJson(`/api/admin/users/${encodeURIComponent(user)}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ password }),
        });
        if (!data.ok) {
          toast(data.error || "Échec");
          return;
        }
        if (input) input.value = "";
        toast(`Mot de passe mis à jour — ${user}`);
      } catch (e) {
        toast(e.message || "Erreur");
      }
      return;
    }

    if (action === "delete") {
      if (!confirm(`Supprimer le compte « ${user} » ?`)) return;
      try {
        const data = await fetchJson(`/api/admin/users/${encodeURIComponent(user)}`, {
          method: "DELETE",
        });
        if (!data.ok) {
          toast(data.error || "Échec");
          return;
        }
        toast(`Compte ${user} supprimé`);
        loadAdminUsers();
      } catch (e) {
        toast(e.message || "Erreur");
      }
      return;
    }

    const isAdmin = action === "promote";
    try {
      const data = await fetchJson(`/api/admin/users/${encodeURIComponent(user)}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ is_admin: isAdmin }),
      });
      if (!data.ok) {
        toast(data.error || "Échec");
        return;
      }
      toast(isAdmin ? `${user} est admin` : `Admin retiré — ${user}`);
      loadAdminUsers();
    } catch (e) {
      toast(e.message || "Erreur");
    }
  }

  async function createAdminUser() {
    const username = (els.adminNewUser?.value || "").trim();
    const password = els.adminNewPass?.value || "";
    const isAdmin = !!els.adminNewIsAdmin?.checked;
    if (!username || password.length < 6) {
      toast("Identifiant + mot de passe (6 car. min.)");
      return;
    }
    if (els.btnAdminCreate) {
      els.btnAdminCreate.disabled = true;
      els.btnAdminCreate.textContent = "Création…";
    }
    try {
      const data = await fetchJson("/api/admin/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password, is_admin: isAdmin }),
      });
      if (!data.ok) {
        toast(data.error || "Création impossible");
        return;
      }
      if (els.adminNewUser) els.adminNewUser.value = "";
      if (els.adminNewPass) els.adminNewPass.value = "";
      if (els.adminNewIsAdmin) els.adminNewIsAdmin.checked = false;
      toast(`Compte ${username} créé ✓`);
      loadAdminUsers();
    } catch (e) {
      toast(e.message || "Erreur");
    } finally {
      if (els.btnAdminCreate) {
        els.btnAdminCreate.disabled = false;
        els.btnAdminCreate.textContent = "Créer le compte";
      }
    }
  }

  function renderAdminRefList(items, filterQ) {
    const q = normalizeSearch(filterQ || "");
    const filtered = (items || []).filter(
      (it) => !q || normalizeSearch(it.name).includes(q)
    );
    if (!filtered.length) return '<p class="meta tiny">Aucun</p>';
    return filtered
      .map((it) => {
        const badge = it.preset
          ? '<span class="admin-preset-badge">preset</span>'
          : "";
        const delBtn = `<button type="button" class="btn danger small" data-action="del" data-name="${esc(it.name)}">Suppr</button>`;
        return `<div class="admin-mgmt-item"><span class="name">${esc(it.name)}${badge}</span>${delBtn}</div>`;
      })
      .join("");
  }

  async function loadAdminStylesHops() {
    if (!els.adminStylesHops) return;
    els.adminStylesHops.innerHTML = "<p class='meta'>Chargement…</p>";
    try {
      const data = await fetchJson("/api/admin/referentials");
      const refs = {
        styles: data.styles || [],
        hops: data.hops || [],
        flavors: data.flavors || [],
      };

      els.adminStylesHops.innerHTML = `
        <div class="admin-ref-card">
          <div class="admin-ref-tabs" role="tablist">
            <button type="button" class="admin-ref-tab active" data-tab="styles">Styles (${refs.styles.length})</button>
            <button type="button" class="admin-ref-tab" data-tab="hops">Houblons (${refs.hops.length})</button>
            <button type="button" class="admin-ref-tab" data-tab="flavors">Saveurs (${refs.flavors.length})</button>
          </div>
          <p class="meta tiny admin-ref-hint">Tout est supprimable. Les presets (badge gris) reviennent si tu les ré-ajoutes avec +.</p>
          <div class="admin-ref-panel active" data-panel="styles">
            <div class="add-row">
              <input type="text" id="new-style-input" placeholder="Nouveau style" />
              <button type="button" class="btn small" id="add-style-btn">+</button>
            </div>
            <input type="search" class="admin-ref-search" data-search="styles" placeholder="Filtrer…" />
            <div class="admin-mgmt-list" id="styles-list"></div>
          </div>
          <div class="admin-ref-panel" data-panel="hops">
            <div class="add-row">
              <input type="text" id="new-hop-input" placeholder="Nouveau houblon" />
              <button type="button" class="btn small" id="add-hop-btn">+</button>
            </div>
            <input type="search" class="admin-ref-search" data-search="hops" placeholder="Filtrer…" />
            <div class="admin-mgmt-list" id="hops-list"></div>
          </div>
          <div class="admin-ref-panel" data-panel="flavors">
            <div class="add-row">
              <input type="text" id="new-flavor-input" placeholder="Nouvelle saveur" />
              <button type="button" class="btn small" id="add-flavor-btn">+</button>
            </div>
            <input type="search" class="admin-ref-search" data-search="flavors" placeholder="Filtrer…" />
            <div class="admin-mgmt-list" id="flavors-list"></div>
          </div>
        </div>
      `;

      const listEls = {
        styles: document.getElementById("styles-list"),
        hops: document.getElementById("hops-list"),
        flavors: document.getElementById("flavors-list"),
      };
      const searchVals = { styles: "", hops: "", flavors: "" };

      function renderLists() {
        listEls.styles.innerHTML = renderAdminRefList(refs.styles, searchVals.styles);
        listEls.hops.innerHTML = renderAdminRefList(refs.hops, searchVals.hops);
        listEls.flavors.innerHTML = renderAdminRefList(refs.flavors, searchVals.flavors);
      }
      renderLists();

      els.adminStylesHops.querySelectorAll(".admin-ref-tab").forEach((tab) => {
        tab.onclick = () => {
          const key = tab.dataset.tab;
          els.adminStylesHops.querySelectorAll(".admin-ref-tab").forEach((t) => {
            t.classList.toggle("active", t.dataset.tab === key);
          });
          els.adminStylesHops.querySelectorAll(".admin-ref-panel").forEach((p) => {
            p.classList.toggle("active", p.dataset.panel === key);
          });
        };
      });

      els.adminStylesHops.querySelectorAll(".admin-ref-search").forEach((inp) => {
        inp.oninput = () => {
          searchVals[inp.dataset.search] = inp.value || "";
          renderLists();
        };
      });

      const bindAdd = (btnId, inputId, url, label, bodyKey = "name") => {
        const btn = document.getElementById(btnId);
        const input = document.getElementById(inputId);
        if (!btn || !input) return;
        const submit = async () => {
          const val = input.value.trim();
          if (val.length < 2) {
            toast("Nom trop court");
            return;
          }
          try {
            await fetchJson(url, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ [bodyKey]: val }),
            });
            toast(`${label} ajouté ✓`);
            input.value = "";
            loadAdminStylesHops();
          } catch (e) {
            toast(e.message || "Erreur");
          }
        };
        btn.onclick = submit;
        input.onkeydown = (e) => {
          if (e.key === "Enter") submit();
        };
      };

      bindAdd("add-style-btn", "new-style-input", "/api/styles", "Style");
      bindAdd("add-hop-btn", "new-hop-input", "/api/hops", "Houblon");
      bindAdd("add-flavor-btn", "new-flavor-input", "/api/flavors/custom", "Saveur");

      els.adminStylesHops.onclick = async (ev) => {
        const btn = ev.target.closest("button[data-action='del']");
        if (!btn) return;
        const nm = btn.dataset.name;
        if (!nm) return;
        const panel = btn.closest(".admin-ref-panel");
        const kind = panel?.dataset.panel;
        if (!kind) return;
        const urlMap = {
          styles: `/api/styles/${encodeURIComponent(nm)}`,
          hops: `/api/hops/${encodeURIComponent(nm)}`,
          flavors: `/api/flavors/custom/${encodeURIComponent(nm)}`,
        };
        const url = urlMap[kind];
        if (!url) return;
        if (!confirm(`Supprimer « ${nm} » ?`)) return;
        try {
          const res = await fetchJson(url, { method: "DELETE" });
          if (!res.ok) throw new Error(res.error || "Suppression impossible");
          toast("Supprimé ✓");
          loadAdminStylesHops();
        } catch (e) {
          toast(e.message || "Erreur suppression");
        }
      };
    } catch (e) {
      els.adminStylesHops.innerHTML = `<p class="meta">Erreur: ${esc(e.message)}</p>`;
    }
  }

  let swReloading = false;
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (swReloading) return;
      swReloading = true;
      window.location.reload();
    });
  }

  async function purgeBeerCaches() {
    if ("serviceWorker" in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map((reg) => reg.unregister()));
    }
    if ("caches" in window) {
      const keys = await caches.keys();
      await Promise.all(keys.map((key) => caches.delete(key)));
    }
  }

  async function forceBeerUpdate(serverVer) {
    if (window.__beerForceUpdating) return;
    window.__beerForceUpdating = true;
    try {
      await purgeBeerCaches();
    } catch (_) {
      /* ignore */
    }
    const bust = serverVer || Date.now();
    window.location.replace(`${api("/app")}?_=${encodeURIComponent(bust)}`);
  }

  async function checkBeerVersion() {
    const local = window.BEER_VERSION || "";
    if (!local || window.__beerForceUpdating) return;
    try {
      const r = await fetch(api("/api/version"), { cache: "no-store", credentials: (window.BEER_MOBILE ? "include" : "same-origin") });
      if (!r.ok) return;
      const d = await r.json();
      if (d.version && d.version !== local) {
        await forceBeerUpdate(d.version);
      }
    } catch (_) {
      /* ignore */
    }
  }

  function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return;
    const scope = ROOT ? `${ROOT}/` : "/";
    const ver = window.BEER_VERSION || "";
    const swUrl = `${ROOT || ""}/sw.js?v=${encodeURIComponent(ver)}`;
    navigator.serviceWorker.register(swUrl, { scope }).then((reg) => {
      reg.update();
      if (reg.waiting) {
        reg.waiting.postMessage({ type: "SKIP_WAITING" });
      }
      reg.addEventListener("updatefound", () => {
        const worker = reg.installing;
        if (!worker) return;
        worker.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) {
            worker.postMessage({ type: "SKIP_WAITING" });
          }
        });
      });
      window.setInterval(() => reg.update(), 5 * 60 * 1000);
    }).catch(() => {});
    checkBeerVersion();
    window.setInterval(checkBeerVersion, 5 * 60 * 1000);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") checkBeerVersion();
    });
    window.addEventListener("focus", checkBeerVersion);
  }

  function isPwaInstalled() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    );
  }

  function maybeShowPwaHint() {
    if (!state.isInvite || isPwaInstalled()) return;
    if (localStorage.getItem("beer_pwa_hint_dismissed") === "1") return;
    els.pwaHintBar?.classList.remove("hidden");
  }

  function applyInviteUi() {
    const hide = state.isInvite;
    if (els.btnWishlist) els.btnWishlist.classList.toggle("hidden", hide);
    if (els.btnGifts) els.btnGifts.classList.toggle("hidden", hide);
    if (els.btnAddWishlist) els.btnAddWishlist.classList.add("hidden");
    if (hide) {
      els.wishlistPanel?.classList.add("hidden");
      els.giftsPanel?.classList.add("hidden");
    }
    if (els.inviteHelpBar) {
      const showHelp =
        hide && localStorage.getItem("beer_invite_tip_dismissed") !== "1";
      els.inviteHelpBar.classList.toggle("hidden", !showHelp);
    }
    if (!hide) {
      els.pwaHintBar?.classList.add("hidden");
    }
  }

  function showMobileSessionBar(user, mode) {
    if (!window.BEER_MOBILE) return;
    const bar = document.getElementById("mobile-session-bar");
    const label = document.getElementById("mobile-session-user");
    if (!bar || !label) return;
    let text = "Non connecté";
    if (user) {
      let role = "";
      if (state.isAdmin) role = " · admin";
      else if (state.isInvite) role = " · invité";
      text = "Connecté · " + user + role;
    } else if (mode === "offline") {
      const cached = localStorage.getItem("beer_mobile_user");
      text = cached ? "Hors ligne · " + cached : "Hors ligne · compte inconnu";
    }
    label.textContent = text;
    bar.classList.remove("hidden");
    const mLogout = document.getElementById("btn-mobile-logout");
    if (mLogout) {
      mLogout.classList.toggle("hidden", !user);
      if (!mLogout.__bound) {
        mLogout.__bound = true;
        mLogout.addEventListener("click", logout);
      }
    }
  }

  async function loadSession() {
    const cached = localStorage.getItem("beer_mobile_user");
    if (cached && window.BEER_MOBILE) showMobileSessionBar(cached, "cached");

    try {
      const r = await fetchApi("/api/me");
      if (!r.ok) throw new Error("session");
      const d = await r.json();
      if (d.auth && !d.user) {
        localStorage.removeItem("beer_mobile_user");
        clearBeerSession();
        window.location.replace(window.BEER_MOBILE ? "./login.html" : api("/"));
        return;
      }
      state.currentUser = d.user || null;
      state.isAdmin = !!d.is_admin;
      state.isInvite = !!d.is_invite;
      if (d.user) localStorage.setItem("beer_mobile_user", d.user);
      if (d.auth && d.user && els.userPill) {
        els.userPill.textContent = d.user;
        els.userPill.classList.remove("hidden");
      }
      if (d.auth && d.user && !d.is_invite && els.btnLogout) {
        els.btnLogout.classList.remove("hidden");
      } else if (els.btnLogout) {
        els.btnLogout.classList.add("hidden");
      }
      if (d.is_admin && els.btnAdmin) {
        els.btnAdmin.classList.remove("hidden");
      }
      if (d.is_admin && els.btnPatchnotes) {
        els.btnPatchnotes.classList.remove("hidden");
      } else if (els.btnPatchnotes) {
        els.btnPatchnotes.classList.add("hidden");
      }
      applyInviteUi();
      showMobileSessionBar(d.user, "online");
    } catch (e) {
      if (window.BEER_MOBILE) {
        const offlineUser = localStorage.getItem("beer_mobile_user");
        showMobileSessionBar(offlineUser, offlineUser ? "offline" : "none");
        if (!offlineUser) {
          window.location.replace("./login.html");
        }
      }
    }
  }

  function logout() {
    if (window.BEER_MOBILE) {
      fetch(api("/api/logout"), { method: "POST", credentials: "include" })
        .catch(function () {})
        .finally(function () {
          localStorage.removeItem("beer_mobile_user");
          clearBeerSession();
          window.location.replace("./login.html");
        });
      return;
    }
    window.location.replace(api("/logout"));
  }

  function init() {
    bindElements();
    if (!els.sliderTrack || !els.scanInput) {
      console.error("Beer Log: éléments DOM manquants");
      return;
    }
    bindEvents();
    initScanMode();
    // Populate dynamic styles (replaces static options) + hops on demand in step3
    loadLocalStyleOptions().catch(() => {});
    // init min rating range display
    if (els.historyFilterRating) {
      els.historyFilterRating.value = state.historyFilters.minRating || 0;
      loadHistoryRatingFilter();
    }
    if (els.btnLogout) {
      els.btnLogout.addEventListener("click", (e) => {
        els.btnLogout.disabled = true;
        logout();
      });
    }
    loadSession();
    if (!window.BEER_MOBILE) registerServiceWorker();
    // Offline write queue: flush pending ops on init and when network comes back
    window.addEventListener("online", function () {
      flushWriteQueue().catch(function () {});
    });
    flushWriteQueue().catch(function () {});
    updateStars();
    state.step = 1;
    els.panels.forEach((p) => p.classList.toggle("active", Number(p.dataset.panel) === 1));
    showUntappdPanel(true);
    updateStepButtons();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
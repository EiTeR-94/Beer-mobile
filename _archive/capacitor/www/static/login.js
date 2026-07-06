(function () {
  "use strict";

  const ROOT = (window.BEER_ROOT || "").replace(/\/$/, "");
  const api = (path) => `${ROOT}${path}`;

  const form = document.getElementById("login-form");
  const userInput = document.getElementById("login-user");
  const passInput = document.getElementById("login-pass");
  const errEl = document.getElementById("login-error");
  const btn = document.getElementById("btn-login");

  function showError(msg) {
    if (!errEl) return;
    errEl.textContent = msg || "";
    errEl.classList.toggle("hidden", !msg);
  }

  async function tryLogin(ev) {
    ev.preventDefault();
    showError("");
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Connexion…";
    }
    try {
      const r = await fetch(api("/api/login"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({
          username: (userInput?.value || "").trim(),
          password: passInput?.value || "",
        }),
      });
      const data = await r.json().catch(() => ({}));
      if (!r.ok || !data.ok) {
        showError(data.detail || data.error || "Identifiants incorrects");
        return;
      }
      if (data.user && window.BEER_MOBILE) localStorage.setItem("beer_mobile_user", data.user);
      window.location.replace(window.BEER_MOBILE ? "./index.html" : api("/app"));
    } catch (e) {
      showError("Connexion impossible");
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = "Se connecter";
      }
    }
  }

  if (form) form.addEventListener("submit", tryLogin);

  fetch(api("/api/me"), { credentials: "include" })
    .then((r) => (r.ok ? r.json() : null))
    .then((d) => {
      if (d?.user) {
        if (window.BEER_MOBILE) localStorage.setItem("beer_mobile_user", d.user);
        window.location.replace(window.BEER_MOBILE ? "./index.html" : api("/app"));
      }
    })
    .catch(() => {});
})();
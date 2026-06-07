// Dromo landing page — light interactions, no dependencies.

(function () {
  "use strict";

  // ---- Footer year ----
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  // ---- Animated cadence readout (cosmetic) ----
  var bpm = document.getElementById("bpm-readout");
  if (bpm && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    var values = [164, 166, 168, 170, 168, 172, 170, 168];
    var i = 0;
    setInterval(function () {
      i = (i + 1) % values.length;
      bpm.textContent = String(values[i]);
    }, 1400);
  }

  // ---- Waitlist storage: Supabase ----
  // Sign-ups POST into the `waitlist` table of project prftbirfbzhdacuenatw. The
  // publishable key is meant to be public — it grants INSERT only (insert-only RLS;
  // the list can't be read back through it). Read sign-ups in the Supabase dashboard
  // (Table editor -> waitlist).
  var SUPABASE_URL = "https://prftbirfbzhdacuenatw.supabase.co";
  var SUPABASE_KEY = "sb_publishable_F17HeWBPWHvDkJtImrHxOg_W4ecrlvP";

  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  function wireForm(formId, noteId) {
    var form = document.getElementById(formId);
    var note = document.getElementById(noteId);
    if (!form || !note) return;

    var defaultNote = note.textContent;

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      note.classList.remove("is-success", "is-error");

      var input = form.querySelector('input[type="email"]');
      var email = (input.value || "").trim();

      if (!EMAIL_RE.test(email)) {
        note.textContent = "Please enter a valid email address.";
        note.classList.add("is-error");
        input.focus();
        return;
      }

      var btn = form.querySelector("button");
      btn.disabled = true;
      var btnLabel = btn.textContent;
      btn.textContent = "…";

      submit(email)
        .then(function () {
          form.reset();
          note.textContent = "You're on the list — we'll be in touch. 🏃";
          note.classList.add("is-success");
        })
        .catch(function () {
          note.textContent = "Something went wrong. Please try again.";
          note.classList.add("is-error");
        })
        .finally(function () {
          btn.disabled = false;
          btn.textContent = btnLabel;
          setTimeout(function () {
            if (note.classList.contains("is-success")) return;
            note.textContent = defaultNote;
            note.classList.remove("is-error");
          }, 6000);
        });
    });
  }

  function submit(email) {
    return fetch(SUPABASE_URL + "/rest/v1/waitlist", {
      method: "POST",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: "Bearer " + SUPABASE_KEY,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ email: email, source: "landing" }),
    }).then(function (res) {
      if (res.ok) return;             // 201 — added
      if (res.status === 409) return; // already on the list — treat as success
      throw new Error("waitlist insert failed: " + res.status);
    });
  }

  wireForm("waitlist-hero", "waitlist-hero-note");
  wireForm("waitlist-cta", "waitlist-cta-note");
})();
